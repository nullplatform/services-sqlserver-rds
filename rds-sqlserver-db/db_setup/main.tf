resource "random_password" "user" {
  length  = 32
  special = false
  keepers = {
    service_id = var.service_id
  }
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "nullplatform/rds-sqlserver/${var.service_id}/app"
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
