# Sorties de l'environnement (instance_profile_name et app_secret_parameter_name
# sont déjà exposés dans secrets.tf, ci_role_arn dans ci.tf).
output "alb_dns_name" {
  description = "Adresse publique de l'application (la CI l'affiche après l'apply)"
  value       = module.web.alb_dns_name
}

output "target_group_arn" {
  description = "ARN du target group de l'ALB"
  value       = module.web.target_group_arn
}

output "vpc_id" {
  description = "ID du VPC de l'environnement"
  value       = module.vpc.vpc_id
}
