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

| Vérification | Commande | Résultat attendu | Fait le |
|---|---|---|---|
| Secret absent du state | `terraform state pull \| grep -c "<valeur>"` (dev et prod) | `0` | |
| Secret absent de l'historique Git | `git log -p --all \| grep -c "<valeur>"` | `0` | |
| Secret masqué dans les logs de CI | relire le dernier run apply | `***` ou absent | |
| Aucun tfvars ni state commité | `git ls-files \| grep -E "tfstate\|\.tfvars$"` | rien | |
| Aucune valeur par défaut sur `app_secret` | lecture de `variables.tf` | pas de `default` | |

## 2. Politique IAM de l'instance

Chaque environnement a son rôle `novasphere-<env>-instance`, créé par Terraform dans `secrets.tf`, avec uniquement ceci :

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
      "Sid": "DechiffrerViaSSM",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "arn:aws:kms:eu-west-3:<compte>:key/<id de la clé aws/ssm>",
      "Condition": { "StringEquals": { "kms:ViaService": "ssm.eu-west-3.amazonaws.com" } }
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

## 3. Authentification de la CI par OIDC

Le fournisseur OIDC `token.actions.githubusercontent.com` et deux rôles (`novasphere-ci-dev`, `novasphere-ci-prod`) sont créés par `ci.tf`. Le job demande un jeton (`permissions: id-token: write`), AWS vérifie sa signature puis les conditions de la politique de confiance :

| Rôle | `aud` | `sub` autorisés | Utilisé par |
|---|---|---|---|
| `novasphere-ci-dev` | `sts.amazonaws.com` | `repo:g2novasphere@341004713/novasphere-infra@1414470281:pull_request`, `…:ref:refs/heads/main`, `…:environment:dev` | plans des PR (dev et prod), apply de dev, dérive de dev |
| `novasphere-ci-prod` | `sts.amazonaws.com` | `repo:g2novasphere@341004713/novasphere-infra@1414470281:environment:prod` **uniquement** | apply de prod et dérive de prod, après approbation |

Le dépôt utilise les sujets OIDC immuables : le `sub` contient les identifiants numériques de l'organisation et du dépôt, donc un dépôt supprimé puis recréé sous le même nom n'obtient pas les credentials. Le rôle prod n'accepte que l'environnement GitHub `prod`, qui exige une approbation et n'autorise que la branche `main` : sans approbation, aucun credential prod n'est délivré. Le plan de prod affiché en PR est calculé avec le rôle de dev, qui a déjà accès au compte (même compte AWS pour dev et prod) : cela n'ajoute aucun droit.

**Différence avec des credentials stockés (modèle du Learner Lab).** Des clés dans les secrets du dépôt sont des secrets à renouveler, valables pour quiconque les obtient, depuis n'importe où. Avec OIDC, rien n'est stocké : les credentials durent quelques minutes et ne sont délivrés qu'à un workflow de ce dépôt, sur la branche ou l'environnement autorisé.

**Droits des rôles CI.** `PowerUserAccess` (tous les services sauf IAM) et une politique IAM en ligne : lecture IAM partout, écriture seulement sur `role/`, `instance-profile/` et `policy/` `novasphere-<env>-*`. Les rôles `novasphere-ci-*` ne correspondent pas à ce préfixe : la CI ne peut ni augmenter ses propres droits, ni modifier le rôle de l'autre environnement. Conséquence : `ci.tf` se modifie en local, par le responsable CI/CD.

**Limites connues.** Dev et prod partagent un compte : le rôle de dev a techniquement accès aux ressources de prod (l'isolation forte demanderait deux comptes AWS). Une PR non relue peut exécuter du code avec le rôle de dev pendant le plan ; l'idéal serait un rôle de plan en lecture seule.

## 4. Groupes de sécurité

| Security Group | Entrant | Sortant | Justification |
|---|---|---|---|
| SG alb | 80/tcp depuis `0.0.0.0/0` | vers SG web | point d'entrée public |
| SG web | 80/tcp depuis **SG alb uniquement** | tout (installation, SSM, Parameter Store) | aucun accès direct ; **aucun port 22** |

## 5. Scan de sécurité

Outil : checkov __ (version). Commande : `checkov -d envs/ --framework terraform` (et sur le dépôt du module).
Date du dernier scan : __. Résultat : __ passés, __ échoués.

À COMPLÉTER avec la **vraie sortie du scan**. Les lignes ci-dessous sont les résultats auxquels on s'attend, à confirmer ou supprimer :

| Contrôle | Ressource | Traitement | Justification |
|---|---|---|---|
| CKV_AWS_79 IMDSv1 désactivé | Launch Template | corrigé | `http_tokens = "required"` |
| CKV_AWS_131 en-têtes HTTP invalides | ALB | corrigé | `drop_invalid_header_fields = true` |
| CKV_AWS_2 listener non HTTPS | listener 80 | accepté | pas de nom de domaine pour valider un certificat ACM (extension HTTPS écartée) |
| CKV_AWS_260 port 80 ouvert à 0.0.0.0/0 | SG alb | accepté | l'ALB est le point d'entrée public ; le SG web reste fermé |
| CKV_AWS_130 IP publique sur les subnets | VPC | accepté | choix imposé : pas de NAT Gateway |
| CKV_AWS_91 logs d'accès de l'ALB | ALB | accepté | coût et durée de vie courte de l'environnement |
| CKV_AWS_150 protection contre la suppression | ALB | accepté | l'environnement est détruit après chaque session |
| CKV2_AWS_28 WAF | ALB | accepté | hors périmètre et coût |
| CKV_AWS_337 clé KMS gérée par le client | paramètre SSM | accepté | la clé gérée `aws/ssm` suffit ici |

Une exception acceptée est marquée dans le code par un commentaire `#checkov:skip=<ID>:<raison>`.
