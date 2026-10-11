variable "aws_region" {
  description = "Région AWS retenue par l'équipe"
  type        = string
  default     = "eu-west-3"

  validation {
    condition     = var.aws_region == "eu-west-3"
    error_message = "L'équipe déploie uniquement en eu-west-3 (Paris), la région du bucket de state."
  }
}

variable "environment" {
  description = "Nom de l'environnement"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment doit valoir dev ou prod."
  }
}

variable "owner" {
  description = "Équipe propriétaire, reportée dans les tags"
  type        = string
}
