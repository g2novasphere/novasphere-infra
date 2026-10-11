# Le nom du bucket est inscrit par scripts/create-state-bucket.sh.
# Seule la clé diffère entre dev et prod.
terraform {
  backend "s3" {
    bucket       = "novasphere-tfstate-193131272485"
    key          = "novasphere/dev/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}
