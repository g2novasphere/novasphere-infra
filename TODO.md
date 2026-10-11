# TODO — NovaSphere, EQUIPE 2 (5SRC4)

> Ce qu'on doit faire, du lancement jusqu'à la soutenance. Rendu : **samedi 31/10/2026, 23h59** (tag `rendu-final`).
> Les dates sont des objectifs : ajustez-les aux dates réelles des séances 8 et 9.
> Cochez au fur et à mesure et commitez ce fichier : il montre l'avancement à toute l'équipe.

**Rappel des rôles** : Maxime = module · Johan = Git · Fahed = AWS · Aboubakar = CI/CD et sécurité.
Compte : **AWS personnel de Fahed (crédits étudiants)**, un accès SSO par membre, CI par OIDC.
Chacun doit **commiter sous son nom**, **ouvrir et relire des PR**, et **savoir expliquer tout le projet**.

---

## Étape 1 — Séance 8 : lancement (objectif : 13/10)

**Fahed (AWS)**
- [ ] Vérifier le montant et la date d'expiration des crédits (*Billing* → *Credits*)
- [ ] Créer une alerte de budget (50 % et 80 %) envoyée aux quatre membres
- [ ] Activer MFA sur le compte root, puis ne plus l'utiliser
- [ ] Activer IAM Identity Center et créer un utilisateur par membre (avec MFA)
- [ ] Lancer `scripts/create-state-bucket.sh` (bucket versionné, chiffré, accès public bloqué)

**Johan (Git)**
- [x] Créer le dépôt `novasphere-infra` et pousser le premier commit **avec le backend déjà configuré**
- [x] Protéger `main` : PR obligatoire, 1 approbation minimum, pas de push direct
- [ ] Ajouter l'intervenant comme collaborateur
- [x] Commiter `.terraform.lock.hcl` (généré pour toutes les plateformes)

**Maxime (module)**
- [ ] Créer le dépôt `terraform-aws-novasphere-web` avec la structure vide : `.gitignore`, `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`

**Aboubakar (CI/CD et sécurité)**
- [ ] Écrire `envs/*/ci.tf` : fournisseur OIDC GitHub (créé par dev, lu par prod) et rôles `novasphere-ci-dev` / `novasphere-ci-prod`
- [ ] Les créer une seule fois en local avec `-target` (voir README, étape 2), puis renseigner les variables GitHub `AWS_ROLE_ARN_DEV` et `AWS_ROLE_ARN_PROD`
- [ ] Créer l'environnement GitHub `prod` avec approbation obligatoire

**Tous**
- [ ] `git config user.name` / `user.email` sur son poste
- [ ] `aws configure sso` puis `aws sso login`, vérifier avec `aws sts get-caller-identity`
- [ ] `terraform init` + `terraform plan` → **No changes** en dev et en prod, capture d'écran
- [ ] Faire valider la fiche de cadrage par l'intervenant, puis mettre à jour `CADRAGE.md` (date, signatures)

---

## Étape 2 — Séance 9 : construire le socle (objectif : 18/10)

**Maxime (module) — `terraform-aws-novasphere-web`**
- [ ] `versions.tf` : `required_providers` uniquement, **aucun bloc provider**
- [ ] `variables.tf` typées : `name_prefix`, `environment`, `vpc_id`, `subnet_ids`, `instance_type`, `ami_id`, `instance_profile_name`, `user_data`, `min_size`, `max_size`
- [ ] Au moins une validation (ex. `environment` dans dev/prod, `min_size >= 2`)
- [ ] `main.tf`, ressources nommées `this` :
  - [ ] SG alb (80 depuis Internet) et SG web (80 **depuis le SG alb uniquement**, pas de 22), `create_before_destroy`
  - [ ] Launch Template : IMDSv2 exigé (`http_tokens = "required"`), profil d'instance, user_data
  - [ ] ALB (`drop_invalid_header_fields = true`), target group (health check sur `/`), listener 80
  - [ ] ASG : min 2, sur les deux subnets, `health_check_type = "ELB"`
- [ ] `outputs.tf` : `alb_dns_name`, `target_group_arn`, `asg_name`
- [ ] Publier le tag `v1.0.0`
- [ ] `envs/*/bootstrap.sh` (10 lignes max) : lit le paramètre SSM, installe le serveur web, affiche environnement, ID d'instance, zone et empreinte du secret

**Fahed (AWS)**
- [ ] `envs/*/network.tf` : `module "vpc"` du registre, version épinglée, 2 zones, subnets publics, `enable_nat_gateway = false`, IP publique au lancement
- [ ] `envs/*/main.tf` : `data "aws_ami"` Amazon Linux 2023
- [ ] Premier déploiement de dev en test, puis destruction

**Johan (Git)**
- [ ] `envs/*/web.tf` : appel `module "web"` avec `?ref=v1.0.0`, profil d'instance créé dans `secrets.tf`
- [ ] `envs/*/outputs.tf` : `alb_dns_name`, `target_group_arn`, `vpc_id`
- [ ] Modèle de description de PR (`.github/pull_request_template.md`)
- [ ] Relire les PR des autres

**Aboubakar (CI/CD et sécurité)**
- [ ] `envs/*/secrets.tf` : `aws_ssm_parameter` SecureString avec `value_wo` et `value_wo_version`
- [ ] Variable `app_secret` : `ephemeral = true`, `sensitive = true`, **sans valeur par défaut**
- [ ] Rôle IAM `novasphere-<env>-instance` + profil d'instance : lecture de **son** paramètre uniquement, actions Session Manager
- [ ] Secrets GitHub `APP_SECRET_DEV` et `APP_SECRET_PROD`
- [ ] `.github/workflows/terraform-pr.yml` : `permissions: id-token: write`, connexion par `role-to-assume`, `fmt -check`, `validate`, `plan` en dev et prod, plan posté en commentaire

**Tous, en fin de séance**
- [ ] Remplir `RESTE_A_FAIRE.md` : 2 items nominatifs par personne, signé, photo jointe

---

## Étape 3 — Autonomie : tout faire tourner par la CI (objectif : 25/10)

**Aboubakar (CI/CD et sécurité)**
- [ ] `.github/workflows/terraform-apply.yml` :
  - [ ] au merge sur `main` : plan dev → fichier de plan → `apply` de ce fichier
  - [ ] job prod avec `environment: prod` (approbation obligatoire)
  - [ ] job `drift` déclenchable (`workflow_dispatch`, `plan -detailed-exitcode`)
  - [ ] apply relançable à la main (`workflow_dispatch`) pour redéployer en début de session
- [ ] Lancer checkov sur `envs/` et sur le module ; corriger ou justifier chaque résultat
- [ ] Vérifier que le secret est absent du state, de l'historique Git et des logs de CI
- [ ] Compléter `SECURITE.md` avec la **vraie sortie du scan**

**Maxime (module)**
- [ ] Corrections du scan dans le module → publier `v1.1.0` (ne jamais modifier `v1.0.0`)
- [ ] Mettre à jour le `?ref=` dans dev et prod par une PR

**Fahed (AWS)**
- [ ] Dev **et** prod répondent via l'ALB avec le contenu de leur environnement
- [ ] Extension : ouvrir une session `aws ssm start-session` sur une instance de prod
- [ ] Vérifier chaque semaine la consommation des crédits (*Billing* → *Bills*)
- [ ] Compléter `ARCHITECTURE.md` (schéma, décisions, extension)

**Johan (Git)**
- [ ] Compléter `CONTRIBUTING.md` avec les règles réellement appliquées
- [ ] Vérifier qu'aucun fichier interdit n'est suivi : `git ls-files | grep -E "tfstate|\.tfvars$|\.terraform/|\.pem"`
- [ ] Vérifier que `envs/dev` et `envs/prod` ne diffèrent que par la clé du backend : `diff -r envs/dev envs/prod`

**Tous**
- [ ] Compléter sa partie du `README.md`
- [ ] Tenir ses items de `RESTE_A_FAIRE.md` et les cocher
- [ ] Détruire l'infrastructure à la fin de **chaque** session de travail (les crédits sont limités)

---

## Étape 4 — Finalisation et gel (du 26/10 au 31/10)

**Johan (Git)**
- [ ] Faire suivre le `README.md` de zéro par un membre qui ne l'a pas écrit, corriger chaque blocage
- [ ] Préparer la **PR de démonstration** (changement visible sur la page, non mergée)
- [ ] Vérifier que les deux dépôts sont accessibles à l'intervenant
- [ ] Poser le tag `rendu-final` **avant le 31/10, 23h59** (`git tag rendu-final && git push origin rendu-final`)

**Tous**
- [ ] Plus aucun « À COMPLÉTER » : `grep -rn "À COMPLÉTER" *.md`
- [ ] `terraform plan` → **No changes** en dev et en prod sur la version gelée
- [ ] Dérouler `CHECKLIST_RENDU.md` ensemble
- [ ] Détruire l'infrastructure après la dernière session

---

## Étape 5 — Préparer la soutenance (après le gel)

**Démonstration (7 min) — chacun la répète en entier**, car le jury choisit qui pilote :
1. [ ] Ouvrir la PR préparée, lire le plan à voix haute
2. [ ] Merger, montrer le déploiement de dev par la CI
3. [ ] Approuver prod
4. [ ] Afficher la page de dev et de prod via l'ALB
5. [ ] Montrer le secret lu depuis Parameter Store (sans afficher sa valeur)
6. [ ] Ouvrir une session Session Manager (extension)

**Questions individuelles — chacun prépare les 6 composantes** (tirage au sort) :
- [ ] A. Fonctionnel · B. Terraform · C. Configuration · D. CI/CD · E. Sécurité · F. Livrables
- [ ] Pour chaque choix important, la **page de documentation officielle** qui le justifie
- [ ] S'entraîner aux pièges du jury : chercher le secret avec `terraform state pull` ; ouvrir un port à la main puis lancer `plan` ; renommer le module puis lancer `plan`

**Le jour J**
- [ ] `aws sso login` sur le poste de démo, crédits restants vérifiés, infrastructure déployée par la CI avant le passage
- [ ] Un onglet avec le dernier run de CI réussi (plan B si la CI est lente)
