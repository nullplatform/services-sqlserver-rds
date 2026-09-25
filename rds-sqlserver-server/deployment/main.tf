resource "aws_security_group" "rds" {
  name        = "np-rds-${var.instance_name}"
  description = "Allow SQL Server access from within the VPC"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = [for c in data.aws_vpc.main.cidr_block_associations : c.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "master" {
  name                    = "nullplatform/rds-sqlserver/${var.instance_name}/master"
  recovery_window_in_days = 0
  kms_key_id              = var.secret_kms_key_id

  tags = {
    "managed-by"   = "nullplatform"
    "rds-instance" = var.instance_name
    "service-id"   = var.service_id
  }
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    username = local.master_username
    password = random_password.master.result
  })
}

resource "aws_kms_key" "rds" {
  description         = "Customer managed key for RDS instance storage encryption (${var.instance_name})"
  enable_key_rotation = true

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/nullplatform-rds-sqlserver-${var.instance_name}"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_db_subnet_group" "main" {
  name       = var.instance_name
  subnet_ids = var.subnet_ids

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

resource "aws_db_instance" "main" {
  identifier        = var.instance_name
  engine            = var.edition
  engine_version    = var.sqlserver_version
  license_model     = "license-included"
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  username = local.master_username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = var.multi_az
  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }

  depends_on = [aws_secretsmanager_secret_version.master]
}
