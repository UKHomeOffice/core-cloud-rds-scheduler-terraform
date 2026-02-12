"""
Aurora Cluster Scheduled Stop/Start

Discovers Aurora clusters by tag and performs Start/Stop actions.
Called by AWS SSM Automation as an aws:executeScript step.

Cluster eligibility (matching PoC logic):
  - Skip Serverless v1       (engine_mode = "serverless")
  - Skip multi-master        (engine_mode = "multimaster")
  - Skip parallel query       (engine_mode = "parallelquery")
  - Skip global database      (engine_mode = "global")
  - Skip Multi-AZ DB Clusters (non-Aurora, detected by DBClusterInstanceClass)
"""

import boto3
import time
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
ACTION_START = "start"
ACTION_STOP = "stop"

STATUS_AVAILABLE = "available"
STATUS_STOPPED = "stopped"
STATUS_STARTING = "starting"
STATUS_STOPPING = "stopping"

UNSTOPPABLE_ENGINE_MODES = {"global", "parallelquery", "multimaster", "serverless"}

MAX_RETRIES = 3
RETRY_DELAY_SECONDS = 5


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def is_multi_az_db_cluster(cluster):
    """
    Multi-AZ DB Clusters (non-Aurora) have a DBClusterInstanceClass field
    that Aurora clusters lack. These cannot be stopped.
    """
    engine = cluster.get("Engine", "")
    has_instance_class = "DBClusterInstanceClass" in cluster
    return engine.startswith(("mysql", "postgres")) and has_instance_class


def is_stoppable_cluster(cluster):
    """Return True if the cluster type supports stop/start."""
    cluster_id = cluster["DBClusterIdentifier"]
    engine_mode = cluster.get("EngineMode", "provisioned").lower()

    if engine_mode in UNSTOPPABLE_ENGINE_MODES:
        logger.info(
            "Cluster '%s' has engine mode '%s' — skipping.",
            cluster_id, engine_mode,
        )
        return False

    if is_multi_az_db_cluster(cluster):
        logger.info(
            "Cluster '%s' is a Multi-AZ DB Cluster — skipping.",
            cluster_id,
        )
        return False

    return True


def has_schedule_tag(rds_client, cluster_arn, tag_key):
    """Check whether the cluster has the opt-in tag."""
    try:
        tags = rds_client.list_tags_for_resource(ResourceName=cluster_arn)["TagList"]
        return any(tag["Key"] == tag_key for tag in tags)
    except Exception as exc:
        logger.warning("Failed to list tags for '%s': %s. Skipping.", cluster_arn, exc)
        return False


def perform_action_with_retry(rds_client, cluster_id, action):
    """
    Execute start/stop with retry for transient errors.
    InvalidDBClusterStateFault is not retried — it won't resolve by retrying.
    """
    api_call = (
        rds_client.start_db_cluster
        if action == ACTION_START
        else rds_client.stop_db_cluster
    )

    last_exception = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            api_call(DBClusterIdentifier=cluster_id)
            time.sleep(1)
            response = rds_client.describe_db_clusters(DBClusterIdentifier=cluster_id)
            new_status = response["DBClusters"][0]["Status"]
            logger.info(
                "Action '%s' succeeded on '%s' (attempt %d). New status: %s",
                action, cluster_id, attempt, new_status,
            )
            return new_status
        except rds_client.exceptions.InvalidDBClusterStateFault:
            raise
        except Exception as exc:
            last_exception = exc
            logger.warning(
                "Attempt %d/%d failed for '%s' on '%s': %s",
                attempt, MAX_RETRIES, action, cluster_id, exc,
            )
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_DELAY_SECONDS)

    raise last_exception


def process_cluster(rds_client, cluster_id, action):
    """
    Process a single cluster. Returns outcome: processed, skipped, or failed.
    """
    result = {"cluster_id": cluster_id, "outcome": "failed", "message": "", "status": ""}

    try:
        response = rds_client.describe_db_clusters(DBClusterIdentifier=cluster_id)
        current_status = response["DBClusters"][0]["Status"]
        result["status"] = current_status

        if action == ACTION_START:
            if current_status in (STATUS_AVAILABLE, STATUS_STARTING):
                result["outcome"] = "skipped"
                result["message"] = f"Already '{current_status}' — no action needed."
                return result
            if current_status != STATUS_STOPPED:
                result["outcome"] = "skipped"
                result["message"] = f"Cannot start from '{current_status}' state."
                return result

        elif action == ACTION_STOP:
            if current_status in (STATUS_STOPPED, STATUS_STOPPING):
                result["outcome"] = "skipped"
                result["message"] = f"Already '{current_status}' — no action needed."
                return result
            if current_status != STATUS_AVAILABLE:
                result["outcome"] = "skipped"
                result["message"] = f"Cannot stop from '{current_status}' state."
                return result

        new_status = perform_action_with_retry(rds_client, cluster_id, action)
        result["outcome"] = "processed"
        result["status"] = new_status
        result["message"] = f"Action '{action}' initiated successfully."

    except Exception as exc:
        result["outcome"] = "failed"
        result["message"] = str(exc)
        logger.error("Failed to %s cluster '%s': %s", action, cluster_id, exc)

    return result


# ---------------------------------------------------------------------------
# Main handler — SSM entry point
# ---------------------------------------------------------------------------
def handler(event, context):
    """
    SSM Automation aws:executeScript entry point.

    Input:  Action ("Start" or "Stop"), ScheduleTagKey (default "Schedule")
    Output: ProcessedClusters, SkippedClusters, FailedClusters
    """
    action = event.get("Action", "").lower()
    tag_key = event.get("ScheduleTagKey", "Schedule")

    if action not in (ACTION_START, ACTION_STOP):
        raise ValueError(f"Invalid Action '{event.get('Action')}'. Must be 'Start' or 'Stop'.")

    rds_client = boto3.client("rds")

    # Step 1: Discover all clusters
    logger.info("Discovering clusters with tag '%s'...", tag_key)
    paginator = rds_client.get_paginator("describe_db_clusters")
    all_clusters = []
    for page in paginator.paginate():
        all_clusters.extend(page["DBClusters"])
    logger.info("Found %d total clusters.", len(all_clusters))

    # Step 2: Filter to eligible tagged clusters
    eligible = []
    for cluster in all_clusters:
        if not is_stoppable_cluster(cluster):
            continue
        if not has_schedule_tag(rds_client, cluster["DBClusterArn"], tag_key):
            continue
        eligible.append(cluster["DBClusterIdentifier"])

    logger.info("Found %d eligible clusters: %s", len(eligible), eligible)

    # Step 3: Process each cluster
    processed, skipped, failed = [], [], []

    for cluster_id in eligible:
        result = process_cluster(rds_client, cluster_id, action)
        logger.info("Cluster '%s': %s — %s", cluster_id, result["outcome"], result["message"])

        if result["outcome"] == "processed":
            processed.append(cluster_id)
        elif result["outcome"] == "skipped":
            skipped.append(cluster_id)
        else:
            failed.append(cluster_id)

    logger.info(
        "Done. Action=%s | Processed=%d | Skipped=%d | Failed=%d",
        action, len(processed), len(skipped), len(failed),
    )

    return {
        "ProcessedClusters": processed,
        "SkippedClusters": skipped,
        "FailedClusters": failed,
    }