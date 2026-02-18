# This tells Terraform: "Don't connect to real AWS. Fake it."
# Without this, you'd need AWS credentials to run the tests.
mock_provider "aws" {}

# These variables apply to ALL run blocks in this file (unless overridden).
# They're the minimum required inputs for our module.
variables {
  name_prefix         = "cc-test-scheduler"
  automation_role_arn = "arn:aws:iam::123456789012:role/test-role"
}

# TEST 1: Basic plan succeeds

run "plan_succeeds_with_defaults" {
  command = plan

  assert {
    condition     = aws_ssm_document.aurora_cluster_scheduler.name == "cc-test-scheduler-aurora-cluster-scheduler"
    error_message = "SSM document should be created with the correct name"
  }
}

# TEST 2: All resource names use the name_prefix

run "resource_names_use_prefix" {
  command = plan

  assert {
    condition     = aws_ssm_association.start_rds_instances.association_name == "cc-test-scheduler-start-rds-instances"
    error_message = "Start RDS instances name should be 'cc-test-scheduler-start-rds-instances'"
  }

  assert {
    condition     = aws_ssm_association.stop_rds_instances.association_name == "cc-test-scheduler-stop-rds-instances"
    error_message = "Stop RDS instances name should be 'cc-test-scheduler-stop-rds-instances'"
  }

  assert {
    condition     = aws_ssm_association.start_aurora_clusters.association_name == "cc-test-scheduler-start-aurora-clusters"
    error_message = "Start Aurora clusters name should be 'cc-test-scheduler-start-aurora-clusters'"
  }

  assert {
    condition     = aws_ssm_association.stop_aurora_clusters.association_name == "cc-test-scheduler-stop-aurora-clusters"
    error_message = "Stop Aurora clusters name should be 'cc-test-scheduler-stop-aurora-clusters'"
  }

  assert {
    condition     = aws_ssm_document.aurora_cluster_scheduler.name == "cc-test-scheduler-aurora-cluster-scheduler"
    error_message = "SSM document name should be 'cc-test-scheduler-aurora-cluster-scheduler'"
  }
}

# TEST 3: RDS instance associations use the correct AWS managed documents

run "instance_associations_use_managed_documents" {
  command = plan

  assert {
    condition     = aws_ssm_association.start_rds_instances.name == "AWS-StartRdsInstance"
    error_message = "Start instances must use 'AWS-StartRdsInstance'"
  }

  assert {
    condition     = aws_ssm_association.stop_rds_instances.name == "AWS-StopRdsInstance"
    error_message = "Stop instances must use 'AWS-StopRdsInstance'"
  }
}

# TEST 4: Default schedules are weekday-only

run "default_schedules_are_weekday_only" {
  command = plan

  # Instance start: 08:00 UTC weekdays
  assert {
    condition     = aws_ssm_association.start_rds_instances.schedule_expression == "cron(0 8 ? * MON-FRI *)"
    error_message = "Default instance start should be 08:00 UTC weekdays"
  }

  # Instance stop: 18:00 UTC weekdays
  assert {
    condition     = aws_ssm_association.stop_rds_instances.schedule_expression == "cron(0 18 ? * MON-FRI *)"
    error_message = "Default instance stop should be 18:00 UTC weekdays"
  }

  # Aurora start: 09:00 UTC weekdays (1hr after instances)
  assert {
    condition     = aws_ssm_association.start_aurora_clusters.schedule_expression == "cron(0 9 ? * MON-FRI *)"
    error_message = "Default Aurora start should be 09:00 UTC weekdays"
  }

  # Aurora stop: 17:00 UTC weekdays (1hr before instances)
  assert {
    condition     = aws_ssm_association.stop_aurora_clusters.schedule_expression == "cron(0 17 ? * MON-FRI *)"
    error_message = "Default Aurora stop should be 17:00 UTC weekdays"
  }
}

# TEST 5: RDS instance associations target by Schedule tag .. This is how SSM finds which instances to stop/start. The targets

run "instance_associations_target_by_tag" {
  command = plan

  assert {
    condition     = aws_ssm_association.start_rds_instances.targets[0].key == "tag-key"
    error_message = "Start instances should target by 'tag-key'"
  }

  assert {
    condition     = contains(aws_ssm_association.start_rds_instances.targets[0].values, "Schedule")
    error_message = "Start instances should look for the 'Schedule' tag"
  }

  assert {
    condition     = aws_ssm_association.stop_rds_instances.targets[0].key == "tag-key"
    error_message = "Stop instances should target by 'tag-key'"
  }

  assert {
    condition     = contains(aws_ssm_association.stop_rds_instances.targets[0].values, "Schedule")
    error_message = "Stop instances should look for the 'Schedule' tag"
  }
}


# TEST 6: IAM role ARN is passed to all 4 associations .Every association needs the IAM role so SSM can assume it. If one

run "role_arn_passed_to_all_associations" {
  command = plan

  assert {
    condition     = aws_ssm_association.start_rds_instances.parameters["AutomationAssumeRole"] == "arn:aws:iam::123456789012:role/test-role"
    error_message = "Start RDS instances must have the role ARN"
  }

  assert {
    condition     = aws_ssm_association.stop_rds_instances.parameters["AutomationAssumeRole"] == "arn:aws:iam::123456789012:role/test-role"
    error_message = "Stop RDS instances must have the role ARN"
  }

  assert {
    condition     = aws_ssm_association.start_aurora_clusters.parameters["AutomationAssumeRole"] == "arn:aws:iam::123456789012:role/test-role"
    error_message = "Start Aurora clusters must have the role ARN"
  }

  assert {
    condition     = aws_ssm_association.stop_aurora_clusters.parameters["AutomationAssumeRole"] == "arn:aws:iam::123456789012:role/test-role"
    error_message = "Stop Aurora clusters must have the role ARN"
  }
}

# TEST 7: Module outputs return expected values. Consumers of this module depend on these outputs 
run "outputs_are_populated" {
  command = plan

  assert {
    condition     = output.ssm_document_name == "cc-test-scheduler-aurora-cluster-scheduler"
    error_message = "ssm_document_name output should match document name"
  }
}
