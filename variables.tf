variable "name_prefix" {
  description = "Prefix for all resource names. Must be lowercase alphanumeric with hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric with hyphens."
  }
}

variable "automation_role_arn" {
  description = "ARN of the IAM role that SSM Automation will assume to perform actions."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z0-9-]*:iam::\\d{12}:role/.+$", var.automation_role_arn))
    error_message = "automation_role_arn must be a valid IAM role ARN."
  }
}

variable "schedule_tag_key" {
  description = "Tag key used to identify RDS resources that opt-in to scheduling."
  type        = string
  default     = "Schedule"

  validation {
    condition     = length(var.schedule_tag_key) > 0
    error_message = "schedule_tag_key must not be empty."
  }
}

# ------------------------------------------------------------------------------
# Schedules — RDS Instances
# Instances start/stop before clusters to allow dependency ordering.
# ------------------------------------------------------------------------------

variable "start_schedule" {
  description = "Cron expression (UTC) for starting RDS instances."
  type        = string
  default     = "cron(0 8 ? * MON-FRI *)"

  validation {
    condition     = can(regex("^(cron|rate)\\(.*\\)$", var.start_schedule))
    error_message = "start_schedule must be a valid cron() or rate() expression."
  }
}

variable "stop_schedule" {
  description = "Cron expression (UTC) for stopping RDS instances."
  type        = string
  default     = "cron(0 18 ? * MON-FRI *)"

  validation {
    condition     = can(regex("^(cron|rate)\\(.*\\)$", var.stop_schedule))
    error_message = "stop_schedule must be a valid cron() or rate() expression."
  }
}

# ------------------------------------------------------------------------------
# Schedules — Aurora Clusters
# Offset from instance schedules to allow time for instance state transitions.
# ------------------------------------------------------------------------------

variable "aurora_start_schedule" {
  description = "Cron expression (UTC) for starting Aurora clusters. Defaults to 1 hour after instance start."
  type        = string
  default     = "cron(0 9 ? * MON-FRI *)"

  validation {
    condition     = can(regex("^(cron|rate)\\(.*\\)$", var.aurora_start_schedule))
    error_message = "aurora_start_schedule must be a valid cron() or rate() expression."
  }
}

variable "aurora_stop_schedule" {
  description = "Cron expression (UTC) for stopping Aurora clusters. Defaults to 1 hour before instance stop."
  type        = string
  default     = "cron(0 17 ? * MON-FRI *)"

  validation {
    condition     = can(regex("^(cron|rate)\\(.*\\)$", var.aurora_stop_schedule))
    error_message = "aurora_stop_schedule must be a valid cron() or rate() expression."
  }
}

variable "tags" {
  description = "Tags to apply to resources created by this module."
  type        = map(string)
  default     = {}
}