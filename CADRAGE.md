# Fiche de cadrage — EQUIPE 2 (séance 8)

Projet fil rouge NovaSphere — Master SRC Bac+5 — Classe : 5SRC4

## Équipe

| Membre | Rôle | Responsabilités principales | Compte AWS de démonstration |
|---|---|---|---|
| DEMAIE Maxime | Responsable module | Dépôt `terraform-aws-novasphere-web` : variables typées, validation, outputs, `bootstrap.sh`, versions v1.x.x | Utilisateur SSO dans le compte de l'équipe |
| LEFORT Johan | Référent Git | Protection de `main`, règles de revue des PR, tags du module et tag `rendu-final`, CONTRIBUTING.md | Utilisateur SSO dans le compte de l'équipe |
| MASAD Fahed | Référent AWS | Compte AWS de l'équipe, accès SSO des membres, alerte de budget, bucket de state, destruction après chaque session, extension Session Manager | **Compte AWS personnel (crédits étudiants) — compte de la démo** |
| MDAHOMA Aboubakar | Responsable CI/CD et sécurité | Workflows `terraform-pr.yml` et `terraform-apply.yml`, CI authentifiée par OIDC, environnement `prod` protégé, job de dérive, secret `value_wo`, scan checkov, SECURITE.md | Utilisateur SSO dans le compte de l'équipe |

Chaque membre commite depuis son poste, sous son propre nom, et ouvre ou relit au moins une pull request.

## Contexte

- **Application** : NovaSphere, le contexte du cours conservé.
- **Ce que servent les instances** : une page web sur `/`. Elle affiche l'environnement (`dev` ou `prod`), l'identifiant de l'instance et la zone de disponibilité, ce qui montre la répartition par l'ALB. Elle indique aussi que le secret a bien été chargé depuis Parameter Store, en n'affichant qu'une empreinte tronquée et jamais la valeur.
- **Environnements** : `dev` est déployé au merge sur `main`. `prod` est déployé après approbation dans l'environnement GitHub protégé.
- **Nommage** : les ressources s'appellent `novasphere-<env>-<ressource>`. Les clés de state sont `novasphere/dev/terraform.tfstate` et `novasphere/prod/terraform.tfstate`.
- **Compte et région** : compte AWS personnel de Fahed (crédits étudiants), région eu-west-3 (Paris). Un rôle IAM dédié par environnement pour les instances, CI authentifiée par OIDC.

## L'extension choisie (une seule)

[x] **Administration sans SSH : Session Manager**

[ ] HTTPS  [ ] Base de données (RDS)  [ ] Image préconstruite (Packer)  [ ] Ansible  [ ] Second service  [ ] Tests de module  [ ] Autre

**Ce qu'elle exige en plus du socle**

- **Ressources** : aucune ressource facturée en plus. L'agent SSM est préinstallé sur Amazon Linux 2023. Comme les instances sont en subnet public avec une IP publique, elles joignent les endpoints SSM sans NAT Gateway ni VPC endpoint. Le port 22 reste fermé et aucune paire de clés n'est créée.
- **Permissions** : le rôle IAM des instances, créé par Terraform, reçoit uniquement les actions nécessaires à Session Manager (décrites dans SECURITE.md).
- **Postes** : chaque membre installe le plugin Session Manager de l'AWS CLI.
- **Coût horaire supplémentaire** : 0 $. Le socle consomme les crédits étudiants (de l'ordre de 0,15 $/h avec dev et prod) : tout est détruit en fin de session et une alerte de budget est active.
- **Temps estimé** : environ 4 h, réparties entre la vérification des permissions, l'affichage des instances dans Fleet Manager, l'ouverture d'une session `aws ssm start-session` et la documentation dans le README.
- **Démonstration** : ouvrir une session sur une instance de prod. Montrer ensuite que le Security Group web n'expose aucun port 22, puis relire le paramètre depuis l'instance grâce à son profil IAM.
- **Plan de repli** : si Session Manager ne fonctionne pas, l'équipe passe aux tests de module (`terraform test` avec `mock_provider`, exécuté en CI). Ce changement serait documenté dans ARCHITECTURE.md et CADRAGE.md en séance 9.

## Ce que l'équipe écarte, et pourquoi

- **HTTPS** : la validation ACM exige un nom de domaine, qu'il faudrait acheter sur les crédits.
- **RDS** : il faut des subnets privés, le coût horaire est élevé et cela demande beaucoup de temps pour un bonus plafonné à 2 points.
- **NAT Gateway et VPC endpoints SSM** : ils sont facturés à l'heure et inutiles, puisque les instances ont une IP publique.
- **Bastion** : il réintroduit SSH et une instance de plus, ce qui va contre l'objectif « aucun port 22 ».
- **Workspaces Terraform** : ils sont interdits pour séparer dev et prod. Le projet utilise des répertoires `envs/dev` et `envs/prod` distincts.
- **Seconde extension** : elle ne serait pas notée, et le temps doit aller au socle.

## Validation

Validée par l'intervenant le ________ : [ ] telle quelle  [ ] réduite à : ______________________

Signature de l'équipe : ______________________  Signature de l'intervenant : ______________________
