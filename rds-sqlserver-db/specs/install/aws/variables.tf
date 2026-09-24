variable "nrn" {
  description = "NullPlatform Resource Name (namespace-level, e.g. organization=<org>:account=<account>:namespace=<namespace>) where the service definition is registered."
  type        = string
}

variable "np_api_key" {
  description = "nullplatform API key used by the agent association to authenticate against the nullplatform API."
  type        = string
  sensitive   = true
}

variable "tags_selectors" {
  description = "Agent tag selectors for the notification channel (must match the tags the target agent registers with)."
  type        = map(string)
}

variable "service_name" {
  description = "Display name for the rds-sqlserver-db service in nullplatform."
  type        = string
  default     = "RDS SQL Server DB"
}

variable "repository_org" {
  description = "GitHub organization owning the services repository."
  type        = string
  default     = "nullplatform"
}

variable "repository_name" {
  description = "Repository name containing the rds-sqlserver-db service spec templates."
  type        = string
  default     = "services-sqlserver-rds"
}

variable "repository_branch" {
  description = "Branch of the services repository to register the service spec/links/entrypoint from."
  type        = string
  default     = "main"
}

variable "repository_token" {
  description = "Access token for private repositories. Unnecessary for a public repository."
  type        = string
  default     = null
  sensitive   = true
}
