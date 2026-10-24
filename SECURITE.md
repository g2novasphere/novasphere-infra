# Sécurité — NovaSphere (EQUIPE 2)

> Rédaction : Aboubakar MDAHOMA (responsable CI/CD et sécurité).

## 1. Les secrets et où ils vivent

| Secret | Où il vit | Comment il y arrive | Où il ne doit jamais être |
|---|---|---|---|
| Secret applicatif (dev, prod) | SSM Parameter Store `/novasphere/<env>/app_secret`, SecureString chiffré par la clé gérée `aws/ssm` | GitHub secret `APP_SECRET_<ENV>` → variable `ephemeral` `app_secret` → attribut `value_wo` | code, `terraform.tfstate`, `bootstrap.sh`, historique Git, logs de CI, page web (seule une empreinte tronquée est affichée) |
| Accès AWS des membres | cache SSO local (`~/.aws/sso/cache`), credentials temporaires | `aws sso login`, utilisateur IAM Identity Center avec MFA | dépôt Git, messages, captures d'écran |
| Accès AWS de la CI | aucun stockage : jeton OIDC échangé à chaque run | `aws-actions/configure-aws-credentials` avec `role-to-assume` | aucune clé AWS dans les secrets GitHub |

**Pourquoi `value_wo`.** Un attribut en écriture seule est envoyé au provider mais jamais enregistré dans le plan ni dans le state. Pour changer la valeur, on incrémente `value_wo_version`.

**Comment l'instance lit le secret.** Au démarrage, `bootstrap.sh` appelle `aws ssm get-parameter --with-decryption` avec les credentials de son profil d'instance, obtenus par IMDSv2. La valeur n'est jamais écrite sur disque ni dans les logs.

### Vérifications faites (à refaire avant le rendu)

La valeur est lue depuis SSM dans une variable PowerShell, jamais affichée ; seuls des compteurs sortent :
```powershell
foreach ($e in "dev","prod") {
  $s = aws ssm get-parameter --name "/novasphere/$e/app_secret" --with-decryption --query Parameter.Value --output text
  $state = (terraform -chdir="envs/$e" state pull) -join "`n"
  $git   = (git log -p --all) -join "`n"
  $ci    = (gh run list -L 10 --json databaseId -q '.[].databaseId' | ForEach-Object { gh run view $_ --log 2>$null }) -join "`n"
  "{0} : state={1} git={2} logsCI={3}" -f $e, ([regex]::Matches($state,[regex]::Escape($s))).Count, ([regex]::Matches($git,[regex]::Escape($s))).Count, ([regex]::Matches($ci,[regex]::Escape($s))).Count
  Remove-Variable s
}
```

| Vérification | Résultat attendu | Résultat dev | Résultat prod | Fait le |
|---|---|---|---|---|
| Secret absent du state | `0` | __ | __ | __ |
| Secret absent de l'historique Git | `0` | __ | __ | __ |
| Secret absent des logs de CI (10 derniers runs) | `0` | __ | __ | __ |
| Aucun tfvars ni state commité (`git ls-files \| grep -E "tfstate\|\.tfvars$"`) | rien | __ | | __ |
| Aucune valeur par défaut sur `app_secret` (`secrets.tf`) | pas de `default` | conforme | conforme | 24/10/2026 |
| Valeur absente du plan (`value_wo = (write-only attribute)`) | write-only | conforme | conforme | 24/10/2026 |

## 2. Politique IAM de l'instance

Chaque environnement a son rôle `novasphere-<env>-instance` et son profil d'instance du même nom, créés par Terraform dans `secrets.tf`, avec uniquement ceci (politique en ligne, ARN réels résolus par Terraform) :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LireSonSecret",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:eu-west-3:<compte>:parameter/novasphere/<env>/app_secret"
    },
    {
      "Sid": "DechiffrerSonSecretViaSSM",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "ssm.eu-west-3.amazonaws.com",
          "kms:EncryptionContext:PARAMETER_ARN": "arn:aws:ssm:eu-west-3:<compte>:parameter/novasphere/<env>/app_secret"
        }
      }
    },
    {
      "Sid": "SessionManager",
      "Effect": "Allow",
      "Action": [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "*"
    }
  ]
}
```

Principe : moindre privilège. L'instance de dev ne peut pas lire le secret de prod, et inversement.

- **Déchiffrement** : `kms:Decrypt` n'est accordé que pour un appel passé par SSM **et** pour ce paramètre précis (SSM place l'ARN du paramètre dans le contexte de chiffrement). La clé n'est pas désignée par son ID : la clé gérée `aws/ssm` n'existe qu'après le premier SecureString du compte, ce qui ferait échouer un premier déploiement.
- **Pourquoi pas `AmazonSSMManagedInstanceCore`** : cette politique gérée autorise `ssm:GetParameter` sur `*`, donc la lecture du secret de l'autre environnement. Les actions de Session Manager sont listées à la main à la place.

## 3. Authentification de la CI par OIDC

Le fournisseur OIDC `token.actions.githubusercontent.com` et deux rôles (`novasphere-ci-dev`, `novasphere-ci-prod`) sont créés par `ci.tf`. Le job demande un jeton (`permissions: id-token: write`), AWS vérifie sa signature puis les conditions de la politique de confiance :

| Rôle | `aud` | `sub` autorisés | Utilisé par |
|---|---|---|---|
| `novasphere-ci-dev` | `sts.amazonaws.com` | `repo:g2novasphere@341004713/novasphere-infra@1414470281:pull_request`, `…:ref:refs/heads/main`, `…:environment:dev` | plans des PR (dev et prod), apply de dev, dérive de dev |
| `novasphere-ci-prod` | `sts.amazonaws.com` | `repo:g2novasphere@341004713/novasphere-infra@1414470281:environment:prod` **uniquement** | apply de prod et dérive de prod, après approbation |

Le dépôt utilise les sujets OIDC immuables : le `sub` contient les identifiants numériques de l'organisation et du dépôt, donc un dépôt supprimé puis recréé sous le même nom n'obtient pas les credentials. Le rôle prod n'accepte que l'environnement GitHub `prod`, qui exige une approbation et n'autorise que la branche `main` : sans approbation, aucun credential prod n'est délivré. Le plan de prod affiché en PR est calculé avec le rôle de dev, qui a déjà accès au compte (même compte AWS pour dev et prod) : cela n'ajoute aucun droit.

**Différence avec des credentials stockés (modèle du Learner Lab).** Des clés dans les secrets du dépôt sont des secrets à renouveler, valables pour quiconque les obtient, depuis n'importe où. Avec OIDC, rien n'est stocké : les credentials durent quelques minutes et ne sont délivrés qu'à un workflow de ce dépôt, sur la branche ou l'environnement autorisé.

**Droits des rôles CI : pourquoi `PowerUserAccess`.** Terraform crée des ressources dans de nombreux services (VPC, EC2, Elastic Load Balancing, Auto Scaling, SSM, et les rôles liés aux services de l'ALB et de l'ASG). La liste exacte des actions change avec la version du provider et du module : une politique écrite action par action casserait la CI à chaque nouvelle ressource, et tout le temps du projet partirait en `AccessDenied`. `PowerUserAccess` couvre ces services **sauf IAM**, qui est le vrai levier d'élévation de privilèges. Les droits IAM sont donc ajoutés à part, dans une politique en ligne restreinte :

- lecture IAM partout (`iam:Get*`, `iam:List*`), nécessaire au refresh du state ;
- écriture seulement sur `role/`, `instance-profile/` et `policy/` `novasphere-<env>-*` : la CI de dev ne gère que les ressources IAM de dev, et inversement.

Les rôles `novasphere-ci-*` ne correspondent pas à ce préfixe : la CI ne peut ni augmenter ses propres droits, ni modifier le rôle de l'autre environnement. Conséquence assumée : `ci.tf` se modifie en local, par le responsable CI/CD, avec `-target`.

**Limites connues.** `PowerUserAccess` reste large : dev et prod partagent un compte, donc le rôle de dev a techniquement accès aux ressources de prod. L'isolation forte demanderait deux comptes AWS, ou des politiques par service restreintes par tag `Environment`. Une PR non relue peut exécuter du code avec le rôle de dev pendant le plan ; l'idéal serait un rôle de plan en lecture seule.

## 4. Groupes de sécurité

Règles déclarées séparément (`aws_vpc_security_group_*_rule`) à partir du module v1.5.0 :

| Security Group | Entrant | Sortant | Justification |
|---|---|---|---|
| SG alb | 80/tcp depuis `0.0.0.0/0` | 80/tcp vers **SG web uniquement** | point d'entrée public |
| SG web | 80/tcp depuis **SG alb uniquement** | 80 et 443/tcp vers Internet (dnf, SSM, Parameter Store) | aucun accès direct ; **aucun port 22** ; pas de NAT ni de VPC endpoint (coût), d'où la sortie vers Internet |

## 5. Scan de sécurité

Outil : **checkov 3.3.30**. Commandes :
```powershell
python -m checkov.main -d envs --framework terraform --compact --skip-download   # dépôt novasphere-infra
python -m checkov.main -d .    --framework terraform --compact --skip-download   # dépôt du module
```
Date du dernier scan : **24/10/2026**.

| Périmètre | Avant corrections | Après corrections |
|---|---|---|
| Module (v1.4.0 → v1.5.0) | 21 passés, **11 échoués**, 0 ignoré | 39 passés, **0 échoué**, 9 ignorés (justifiés) |
| `envs/` (dev + prod) | 120 passés, **12 échoués**, 2 ignorés | 120 passés, **6 échoués**, 8 ignorés (justifiés) |

Une exception acceptée est marquée dans le code par `#checkov:skip=<ID>:<raison>` : checkov la compte en « ignoré » et la raison reste lisible à côté de la ressource.

### Module `terraform-aws-novasphere-web`

| Contrôle | Ressource | Traitement | Justification |
|---|---|---|---|
| CKV_AWS_382 sortie vers `0.0.0.0/0` sur tous les ports | SG alb, SG web | **corrigé** | SG alb : 80 vers le SG web uniquement ; SG web : 80 et 443 seulement |
| CKV_AWS_153 tags de l'ASG | ASG | **corrigé** | tags `Name` et `Environment` propagés aux instances |
| CKV_AWS_260 port 80 ouvert à `0.0.0.0/0` | règle d'entrée du SG alb | accepté | l'ALB est le point d'entrée public ; le SG web reste fermé |
| CKV_AWS_260 (faux positif) | règle d'entrée du SG web | accepté | la source est le SG de l'ALB (`referenced_security_group_id`), pas `0.0.0.0/0` |
| CKV_AWS_2, CKV2_AWS_20, CKV_AWS_103 HTTPS / TLS | listener 80, ALB | accepté | pas de nom de domaine pour valider un certificat ACM (extension HTTPS écartée au cadrage) |
| CKV_AWS_378 target group en HTTP | target group | accepté | trafic ALB → instances interne au VPC, sans certificat |
| CKV_AWS_91 logs d'accès | ALB | accepté | coût S3, environnement détruit après chaque session |
| CKV_AWS_150 protection contre la suppression | ALB | accepté | incompatible avec la destruction en fin de session |
| CKV2_AWS_28 WAF | ALB | accepté | hors périmètre et facturé |

Corrigé aussi, hors checkov : `name_prefix` sur les SG (un nom fixe empêche `create_before_destroy`), `instance_refresh` sur l'ASG (un nouveau `bootstrap.sh` remplace les instances), `http_put_response_hop_limit = 1`.

Note sur les versions : `v1.2.0` et `v1.3.0` ont été posés par erreur sur le même commit que `v1.1.0` ; les corrections checkov sont publiées en `v1.5.0`.

### Environnements `envs/dev` et `envs/prod`

| Contrôle | Ressource | Traitement | Justification |
|---|---|---|---|
| CKV_AWS_356 `Resource "*"` | `aws_iam_policy_document.instance` (`secrets.tf`) | accepté | `ssmmessages:*` et `ssm:UpdateInstanceInformation` n'acceptent pas de ressource précise ; `kms:Decrypt` est limité par `kms:ViaService` et `kms:EncryptionContext:PARAMETER_ARN` |
| CKV_AWS_111 écriture sans contrainte | `aws_iam_policy_document.instance` (`secrets.tf`) | accepté | mêmes actions Session Manager ; la lecture du secret est limitée à son ARN |
| CKV_AWS_356 `Resource "*"` | `aws_iam_policy_document.ci_iam` (`ci.tf`) | accepté | lecture seule (`iam:Get*`, `iam:List*`) nécessaire au refresh ; écriture limitée à `novasphere-<env>-*` |
| CKV_AWS_337 clé KMS gérée par le client | paramètre SSM | accepté | la clé gérée `aws/ssm` suffit, une clé client est facturée |
| CKV_TF_1 module épinglé par hash de commit | `module "vpc"`, `module "web"` | accepté (non marqué dans le code) | le cahier des charges impose des versions lisibles : `version = "6.7.3"` pour le registre, `?ref=vX.Y.Z` pour notre module ; un tag publié n'est jamais modifié |
| CKV_AWS_394 zones de disponibilité non épinglées | `data "aws_availability_zones"` (`network.tf`) | à traiter par le référent AWS | la liste peut s'allonger si AWS ajoute une zone ; le VPC n'en prend que deux (`slice`) |
