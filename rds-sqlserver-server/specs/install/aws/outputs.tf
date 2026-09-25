output "service_specification_id" {
  description = "ID of the registered rds-sqlserver-server service specification."
  value       = module.service_definition.service_specification_id
}

output "service_specification_slug" {
  description = "Slug of the registered rds-sqlserver-server service specification."
  value       = module.service_definition.service_specification_slug
}

output "agent_association_id" {
  description = "ID of the notification channel that associates the rds-sqlserver-server service specification with the agent."
  value       = module.service_definition_agent_association.id
}
