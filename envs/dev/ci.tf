# ci.tf — accès de GitHub Actions au compte AWS par OIDC (aucune clé stockée).
# Fichier IDENTIQUE dans envs/dev et envs/prod : seule var.environment change le comportement.
# Créé UNE fois en local avec -target (README, étape 2) : la CI ne peut pas créer
# le rôle qui lui permet de s'authentifier. Toute modification de ce fichier
# s'applique aussi en local, car le rôle CI n'a pas le droit de se modifier lui-même.

variable "github_repo" {
  description = "Dépôt GitHub autorisé à assumer les rôles CI (owner/repo), pas un secret"
  type        = string
  default     = "g2novasphere/novasphere-infra"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo doit être au format owner/repo."
  }
}

locals {
  github_oidc_host = "token.actions.githubusercontent.com"

  # Le fournisseur OIDC est unique dans le compte : dev le crée, prod le lit.
  create_github_oidc = var.environment == "dev"
  github_oidc_arn    = local.create_github_oidc ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # Claim "sub" du jeton GitHub accepté par chaque rôle :
  # - "pull_request"        : plans des PR (dev ET prod, voir terraform-pr.yml)
  # - "ref:refs/heads/main" : job sans environnement lancé sur main
  # - "environment:<env>"   : job qui déclare `environment: <env>`
  # Le rôle prod n'accepte QUE l'environnement GitHub protégé : sans approbation, pas de credentials prod.
  ci_subjects = {
    dev = [
      "repo:${var.github_repo}:pull_request",
      "repo:${var.github_repo}:ref:refs/heads/main",
      "repo:${var.github_repo}:environment:dev",
    ]
    prod = [
      "repo:${var.github_repo}:environment:prod",
    ]
  }
}

data "aws_caller_identity" "ci" {}

resource "aws_iam_openid_connect_provider" "github" {
  count          = local.create_github_oidc ? 1 : 0
  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.create_github_oidc ? 0 : 1
  url   = "https://${local.github_oidc_host}"
}

data "aws_iam_policy_document" "ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = local.ci_subjects[var.environment]
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = "novasphere-ci-${var.environment}"
  description          = "Role assume par GitHub Actions (OIDC) pour l'environnement ${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust.json
  max_session_duration = 3600
}

# Tous les services sauf IAM (inclut iam:CreateServiceLinkedRole, utile à l'ALB et à l'ASG).
resource "aws_iam_role_policy_attachment" "ci_poweruser" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# IAM : lecture partout, écriture seulement sur les ressources IAM de SON environnement
# (rôle et profil d'instance novasphere-<env>-*). Les rôles novasphere-ci-* n'en font pas
# partie : la CI ne peut ni s'élever ses propres droits, ni toucher au rôle de l'autre environnement.
data "aws_iam_policy_document" "ci_iam" {
  statement {
    sid       = "LireIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid     = "GererIamDeSonEnvironnement"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.ci.account_id}:role/novasphere-${var.environment}-*",
      "arn:aws:iam::${data.aws_caller_identity.ci.account_id}:instance-profile/novasphere-${var.environment}-*",
      "arn:aws:iam::${data.aws_caller_identity.ci.account_id}:policy/novasphere-${var.environment}-*",
    ]
  }
}

resource "aws_iam_role_policy" "ci_iam" {
  name   = "novasphere-ci-iam-${var.environment}"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_iam.json
}

output "ci_role_arn" {
  description = "ARN du rôle CI, à reporter dans la variable GitHub AWS_ROLE_ARN_<ENV>"
  value       = aws_iam_role.ci.arn
}
