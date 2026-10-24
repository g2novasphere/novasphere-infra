data "aws_availability_zones" "this" {
  state = "available"
}

locals {
  azs            = slice(data.aws_availability_zones.this.names, 0, 2)
  public_subnets = [for index in range(2) : cidrsubnet(var.vpc_cidr, 8, index)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = local.name_prefix
  cidr = var.vpc_cidr

  azs            = local.azs
  public_subnets = local.public_subnets

  create_igw              = true
  map_public_ip_on_launch = true

  enable_nat_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}
