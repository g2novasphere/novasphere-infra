# NovaSphere — infrastructure multi-environnements (EQUIPE 2, 5SRC4)

Infrastructure web NovaSphere sur AWS, en deux environnements (`dev` et `prod`), décrite avec Terraform et déployée par GitHub Actions. Ce document permet de tout déployer de zéro, sans connaître le projet.

> Rédaction : tous. Relecture finale : un membre qui n'a pas écrit la section la suit pas à pas sur un poste propre.

## 1. Prérequis

| Outil | Version | Vérification |
|---|---|---|
| Terraform | 1.14 ou supérieure | `terraform version` |
| AWS CLI | 2.x | `aws --version` |
| Plugin Session Manager | dernière | `session-manager-plugin --version` |
| Git | 2.x | `git --version` |
| Compte GitHub | accès au dépôt `novasphere-infra` et au dépôt du module | |
| Accès AWS | utilisateur personnel dans le compte de l'équipe (IAM Identity Center) | `aws sts get-caller-identity` |

Deux dépôts sont utilisés :
- `novasphere-infra` (ce dépôt) : les environnements, la CI et la documentation ;
- `terraform-aws-novasphere-web` : le module de l'équipe, appelé par tag (`?ref=vX.Y.Z`).

## 2. Credentials

Toute l'infrastructure et le state vivent dans **un seul compte AWS** : le compte personnel du référent AWS, financé par les crédits étudiants. Le compte root n'est jamais utilisé au quotidien.

**Sur le poste.** Chaque membre a **son propre utilisateur** (IAM Identity Center), avec MFA. Personne ne partage d'identifiants.
```bash
aws configure sso --use-device-code   # une seule fois : URL du portail, régions eu-west-3, profil "novasphere"
aws sso login --profile novasphere
export AWS_PROFILE=novasphere
aws sts get-caller-identity     # le numéro de compte doit être celui de l'équipe
```

**Dans GitHub : aucune clé AWS.** La CI s'authentifie par **OIDC** : GitHub lui fournit un jeton à chaque run, qu'elle échange contre des credentials AWS de courte durée en assumant un rôle IAM. Le dépôt ne contient que :

| Type | Nom | Contenu |
|---|---|---|
| Variable | `AWS_ROLE_ARN_DEV` | ARN du rôle CI de dev (pas un secret) |
| Variable | `AWS_ROLE_ARN_PROD` | ARN du rôle CI de prod (pas un secret) |
| Secret | `APP_SECRET_DEV` | secret applicatif de dev, jamais écrit ailleurs |
| Secret | `APP_SECRET_PROD` | secret applicatif de prod, jamais écrit ailleurs |

## 3. Déployer de zéro

**Étape 1 — préparer le compte** (une seule fois, par le référent AWS) :
- créer une alerte de budget (*Billing* → *Budgets*) à 50 % et 80 % du montant prévu, envoyée à toute l'équipe ;
- activer IAM Identity Center et créer un utilisateur par membre ;
- créer le bucket du state :
```bash
./scripts/create-state-bucket.sh
git add envs/*/backend.tf && git commit -m "chore: nom du bucket de state"
```

**Étape 2 — créer l'accès de la CI** (une seule fois, par le responsable CI/CD ; seul `apply` fait hors de la CI, car elle ne peut pas créer le rôle qui lui permet de s'authentifier). Dev d'abord : il crée le fournisseur OIDC, que prod ne fait que lire.
```bash
for env in dev prod; do
  cp -n envs/$env/terraform.tfvars.example envs/$env/terraform.tfvars
  terraform -chdir=envs/$env init
  terraform -chdir=envs/$env apply \
    -target=aws_iam_role_policy_attachment.ci_poweruser \
    -target=aws_iam_role_policy.ci_iam
done
```
Sous PowerShell : même commande dans une boucle `foreach ($env in "dev","prod") { ... }`, avec `` ` `` en fin de ligne.

Puis renseigner GitHub (CLI `gh`, droits admin sur le dépôt) :
```bash
REPO=g2novasphere/novasphere-infra
gh variable set AWS_ROLE_ARN_DEV  -R $REPO --body "$(terraform -chdir=envs/dev  output -raw ci_role_arn)"
gh variable set AWS_ROLE_ARN_PROD -R $REPO --body "$(terraform -chdir=envs/prod output -raw ci_role_arn)"
```
Créer l'environnement protégé : *Settings* → *Environments* → *New environment* `prod` → *Required reviewers* : au moins deux membres → *Deployment branches* : `main` uniquement. L'environnement `dev` est créé automatiquement au premier run.

Vérifier : *Actions* → *terraform-apply* → *Run workflow* → `apply`. Le job `apply-dev` doit passer l'étape *configure-aws-credentials*, et `apply-prod` doit attendre une approbation.

**Étape 3 — vérifier localement** (facultatif, sans rien créer) :
```bash
cd envs/dev
cp terraform.tfvars.example terraform.tfvars
export TF_VAR_app_secret='valeur-de-test'   # jamais dans un fichier
terraform init
terraform plan
```

**Étape 4 — déployer par la CI** (le seul chemin autorisé pour créer l'infrastructure) :
1. Créer une branche depuis `main` à jour, modifier, pousser, ouvrir une pull request (`gh pr create`) ; la description est pré-remplie par le modèle de PR.
2. La CI lance `fmt`, `validate` et `plan` pour dev et prod, et poste chaque plan en commentaire. Le relecteur (un autre membre) lit la ligne `Plan: X to add, Y to change, Z to destroy`, puis approuve.
3. Merger : `gh pr merge <numéro> --squash --delete-branch`. La CI enregistre le plan de dev dans un fichier, puis applique **ce fichier**.
4. Le job **prod** attend une approbation : *Actions* → le run → *Review deployments* → `prod` → *Approve and deploy*. Ne jamais laisser ce job en attente : il bloque tous les runs suivants (un seul déploiement à la fois).

Redéployer en début de session, sans PR, à partir du code de `main` :
```bash
gh workflow run terraform-apply.yml --ref main -f action=apply
gh run watch $(gh run list --workflow terraform-apply.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```
Puis approuver le job prod comme ci-dessus.

Temps de déploiement mesuré (création complète) : dev ≈ 3 min (2 min 58 s), prod ≈ 3 min (2 min 46 s) après approbation. Compter 1 à 3 min de plus pour que les instances passent leurs health checks.

## 4. Vérifier

L'adresse des ALB change à chaque recréation : on la récupère par leur nom.
```bash
for env in dev prod; do
  DNS=$(aws elbv2 describe-load-balancers --names novasphere-$env-alb --query 'LoadBalancers[0].DNSName' --output text)
  echo "== $env : http://$DNS/"
  for i in 1 2 3 4; do curl -s "http://$DNS/" | grep -o 'NovaSphere [a-z]*\|ID: [^|]*| Zone: [^ ]*'; done
done
```
Attendu pour chaque environnement : `NovaSphere dev` (ou `prod`) et deux identifiants d'instance dans deux zones (`eu-west-3a`, `eu-west-3b`) : l'ALB répartit les requêtes entre les deux instances de l'ASG. La page complète affiche aussi l'empreinte du secret. Un `502` ou `503` juste après un déploiement signifie que les instances passent encore leurs health checks.

État des instances dans le target group :
```bash
TG=$(aws elbv2 describe-target-groups --names novasphere-dev-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query 'TargetHealthDescriptions[].{instance:Target.Id,etat:TargetHealth.State}' --output table
```
`initial` : en démarrage ; `healthy` : prête.

Le secret est bien en SecureString, sans afficher sa valeur :
```bash
aws ssm describe-parameters --parameter-filters "Key=Name,Values=/novasphere/dev/app_secret" \
  --query 'Parameters[0].Type'           # → "SecureString"
(cd envs/dev && terraform state pull) | grep -ci "<valeur du secret>"   # → 0
```

Accès à une instance sans SSH (extension Session Manager) :
```bash
ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
aws ssm start-session --target "$ID"
```

Détection de dérive (lancement manuel, rien n'est modifié) :
```bash
gh workflow run terraform-apply.yml --ref main -f action=drift
```
Un job par environnement ; celui de prod demande une approbation (environnement protégé). Code 0 : aucune dérive ; code 2 : dérive détectée (le plan détaille l'écart).

## 5. Détruire (fin de chaque session de travail)

Rien ne doit tourner entre deux sessions : avec les deux environnements, on consomme de l'ordre de 0,15 $ par heure (ALB, instances, IPv4 publiques), soit plusieurs dollars de crédits par jour oubliés.

On détruit uniquement ce qui est facturé (la brique web et le réseau). Le fournisseur OIDC, les rôles IAM et le paramètre SSM restent en place : ils ne coûtent rien, et la CI garde son accès pour la session suivante.
```bash
export TF_VAR_app_secret='x'   # valeur exigée par Terraform, non utilisée pour détruire
cd envs/prod && terraform destroy -target=module.web -target=module.vpc
cd ../dev   && terraform destroy -target=module.web -target=module.vpc
unset TF_VAR_app_secret
```

**Jamais de `terraform destroy` sans `-target`** : il détruirait aussi `ci.tf` (rôle de la CI et fournisseur OIDC) et couperait toute la chaîne de déploiement ; la réparation est l'étape 2 ci-dessus. Avant de taper `yes`, relire le plan : il ne doit contenir ni `aws_iam_role.ci`, ni `aws_iam_openid_connect_provider`, ni `aws_ssm_parameter`.

À la session suivante, un merge (ou une relance du workflow d'apply) recrée tout par la CI. Le bucket du state n'est jamais détruit.

Vérifier qu'il ne reste rien de facturé :
```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'   # → []
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].AutoScalingGroupName'   # → []
```

## 6. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `ExpiredToken` ou `Token has expired` | session SSO expirée | `aws sso login --profile novasphere` |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | condition `sub` du rôle CI ou `permissions: id-token: write` manquante | vérifier le dépôt, la branche ou l'environnement dans la politique de confiance |
| `Error acquiring the state lock` | un autre plan ou apply en cours | attendre ; `terraform force-unlock <ID>` seulement si personne ne travaille |
| plan qui veut tout recréer | mauvais compte AWS | vérifier `aws sts get-caller-identity` |
| cibles `unhealthy` dans le target group | bootstrap en échec | se connecter par Session Manager, lire `/var/log/cloud-init-output.log` |
| À COMPLÉTER | erreurs réellement rencontrées par l'équipe | |

## 7. Documentation du projet

[ARCHITECTURE.md](ARCHITECTURE.md) · [SECURITE.md](SECURITE.md) · [CONTRIBUTING.md](CONTRIBUTING.md) · [CADRAGE.md](CADRAGE.md) · [RESTE_A_FAIRE.md](RESTE_A_FAIRE.md)
