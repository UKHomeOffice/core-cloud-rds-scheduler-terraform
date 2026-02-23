output "ssm_document_name" {
  description = "Name of the custom SSM Automation Document for Aurora clusters."
  value       = aws_ssm_document.aurora_cluster_scheduler.name
}

output "instance_start_association_ids" {
  description = "SSM Association IDs for the RDS instance start schedules (one per weekday)."
  value       = { for day, assoc in aws_ssm_association.start_rds_instances : day => assoc.association_id }
}

output "instance_stop_association_ids" {
  description = "SSM Association IDs for the RDS instance stop schedules (one per weekday)."
  value       = { for day, assoc in aws_ssm_association.stop_rds_instances : day => assoc.association_id }
}

output "aurora_start_association_ids" {
  description = "SSM Association IDs for the Aurora cluster start schedules (one per weekday)."
  value       = { for day, assoc in aws_ssm_association.start_aurora_clusters : day => assoc.association_id }
}

output "aurora_stop_association_ids" {
  description = "SSM Association IDs for the Aurora cluster stop schedules (one per weekday)."
  value       = { for day, assoc in aws_ssm_association.stop_aurora_clusters : day => assoc.association_id }
}
