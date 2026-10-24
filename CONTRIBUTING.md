# Règles d'équipe — EQUIPE 2 (5SRC4)

> Rédaction : Johan LEFORT (référent Git). Ces règles sont celles réellement appliquées pendant le projet ; plusieurs sont nées d'un incident, indiqué entre parenthèses.

## Rôles

| Membre | Rôle | Garant de |
|---|---|---|
| Maxime DEMAIE | Responsable module | dépôt `terraform-aws-novasphere-web`, ses versions, `bootstrap.sh` |
| Johan LEFORT | Référent Git | protection des dépôts, `web.tf`, `outputs.tf`, CONTRIBUTING.md, tag `rendu-final` |
| Fahed MASAD | Référent AWS | compte AWS, accès SSO, budget, bucket de state, `network.tf`, Session Manager, ARCHITECTURE.md |
| Aboubakar MDAHOMA | CI/CD et sécurité | workflows, `ci.tf` (OIDC), `secrets.tf`, checkov, SECURITE.md |

Être garant ne veut pas dire travailler seul : chacun doit savoir expliquer tout le dépôt.

## Poste de travail

- Tout le monde travaille sous Linux (WSL Ubuntu), dans le dossier Linux (`~/`), jamais dans `/mnt/c/`.
- Outils : Terraform ≥ 1.14, AWS CLI v2, Git, `gh` (CLI GitHub).
- Identité Git personnelle sur chaque poste (`git config --global user.name` / `user.email`) : la contribution est lue dans l'historique.
- Accès AWS : chacun son utilisateur IAM Identity Center avec MFA (`aws sso login --profile novasphere --use-device-code`). Aucun identifiant n'est partagé, le compte root n'est jamais utilisé.

## Protection des dépôts

Les deux dépôts sont publics : sur un compte GitHub gratuit, les rulesets ne s'appliquent qu'aux dépôts publics. Aucun secret n'y figure, et l'historique a été vérifié avant chaque passage en public.

| Dépôt | Ruleset | Effet |
|---|---|---|
| novasphere-infra | `protection-main` | PR obligatoire, 1 approbation, approbation annulée si nouveau commit, conversations résolues, pas de force push ni de suppression |
| terraform-aws-novasphere-web | `protection-main` | idem |
| terraform-aws-novasphere-web | `protection-tags` | un tag publié ne peut être ni déplacé ni supprimé |

La liste de contournement (*bypass list*) est vide : personne, administrateurs compris, ne pousse directement sur `main`.

## Branches et pull requests

- Une branche par sujet : `feat/…`, `fix/…`, `docs/…`, `ci/…`, `chore/…`.
- On ne travaille jamais sur la branche d'un autre sans le prévenir (incident : deux versions concurrentes de `web.tf` sur `fix/web-v1.2.0`).
- Toute PR a une description : ce qui change, pourquoi, le résumé du plan (`Plan: X to add, Y to change, Z to destroy`).
- La relecture est faite par un membre qui n'a pas écrit le code. Le relecteur :
  - lit le diff avec trois points : `git diff main...<branche>` (ce que la branche apporte) ;
  - attend que la CI soit verte et lit le plan posté en commentaire (aucune destruction inattendue, aucune valeur sensible) ;
  - approuve avec un commentaire qui dit ce qu'il a vérifié.
- Si l'approbation passe en `DISMISSED`, c'est que le contenu a changé : on relit, puis on réapprouve.
- On n'utilise jamais `--admin` pour contourner la protection.

## Stratégie de merge

- Par défaut : `gh pr merge <n> --squash --delete-branch`.
- Exception : si une autre PR est construite sur cette branche, merge classique `--merge` (avec un squash, GitHub continuerait d'afficher les commits dans la PR suivante).
- Après un merge : `git switch main && git pull`.

## Versions du module

- Seul le responsable du module crée les tags de `terraform-aws-novasphere-web` (incident : `v1.2.0` et `v1.3.0` créées depuis un `main` local non à jour).
- Un tag se crée uniquement après le merge de la PR, depuis `main` à jour :
  ```bash
  git switch main && git pull
  git log -1 --oneline          # vérifier que c'est le commit de merge attendu
  git tag -a vX.Y.Z -m "description" && git push origin vX.Y.Z
  ```
- Vérification après publication : `git ls-remote --tags <dépôt>` ; la ligne `vX.Y.Z^{}` (ou `vX.Y.Z` pour un tag simple) doit pointer sur le commit attendu.
- Un tag publié ne se modifie jamais : une erreur se corrige par une nouvelle version.
- `v1.2.0` et `v1.3.0` pointent sur le code de `v1.1.0` : ne pas les utiliser.
- Le module déclare une version minimale du provider (`>= 6.0`) ; c'est le projet qui fixe la borne haute (`~> 6.0`) (incident : `v1.0.0` exigeait `~> 5.0`, incompatible avec le projet).

## Terraform

- `terraform fmt -recursive` avant chaque commit.
- En local : `init`, `validate`, `plan` uniquement. Tout `apply` passe par la CI.
- Seule exception : le destroy de fin de session (voir plus bas).
- `terraform init` sans `-upgrade` : on ne change pas la version du provider sans PR dédiée.
- Jamais de `terraform.tfvars`, de `*.tfstate`, de `.terraform/` ni de secret dans le dépôt.
- `envs/dev` et `envs/prod` restent identiques : seules la clé du backend et les valeurs des tfvars diffèrent (`diff -r envs/dev envs/prod --exclude=.terraform --exclude=terraform.tfvars`).

## Chaîne CI/CD

- Chaque merge sur `main` lance l'apply : dev automatiquement, prod après approbation dans l'environnement `prod`.
- Un job prod en attente bloque tous les runs suivants (concurrence du workflow) : on l'approuve ou on le refuse aussitôt.
- On n'annule pas un run pendant un `apply` : risque de ressources à moitié créées et de verrou de state laissé en place. En cas de doute : `aws s3 ls s3://novasphere-tfstate-193131272485/novasphere/<env>/` ne doit montrer aucun `.tflock`.
- En cas d'échec : `gh run view <id> --log-failed`, puis on corrige par une PR.

## Sessions de travail

- Début : `aws sso login`, `git switch main && git pull`.
- Fin : destroy de ce qui est facturé, prod puis dev :
  ```bash
  terraform destroy -target=module.web -target=module.vpc
  ```
  Le bucket de state, les rôles IAM, le fournisseur OIDC et les paramètres SSM sont conservés (gratuits).
- **Jamais de `terraform destroy` sans `-target`** : il supprime aussi `ci.tf`, donc le rôle de la CI et le fournisseur OIDC, et coupe toute la chaîne (incident du 24/10, réparé par le bootstrap `-target` du README).
- Les crédits sont limités : on surveille l'alerte de budget.

## Traçabilité

Chaque action sur le compte AWS est tracée par CloudTrail avec l'identité SSO de son auteur, ou le nom du run pour la CI (`gh-apply-<env>-<id>`). Pour retrouver qui a fait quoi :
```bash
aws cloudtrail lookup-events --region eu-west-3 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=<Action> \
  --query 'Events[].{date:EventTime,qui:Username}' --output table
```

## Messages de commit

`type: description courte` — types : `feat`, `fix`, `docs`, `ci`, `chore`, `refactor`.
Exemple : `fix(web): module v1.4.0 et name_prefix = local.name_prefix`.

## Questions et blocages

Une question à l'équipe ou au support contient : la commande lancée, le message d'erreur complet, ce qui a déjà été essayé.
