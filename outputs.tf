output "ssm_document_name" {
  description = "Name of the custom SSM Automation Document for Aurora clusters."
  value       = aws_ssm_document.aurora_cluster_scheduler.name
}

output "instance_start_association_id" {
  description = "SSM Association ID for the RDS instance start schedule."
  value       = aws_ssm_association.start_rds_instances.association_id
}

output "instance_stop_association_id" {
  description = "SSM Association ID for the RDS instance stop schedule."
  value       = aws_ssm_association.stop_rds_instances.association_id
}

output "aurora_start_association_id" {
  description = "SSM Association ID for the Aurora cluster start schedule."
  value       = aws_ssm_association.start_aurora_clusters.association_id
}

output "aurora_stop_association_id" {
  description = "SSM Association ID for the Aurora cluster stop schedule."
  value       = aws_ssm_association.stop_aurora_clusters.association_id
}
