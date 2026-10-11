# Séance 8 : aucune ressource, le premier plan doit afficher « No changes ».
# Le réseau (network.tf), la brique web (web.tf) et les secrets (secrets.tf)
# arrivent en séance 9.

locals {
  name_prefix = "novasphere-${var.environment}"
}
