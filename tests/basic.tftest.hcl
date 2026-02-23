# This tells Terraform: "Don't connect to real AWS. Fake it."
# Without this, you'd need AWS credentials to run the tests.
mock_provider "aws" {}

# provider "aws" {
#   region = "eu-west-2"
# }
# run "default_schedules_are_weekday_only" {
#   command = apply

#   assert {
#     condition     = aws_ssm_association.start_aurora_clusters["MON"].schedule_expression == "cron(0 8 ? * MON *)"
#     error_message = "Default Aurora start on MON should be cron(0 8 ? * MON *)"
#   }
# }



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
    condition     = aws_ssm_association.start_rds_instances["MON"].association_name == "cc-test-scheduler-start-rds-instances-mon"
    error_message = "Start RDS instances MON should use name_prefix"
  }

  assert {
    condition     = aws_ssm_association.stop_rds_instances["MON"].association_name == "cc-test-scheduler-stop-rds-instances-mon"
    error_message = "Stop RDS instances MON should use name_prefix"
  }

  assert {
    condition     = aws_ssm_association.start_aurora_clusters["MON"].association_name == "cc-test-scheduler-start-aurora-clusters-mon"
    error_message = "Start Aurora clusters MON should use name_prefix"
  }

  assert {
    condition     = aws_ssm_association.stop_aurora_clusters["MON"].association_name == "cc-test-scheduler-stop-aurora-clusters-mon"
    error_message = "Stop Aurora clusters MON should use name_prefix"
  }

  assert {
    condition     = aws_ssm_document.aurora_cluster_scheduler.name == "cc-test-scheduler-aurora-cluster-scheduler"
    error_message = "SSM document name should use name_prefix"
  }
}



# TEST 3: Creates one association per weekday (5 each)


run "creates_association_per_weekday" {
  command = plan

  assert {
    condition     = length(aws_ssm_association.start_rds_instances) == 5
    error_message = "Should create 5 start RDS instance associations (one per weekday)"
  }

  assert {
    condition     = length(aws_ssm_association.stop_rds_instances) == 5
    error_message = "Should create 5 stop RDS instance associations (one per weekday)"
  }

  assert {
    condition     = length(aws_ssm_association.start_aurora_clusters) == 5
    error_message = "Should create 5 start Aurora associations (one per weekday)"
  }

  assert {
    condition     = length(aws_ssm_association.stop_aurora_clusters) == 5
    error_message = "Should create 5 stop Aurora associations (one per weekday)"
  }
}
# TEST 4: Default schedules are weekday-only

run "default_schedules_are_weekday_only" {
  command = plan

  assert {
    condition     = aws_ssm_association.start_rds_instances["MON"].schedule_expression == "cron(0 8 ? * MON *)"
    error_message = "Default instance start on MON should be cron(0 8 ? * MON *)"
  }

  assert {
    condition     = aws_ssm_association.start_rds_instances["FRI"].schedule_expression == "cron(0 8 ? * FRI *)"
    error_message = "Default instance start on FRI should be cron(0 8 ? * FRI *)"
  }

  assert {
    condition     = aws_ssm_association.stop_rds_instances["MON"].schedule_expression == "cron(0 18 ? * MON *)"
    error_message = "Default instance stop on MON should be cron(0 18 ? * MON *)"
  }

  assert {
    condition     = aws_ssm_association.start_aurora_clusters["MON"].schedule_expression == "cron(0 8 ? * MON *)"
    error_message = "Default Aurora start on MON should be cron(0 8 ? * MON *)"
  }

  assert {
    condition     = aws_ssm_association.stop_aurora_clusters["MON"].schedule_expression == "cron(0 18 ? * MON *)"
    error_message = "Default Aurora stop on MON should be cron(0 18 ? * MON *)"
  }
}

# TEST 5: RDS instance associations target by Schedule tag .. This is how SSM finds which instances to stop/start. The targets

run "instance_associations_target_by_tag" {
  command = plan

  assert {
    condition     = aws_ssm_association.start_rds_instances["MON"].targets[0].key == "tag-key"
    error_message = "Start instances should target by 'tag-key'"
  }

  assert {
    condition     = contains(aws_ssm_association.start_rds_instances["MON"].targets[0].values, "Schedule")
    error_message = "Start instances should look for the 'Schedule' tag"
  }

  assert {
    condition     = aws_ssm_association.stop_rds_instances["MON"].targets[0].key == "tag-key"
    error_message = "Stop instances should target by 'tag-key'"
  }

  assert {
    condition     = contains(aws_ssm_association.stop_rds_instances["MON"].targets[0].values, "Schedule")
    error_message = "Stop instances should look for the 'Schedule' tag"
  }
}



# TEST 6: IAM role ARN is passed to all 4 associations .Every association needs the IAM role so SSM can assume it. If one

run "role_arn_passed_to_all_associations" {
  command = plan

  assert {
    condition     = aws_ssm_association.start_rds_instances["MON"].parameters["AutomationAssumeRole"] == "arn:aws:iam::123456789012:role/test-role"
    error_message = "Start RDS instances must have the role ARN"
  }

  assert {
    condition     = aws_ssm_association.stop_rds_instances["MON"].parameters["AutomationAssumeRole"] == "arn:aws:iam::123456789012:role/test-role"
    error_message = "Stop RDS instances must have the role ARN"
  }

  assert {
    condition     = aws_ssm_association.start_aurora_clusters["MON"].parameters["AutomationAssumeRole"] == "arn:aws:iam::123456789012:role/test-role"
    error_message = "Start Aurora clusters must have the role ARN"
  }

  assert {
    condition     = aws_ssm_association.stop_aurora_clusters["MON"].parameters["AutomationAssumeRole"] == "arn:aws:iam::123456789012:role/test-role"
    error_message = "Stop Aurora clusters must have the role ARN"
  }
}


# TEST 7: Empty tags map is valid

run "empty_tags_are_valid" {
  command = plan

  variables {
    tags = {}
  }

  assert {
    condition     = aws_ssm_document.aurora_cluster_scheduler.name == "cc-test-scheduler-aurora-cluster-scheduler"
    error_message = "Module should work fine with empty tags"
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
