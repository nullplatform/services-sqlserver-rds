variable "service_id" {
  type        = string
  description = "Nullplatform service ID"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "db_host" {
  type        = string
  description = "RDS endpoint hostname of the rds-sqlserver server this database lives on"
}

variable "db_port" {
  type        = number
  default     = 1433
  description = "RDS port"
}

variable "db_name" {
  type        = string
  description = "Database name created inside the RDS instance"
}

variable "db_username" {
  type        = string
  description = "Login and database user name for the application"
}

variable "master_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret holding the server master credentials"
}
