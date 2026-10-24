# Séance 8 : aucune ressource, le premier plan doit afficher « No changes ».
# Le réseau (network.tf), la brique web (web.tf) et les secrets (secrets.tf)
# arrivent en séance 9.

locals {
  name_prefix = "novasphere-${var.environment}"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
