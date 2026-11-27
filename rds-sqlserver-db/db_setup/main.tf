resource "random_password" "user" {
  length  = 32
  special = false
  keepers = {
    service_id = var.service_id
  }
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "nullplatform/rds-sqlserver/${var.instance_name}/app"
  recovery_window_in_days = 0

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.user.result
    host     = var.db_host
    port     = var.db_port
    dbname   = var.db_name
  })
}

locals {
  migrator_target_user_name = "migrator_user_${var.db_name}"
}

ephemeral "random_password" "migrator" {
  length      = 32
  min_lower   = 1
  min_numeric = 1
  min_upper   = 1
  special     = false
}

resource "aws_secretsmanager_secret" "migrator" {
  name                    = "nullplatform/rds-sqlserver/${var.rds_instance_identifier}/${var.db_name}/migrator"
  recovery_window_in_days = 7

  lifecycle {
    precondition {
      condition     = var.rds_instance_identifier != ""
      error_message = "rds_instance_identifier is required to name the migrator secret and endpoint."
    }
  }

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

resource "aws_secretsmanager_secret_version" "migrator" {
  secret_id = aws_secretsmanager_secret.migrator.id
  secret_string_wo = jsonencode({
    username = local.migrator_target_user_name
    password = ephemeral.random_password.migrator.result
    host     = var.db_host
    port     = tostring(var.db_port)
    dbname   = var.db_name
  })
  secret_string_wo_version = 1
}
