# Checklist avant le tag `rendu-final` (avant le 31/10/2026, 23h59)

> À parcourir ensemble la veille du rendu. Ce qui est poussé après le tag ne compte pas.

## Documentation (composante F, 3 points)

- [ ] **README.md** suivi de zéro par un membre qui ne l'a pas écrit, sur un poste propre, sans aide
- [ ] README : prérequis, credentials, ordre des commandes, vérification, destruction, dépannage complétés
- [ ] **ARCHITECTURE.md** : schéma à jour, toutes les décisions et alternatives écartées, extension décrite
- [ ] **SECURITE.md** : tableau des secrets, politique IAM idéale, **vraie sortie du scan** et traitement de chaque ligne
- [ ] **CONTRIBUTING.md** : règles réellement appliquées
- [ ] **CADRAGE.md** : la fiche **validée** (date, case cochée, signatures) ; mise à jour si l'extension a changé
- [ ] **RESTE_A_FAIRE.md** : items nominatifs remplis, cochés, signés, photo jointe
- [ ] Plus aucune mention « À COMPLÉTER » : `grep -rn "À COMPLÉTER" *.md` ne renvoie rien

## Pièges qu'un jury cherche

- [ ] `git ls-files | grep -E "tfstate|\.tfvars$|\.terraform/|\.pem"` ne renvoie rien
- [ ] `terraform state pull | grep` du secret renvoie 0, en dev et en prod
- [ ] `git log -p --all | grep` du secret renvoie 0
- [ ] Aucune valeur par défaut sur `app_secret`
- [ ] Aucune clé AWS dans les secrets GitHub : la CI passe uniquement par OIDC
- [ ] Aucun bloc `provider` dans le module
- [ ] `envs/dev` et `envs/prod` identiques sauf la clé du backend : `diff -r envs/dev envs/prod`

## Terraform (composante B, 6 points)

- [ ] Module publié par tag, appelé avec `?ref=vX.Y.Z`, avec au moins une validation
- [ ] `terraform plan` affiche **No changes** en dev et en prod sur le dépôt gelé
- [ ] `.terraform.lock.hcl` commité

## CI/CD (composante D, 3 points)

- [ ] Plan posté en commentaire sur une PR récente
- [ ] Apply dev au merge, apply prod derrière approbation, job drift déclenchable
- [ ] Une **pull request de démonstration** préparée avec un changement visible sur la page

## Contribution individuelle

- [ ] Chaque membre a des commits significatifs à son nom
- [ ] Chaque membre a ouvert et relu au moins une PR

## Le jour du rendu

- [ ] Dépôts publics, ou intervenant ajouté comme collaborateur (les deux dépôts)
- [ ] `git tag rendu-final && git push origin rendu-final` posé **avant** l'heure
- [ ] Infrastructure détruite après la dernière session, aucune dépense en cours dans *Billing*

## Le jour de la soutenance

- [ ] `aws sso login` sur le poste de démo, crédits restants vérifiés
- [ ] Onglet avec le dernier run de CI réussi (plan B si la CI est lente)
- [ ] Chacun sait expliquer chaque composante, avec la page de documentation officielle qui justifie chaque choix
