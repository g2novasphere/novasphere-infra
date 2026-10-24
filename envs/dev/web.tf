# Brique web : appel du module de l'équipe, versionné par tag.
# Toutes les valeurs viennent des autres fichiers de l'environnement :
# réseau (network.tf), AMI (main.tf), profil d'instance (secrets.tf).
module "web" {
  source = "git::https://github.com/g2novasphere/terraform-aws-novasphere-web.git?ref=v1.2.0"

  name_prefix = "novasphere"
  environment = var.environment

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  instance_type         = var.instance_type
  ami_id                = data.aws_ami.al2023.id
  instance_profile_name = aws_iam_instance_profile.instance.name

  # Le module transmet user_data tel quel au Launch Template, qui exige du base64.
  # templatefile remplace uniquement les ${...} ; les variables bash ($T, $IID...) restent intactes.
  user_data = base64encode(templatefile("${path.module}/bootstrap.sh", {
    environment = var.environment
    region      = var.aws_region
  }))

  min_size = var.min_size
  max_size = var.max_size

  # Les instances lisent le secret dès leur démarrage : la politique IAM
  # doit être attachée au rôle AVANT qu'elles ne démarrent.
  depends_on = [aws_iam_role_policy.instance]
}
