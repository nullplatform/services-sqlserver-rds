variable "service_id" {
  type        = string
  description = "Nullplatform service ID"
}

variable "instance_name" {
  type        = string
  description = "Unique instance name for AWS resource naming (format: np-<service_name>)"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the RDS instance will be deployed"
}

variable "edition" {
  type        = string
  default     = "sqlserver-ex"
  description = "SQL Server edition, mapped directly to the RDS engine identifier"

  validation {
    condition     = contains(["sqlserver-ex", "sqlserver-web", "sqlserver-se"], var.edition)
    error_message = "edition must be one of: sqlserver-ex, sqlserver-web, sqlserver-se"
  }
}

variable "instance_class" {
  type        = string
  default     = "db.t3.small"
  description = "RDS instance class"
}

variable "allocated_storage" {
  type        = number
  default     = 20
  description = "Allocated storage in GB"
}

variable "sqlserver_version" {
  type        = string
  default     = "16.00"
  description = "SQL Server major version"
}

variable "timezone" {
  type        = string
  default     = null
  description = "Server-level timezone. Cannot be changed after creation."
}

variable "collation" {
  type        = string
  default     = null
  description = "Server-level collation. Cannot be changed after creation."
}

variable "multi_az" {
  type        = bool
  default     = false
  description = "Enable Multi-AZ deployment for high availability. Not supported on sqlserver-ex."
}

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Number of days to retain automated backups. 0 disables backups."
}

variable "backup_window" {
  type        = string
  default     = "03:00-04:00"
  description = "Daily time range for automated backups (UTC, hh:mm-hh:mm)"
}

variable "maintenance_window" {
  type        = string
  default     = "Mon:04:00-Mon:05:00"
  description = "Weekly time range for maintenance operations (UTC, ddd:hh:mm-ddd:hh:mm)"
}

variable "secret_kms_key_id" {
  type        = string
  default     = null
  description = "KMS key ID or ARN used to encrypt the RDS master secret in Secrets Manager. If not set, AWS encrypts it with the default aws/secretsmanager managed key."
}
