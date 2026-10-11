# Règles d'équipe — EQUIPE 2

> Rédaction : Johan LEFORT (référent Git). Adaptées des règles de la séance 1.

## Rôles

| Membre | Rôle | Fichiers dont il est garant |
|---|---|---|
| Maxime DEMAIE | Responsable module | dépôt `terraform-aws-novasphere-web`, `bootstrap.sh`, `web.tf` |
| Johan LEFORT | Référent Git | protection de `main`, tags, `.gitignore`, CONTRIBUTING.md, RESTE_A_FAIRE.md |
| Fahed MASAD | Référent AWS | compte AWS, accès SSO, budget, bucket de state, `backend.tf`, `network.tf`, extension Session Manager, ARCHITECTURE.md |
| Aboubakar MDAHOMA | CI/CD et sécurité | `.github/workflows/`, `ci.tf` (OIDC), `secrets.tf`, SECURITE.md |

Être garant ne veut pas dire travailler seul : chacun doit savoir expliquer tout le dépôt.

## Identité Git

Chacun commite depuis son poste, sous son propre nom :
```bash
git config user.name "Prénom Nom"
git config user.email "adresse@..."
```
La contribution est lue dans l'historique du dépôt gelé.

## Branches et pull requests

- Aucun push direct sur `main` : elle est protégée.
- Une branche par sujet : `feat/…`, `fix/…`, `docs/…`, `ci/…`.
- Toute modification passe par une pull request, relue et approuvée par **un autre membre**.
- On ne merge pas une PR dont le plan n'a pas été relu, ou dont `fmt` ou `validate` échoue.
- Description de PR : ce qui change, le résumé du plan (`X to add, Y to change, Z to destroy`), comment vérifier.

## Messages de commit

`type: description courte au présent` — types : `feat`, `fix`, `docs`, `ci`, `refactor`, `chore`.
Exemple : `feat: ajout du target group et du health check`.

## Terraform

- `terraform fmt -recursive` avant chaque commit.
- Jamais d'`apply` à la main sur l'infrastructure : le déploiement passe par la CI.
- Jamais de `terraform.tfvars`, de `*.tfstate` ni de secret dans le dépôt.
- Le module est publié par tag `vX.Y.Z` ; un tag publié n'est **jamais** modifié, on en crée un nouveau.

## Sessions de travail

- Début : `aws sso login --profile novasphere` et `aws sts get-caller-identity`.
- Fin : `terraform destroy` sur prod puis dev ; vérifier qu'aucun ALB ni ASG ne reste.
- On ne touche pas au state à la main ; `force-unlock` seulement après accord de l'équipe.
- Chacun utilise **son propre** accès AWS : on ne partage jamais d'identifiants, on n'utilise jamais le compte root.
- Les crédits étudiants sont limités : on surveille l'alerte de budget et on détruit tout en fin de session.

## Questions et blocages

Une question au support : la commande lancée, le message d'erreur complet, ce qui a déjà été essayé.
