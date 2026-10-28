# secrets.tf — secret applicatif et identité IAM des instances web.
# Fichier IDENTIQUE dans envs/dev et envs/prod : seule var.environment change.
#
# Chemin du secret : GitHub secret APP_SECRET_<ENV> -> TF_VAR_app_secret (CI)
# -> variable ephemeral -> attribut write-only value_wo -> SSM Parameter Store.
# La valeur n'apparaît JAMAIS dans le plan ni dans le state.

variable "app_secret" {
  description = "Secret applicatif, fourni par TF_VAR_app_secret (secret GitHub en CI). Jamais dans un fichier."
  type        = string
  ephemeral   = true # non enregistré dans le plan ni dans le state
  sensitive   = true # masqué dans les sorties de Terraform
  # Pas de valeur par défaut : volontaire, un oubli doit faire échouer le plan.

  validation {
    condition     = length(var.app_secret) >= 16
    error_message = "app_secret doit faire au moins 16 caractères (secret GitHub APP_SECRET_<ENV> manquant ou trop court ?)."
  }
}

variable "app_secret_version" {
  description = "À incrémenter pour pousser une nouvelle valeur du secret (value_wo n'est pas comparé par Terraform)"
  type        = number
  default     = 1
}

resource "aws_ssm_parameter" "app_secret" {
  name        = "/novasphere/${var.environment}/app_secret"
  description = "Secret applicatif NovaSphere (${var.environment})"
  type        = "SecureString" # chiffré par la clé gérée aws/ssm

  value_wo         = var.app_secret
  value_wo_version = var.app_secret_version

  #checkov:skip=CKV_AWS_337:la clé gérée aws/ssm suffit (pas de clé KMS client facturée)
}

# ---------------------------------------------------------------------------
# Rôle des instances : lire SON paramètre et accepter Session Manager, rien d'autre.
# Volontairement PAS AmazonSSMManagedInstanceCore : elle autorise ssm:GetParameter
# sur "*", donc la lecture du secret de l'autre environnement.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "instance_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "novasphere-${var.environment}-instance"
  description        = "Role des instances web NovaSphere (${var.environment})"
  assume_role_policy = data.aws_iam_policy_document.instance_trust.json
}

data "aws_iam_policy_document" "instance" {
  #checkov:skip=CKV_AWS_356:ssmmessages:* et ssm:UpdateInstanceInformation n'acceptent pas de ressource précise ; kms:Decrypt est limité par ViaService et PARAMETER_ARN
  #checkov:skip=CKV_AWS_111:mêmes actions Session Manager, sans ressource possible ; la lecture du secret est limitée à son ARN
  statement {
    sid       = "LireSonSecret"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.app_secret.arn]
  }

  # Déchiffrement limité aux appels faits via SSM, et pour CE paramètre uniquement
  # (SSM passe l'ARN du paramètre dans le contexte de chiffrement KMS).
  statement {
    sid       = "DechiffrerSonSecretViaSSM"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:PARAMETER_ARN"
      values   = [aws_ssm_parameter.app_secret.arn]
    }
  }

  # Agent SSM : enregistrement de l'instance et canaux de Session Manager.
  statement {
    sid = "SessionManager"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "novasphere-${var.environment}-instance"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "novasphere-${var.environment}-instance"
  role = aws_iam_role.instance.name
}

output "instance_profile_name" {
  description = "Profil d'instance à passer au module web (variable instance_profile_name)"
  value       = aws_iam_instance_profile.instance.name
}

output "app_secret_parameter_name" {
  description = "Nom du paramètre SSM lu par bootstrap.sh (la valeur n'est jamais exposée)"
  value       = aws_ssm_parameter.app_secret.name
}
