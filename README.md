# RDS Scheduled Stop/Start

Terraform module that automatically stops and starts RDS instances and Aurora clusters on a schedule using AWS Systems Manager (SSM) State Manager. Resources opt-in by adding a `Schedule` tag.

## Usage
```hcl
module "rds_scheduled_stop_start" {
  source = "git::https://github.com/UKHomeOffice/core-cloud-rds-scheduled-terraform.git?ref=v1.0.0"

  name_prefix        = "cc-rds-scheduler"
  automation_role_arn = aws_iam_role.ssm_rds_scheduler.arn
  schedule_tag_key   = "Schedule"

  start_schedule        = "cron(0 8 ? * MON-FRI *)"
  stop_schedule         = "cron(0 18 ? * MON-FRI *)"
  aurora_start_schedule = "cron(0 9 ? * MON-FRI *)"
  aurora_stop_schedule  = "cron(0 17 ? * MON-FRI *)"

  tags = {
    cost-centre  = "1709144"
    account-code = "521835"
    portfolio-id = "CTO"
    project-id   = "CC"
    service-id   = "rds-scheduled-stop-start"
  }
}
```

**Note:** This module does NOT create the IAM role. The calling code must create it with the correct tag-based condition. See [IAM Role Requirements](#iam-role-requirements) below.

## Architecture
```
SSM State Manager
├── RDS Instances (AWS managed documents)
│   ├── AWS-StartRdsInstance  →  targets by tag-key "Schedule"
│   └── AWS-StopRdsInstance   →  targets by tag-key "Schedule"
│
└── Aurora Clusters (custom automation document)
    └── Python script:
        ├── Discovers clusters via DescribeDBClusters API
        ├── Filters by "Schedule" tag
        ├── Filters out unstoppable types (serverless, global, etc.)
        └── Calls StartDBCluster / StopDBCluster
```

### Why two approaches?

SSM State Manager can target RDS **instances** by tag natively. Aurora **clusters** cannot be targeted by tag, so a custom SSM Automation Document discovers them via API calls.

### Schedule staggering

| Time (UTC) | Action |
|---|---|
| 08:00 MON-FRI | Start RDS instances |
| 09:00 MON-FRI | Start Aurora clusters |
| 17:00 MON-FRI | Stop Aurora clusters |
| 18:00 MON-FRI | Stop RDS instances |

## Opting in a database

Add a `Schedule` tag to any RDS instance or Aurora cluster:
```
Tag Key:   Schedule
Tag Value: <any value, e.g. "true" or "weekdays">
```

To opt out, remove the tag.

## IAM Role Requirements

The calling code must create an IAM role with:

1. **Trust policy:** Allow `ssm.amazonaws.com` to assume the role
2. **Permissions:**
   - `rds:StopDBCluster`, `rds:StartDBCluster`, `rds:StopDBInstance`, `rds:StartDBInstance` — restricted by tag condition `aws:ResourceTag/Schedule = *`
   - `rds:DescribeDBClusters`, `rds:DescribeDBInstances`, `rds:ListTagsForResource` — on all resources (required for discovery)

Example:
```hcl
resource "aws_iam_role" "ssm_rds_scheduler" {
  name = "cc-ssm-rds-scheduled-stop-start-role"

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
  name = "cc-ssm-rds-scheduled-stop-start-policy"
  role = aws_iam_role.ssm_rds_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowStopStartTaggedResourcesOnly"
        Effect   = "Allow"
        Action   = [
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
        Sid      = "AllowDescribeForDiscovery"
        Effect   = "Allow"
        Action   = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
}
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name_prefix` | Prefix for all resource names | `string` | — | Yes |
| `automation_role_arn` | IAM role ARN for SSM to assume | `string` | — | Yes |
| `schedule_tag_key` | Tag key for opt-in filtering | `string` | `Schedule` | No |
| `start_schedule` | Cron for starting RDS instances | `string` | `cron(0 8 ? * MON-FRI *)` | No |
| `stop_schedule` | Cron for stopping RDS instances | `string` | `cron(0 18 ? * MON-FRI *)` | No |
| `aurora_start_schedule` | Cron for starting Aurora clusters | `string` | `cron(0 9 ? * MON-FRI *)` | No |
| `aurora_stop_schedule` | Cron for stopping Aurora clusters | `string` | `cron(0 17 ? * MON-FRI *)` | No |
| `tags` | Tags for module-created resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|---|---|
| `ssm_document_name` | Name of the custom SSM Automation Document |
| `instance_start_association_id` | SSM Association ID for instance start |
| `instance_stop_association_id` | SSM Association ID for instance stop |
| `aurora_start_association_id` | SSM Association ID for cluster start |
| `aurora_stop_association_id` | SSM Association ID for cluster stop |

## Cluster eligibility

The Python script skips clusters that cannot be stopped (matching PoC logic):

- Serverless v1 (`engine_mode = serverless`)
- Multi-master (`engine_mode = multimaster`)
- Parallel query (`engine_mode = parallelquery`)
- Global database (`engine_mode = global`)
- Multi-AZ DB Clusters (non-Aurora, detected by `DBClusterInstanceClass`)