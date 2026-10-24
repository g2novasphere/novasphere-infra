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

variable "instance_type" {
  description = "Type des instances web (petits types uniquement, pour préserver les crédits)"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "instance_type doit valoir t3.micro ou t3.small (budget de l'équipe)."
  }
}

variable "min_size" {
  description = "Nombre minimal d'instances (2 pour la haute disponibilité)"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Nombre maximal d'instances"
  type        = number
  default     = 3

  validation {
    condition     = var.max_size <= 4
    error_message = "max_size ne doit pas dépasser 4 (budget de l'équipe)."
  }
}
