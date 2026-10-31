## Ce qui change
<!-- Une ou deux phrases -->

## Pourquoi
<!-- Lien avec la TODO, le cahier des charges ou un incident -->

## Résumé du plan
<!-- Recopier la ligne du commentaire de la CI : Plan: X to add, Y to change, Z to destroy -->
- dev :
- prod :

## Vérification
<!-- Comment le relecteur peut vérifier -->

## Checklist
- [ ] `terraform fmt -recursive` lancé
- [ ] Aucun secret, `.tfvars`, `.tfstate` ni `.terraform/` dans la PR
- [ ] `envs/dev` et `envs/prod` restent identiques (hors clé du backend et tfvars)
- [ ] Le plan ne détruit rien d'inattendu
- [ ] Documentation mise à jour si besoin
