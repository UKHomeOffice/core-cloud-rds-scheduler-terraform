################################################################################
# RDS Scheduled Stop/Start Module
#
# Uses AWS SSM State Manager to stop/start RDS instances and Aurora clusters
# on a schedule. Resources opt-in by having a "Schedule" tag.
#
# - RDS Instances: Uses AWS managed documents (AWS-StartRdsInstance/AWS-StopRdsInstance)
# - Aurora Clusters: Uses a custom SSM Automation Document (clusters can't be
#   targeted by tag natively)
################################################################################

# ------------------------------------------------------------------------------
# SSM Associations — RDS Instances (AWS Managed Documents)
# ------------------------------------------------------------------------------

#checkov:skip=CCL_COSMOS_FINOPS_TAGS:SSM associations do not support tags - AWS resource limitation
resource "aws_ssm_association" "start_rds_instances" {
  name                = "AWS-StartRdsInstance"
  association_name    = "${var.name_prefix}-start-rds-instances"
  schedule_expression = var.start_schedule

  parameters = {
    InstanceId           = ""
    AutomationAssumeRole = var.automation_role_arn
  }

  targets {
    key    = "tag-key"
    values = [var.schedule_tag_key]
  }

  automation_target_parameter_name = "InstanceId"
}

#checkov:skip=CCL_COSMOS_FINOPS_TAGS:SSM associations do not support tags - AWS resource limitation
resource "aws_ssm_association" "stop_rds_instances" {
  name                = "AWS-StopRdsInstance"
  association_name    = "${var.name_prefix}-stop-rds-instances"
  schedule_expression = var.stop_schedule

  parameters = {
    InstanceId           = ""
    AutomationAssumeRole = var.automation_role_arn
  }

  targets {
    key    = "tag-key"
    values = [var.schedule_tag_key]
  }

  automation_target_parameter_name = "InstanceId"
}

# ------------------------------------------------------------------------------
# SSM Associations — Aurora Clusters (Custom Document)
# ------------------------------------------------------------------------------

#checkov:skip=CCL_COSMOS_FINOPS_TAGS:SSM associations do not support tags - AWS resource limitation
resource "aws_ssm_association" "start_aurora_clusters" {
  name                = aws_ssm_document.aurora_cluster_scheduler.name
  association_name    = "${var.name_prefix}-start-aurora-clusters"
  schedule_expression = var.aurora_start_schedule

  parameters = {
    AutomationAssumeRole = var.automation_role_arn
    Action               = "Start"
    ScheduleTagKey       = var.schedule_tag_key
  }
}

#checkov:skip=CCL_COSMOS_FINOPS_TAGS:SSM associations do not support tags - AWS resource limitation
resource "aws_ssm_association" "stop_aurora_clusters" {
  name                = aws_ssm_document.aurora_cluster_scheduler.name
  association_name    = "${var.name_prefix}-stop-aurora-clusters"
  schedule_expression = var.aurora_stop_schedule

  parameters = {
    AutomationAssumeRole = var.automation_role_arn
    Action               = "Stop"
    ScheduleTagKey       = var.schedule_tag_key
  }
}

# ------------------------------------------------------------------------------
# SSM Automation Document — Aurora Cluster Discovery + Stop/Start
# ------------------------------------------------------------------------------

resource "aws_ssm_document" "aurora_cluster_scheduler" {
  name            = "${var.name_prefix}-aurora-cluster-scheduler"
  document_type   = "Automation"
  document_format = "JSON"
  tags            = var.tags

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Discover Aurora clusters by tag and perform Start/Stop actions."
    assumeRole    = "{{AutomationAssumeRole}}"

    parameters = {
      AutomationAssumeRole = {
        type           = "String"
        description    = "The ARN of the role that allows Automation to perform the actions on your behalf."
        default        = ""
        allowedPattern = "^arn:aws[a-z0-9-]*:iam::\\d{12}:role/[\\w+=,.@_/-]+|^$"
      }
      Action = {
        type          = "String"
        description   = "The action to take: Start or Stop."
        allowedValues = ["Start", "Stop"]
      }
      ScheduleTagKey = {
        type        = "String"
        description = "The tag key used to identify opt-in clusters."
        default     = "Schedule"
      }
    }

    mainSteps = [
      {
        name   = "discoverAndManageClusters"
        action = "aws:executeScript"
        inputs = {
          Runtime = "python3.11"
          Handler = "handler"
          Script  = file("${path.module}/scripts/aurora_cluster_scheduler.py")
          InputPayload = {
            Action         = "{{Action}}"
            ScheduleTagKey = "{{ScheduleTagKey}}"
          }
        }
        outputs = [
          {
            Name     = "ProcessedClusters"
            Selector = "$.Payload.ProcessedClusters"
            Type     = "StringList"
          },
          {
            Name     = "SkippedClusters"
            Selector = "$.Payload.SkippedClusters"
            Type     = "StringList"
          },
          {
            Name     = "FailedClusters"
            Selector = "$.Payload.FailedClusters"
            Type     = "StringList"
          }
        ]
      }
    ]
  })
}