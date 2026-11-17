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

resource "random_password" "migrator" {
  length  = 32
  special = false
  keepers = {
    service_id = var.service_id
  }
}

resource "aws_secretsmanager_secret" "migrator" {
  name                    = "nullplatform/rds-sqlserver/${var.instance_name}/migrator"
  recovery_window_in_days = 0

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

resource "aws_secretsmanager_secret_version" "migrator" {
  secret_id = aws_secretsmanager_secret.migrator.id
  secret_string = jsonencode({
    username = var.migrator_username
    password = random_password.migrator.result
    host     = var.db_host
    port     = var.db_port
    dbname   = var.db_name
  })
}
