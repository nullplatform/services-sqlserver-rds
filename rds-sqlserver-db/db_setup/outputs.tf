output "hostname" {
  value       = var.db_host
  description = "RDS endpoint hostname"
}

output "port" {
  value       = var.db_port
  description = "RDS port"
}

output "master_secret_arn" {
  value       = var.master_secret_arn
  description = "ARN of the Secrets Manager secret for master credentials"
}

output "db_username" {
  value       = var.db_username
  description = "Database username"
}

output "db_password" {
  value       = random_password.user.result
  sensitive   = true
  description = "Database user password"
}

output "database_name" {
  value       = var.db_name
  description = "Database name"
}

output "app_secret_arn" {
  value       = aws_secretsmanager_secret.app.arn
  description = "ARN of the Secrets Manager secret holding the app-level credentials"
}

output "migrator_username" {
  value       = local.migrator_target_user_name
  description = "Login and database user name that runs migrations"
}

output "migrator_secret_arn" {
  value       = aws_secretsmanager_secret.migrator.arn
  description = "ARN of the Secrets Manager secret holding the migrations user credentials"
}
