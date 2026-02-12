
################################################################################
# Test Deployment — RDS Scheduled Stop/Start
#
# Usage:
#   1. cd examples/test/
#   2. terraform init
#   3. terraform plan
#   4. terraform apply
#   5. Tag a test RDS instance/cluster with Schedule=true
#   6. Verify via SSM console or trigger manually
#   7. terraform destroy (cleanup)
################################################################################

provider "aws" {
  region = "eu-west-2"
}

locals {
  common_tags = {
    Environment  = "test"
    ManagedBy    = "terraform"
    Purpose      = "rds-scheduler-testing"
    Owner        = "core-cloud"
    cost-centre  = "1709144"
    account-code = "521835"
    portfolio-id = "CTO"
    project-id   = "CC"
    service-id   = "rds-scheduled-stop-start"
  }
}

# ------------------------------------------------------------------------------
# IAM Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "ssm_rds_scheduler" {
  name = "cc-test-ssm-rds-scheduler"
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ssm_rds_scheduler" {
  name = "rds-scheduled-stop-start"
  role = aws_iam_role.ssm_rds_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStopStartTaggedResources"
        Effect = "Allow"
        Action = [
          "rds:StopDBCluster",
          "rds:StartDBCluster",
          "rds:StopDBInstance",
          "rds:StartDBInstance"
        ]
        Resource = [
          "arn:aws:rds:*:*:cluster:*",
          "arn:aws:rds:*:*:db:*"
        ]
        Condition = {
          StringLike = { "aws:ResourceTag/Schedule" = "*" }
        }
      },
      {
        Sid    = "AllowDescribeForDiscovery"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Module under test
# ------------------------------------------------------------------------------

module "rds_scheduled_stop_start" {
  source = "../../"

  name_prefix         = "cc-test-rds-scheduler"
  automation_role_arn = aws_iam_role.ssm_rds_scheduler.arn
  schedule_tag_key    = "Schedule"

  start_schedule        = "rate(30 minutes)"
  stop_schedule         = "rate(30 minutes)"
  aurora_start_schedule = "rate(30 minutes)"
  aurora_stop_schedule  = "rate(30 minutes)"

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "ssm_document_name" {
  value = module.rds_scheduled_stop_start.ssm_document_name
}

output "iam_role_arn" {
  value = aws_iam_role.ssm_rds_scheduler.arn
}
