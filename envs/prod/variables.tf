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

variable "vpc_cidr" {
  description = "Plage d'adresses du VPC de l'environnement"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr doit être un bloc CIDR IPv4 valide."
  }
}
