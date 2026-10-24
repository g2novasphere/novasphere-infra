# Architecture — NovaSphere (EQUIPE 2)

> Rédaction : Fahed MASAD (référent AWS). Une page au maximum.

## Schéma

```
                         Internet
                            │ HTTP :80
                ┌───────────▼────────────┐
                │  ALB  (SG alb : 80 ← 0.0.0.0/0)
                │  listener 80 → target group (health check sur /)
                └─────┬──────────────┬───┘
         eu-west-3a   │              │   eu-west-3b
      ┌───────────────▼──┐      ┌────▼──────────────┐
      │ subnet public A  │      │ subnet public B   │
      │ 10.0.0.0/24      │      │ 10.0.1.0/24       │
      │ EC2 (ASG)        │      │ EC2 (ASG)         │
      │ SG web : 80 ← SG alb uniquement, aucun port 22
      └────────┬─────────┘      └────────┬──────────┘
               │ IMDSv2, rôle IAM novasphere-<env>-instance (moindre privilège)
               ├──► SSM Parameter Store  /novasphere/<env>/app_secret (SecureString)
               └──► Session Manager (administration sans SSH)

  VPC : module public terraform-aws-modules/vpc/aws 6.7.3, 2 AZ, pas de NAT Gateway
  ASG : minimum 2 instances, Launch Template, health_check_type = "ELB"
  State : S3 novasphere-tfstate-193131272485, versionné, chiffré, use_lockfile
          clés novasphere/dev/terraform.tfstate et novasphere/prod/terraform.tfstate
  CI : GitHub Actions authentifiée par OIDC (aucune clé AWS stockée)
       PR : fmt, validate, plan ; merge : apply dev ; prod après approbation
  Comptes : compte de gestion (facturation, Organizations, Identity Center)
            compte projet novasphere 193131272485 (toutes les ressources)
            un utilisateur SSO par membre, MFA obligatoire
```

## Décisions et alternatives écartées

| Décision | Alternative écartée | Raison |
|---|---|---|
| Deux répertoires `envs/dev` et `envs/prod` | workspaces Terraform | interdits par le cahier des charges ; des répertoires rendent le backend et l'environnement visibles |
| Code commun dans le module `terraform-aws-novasphere-web` appelé par tag | copier le code dans chaque environnement | dev et prod ne doivent différer que par les variables ; un tag fige une version testée |
| Région eu-west-3 (Paris) | us-east-1 | proche des utilisateurs et de l'équipe ; la contrainte us-east-1 ne valait que pour le Learner Lab |
| VPC du registre public | VPC écrit à la main | imposé, et maintenu par la communauté |
| Module VPC épinglé en version exacte `6.7.3` | contrainte souple `~> 6.0` | une version exacte garantit le même plan pour toute l'équipe et sur le dépôt gelé |
| Subnets publics sans NAT Gateway | subnets privés + NAT | une NAT Gateway est facturée à l'heure ; le SG web n'accepte que l'ALB, donc l'IP publique n'expose rien |
| CIDR `10.0.0.0/16`, subnets `/24` calculés par `cidrsubnet()` | CIDR écrits à la main | la variable `vpc_cidr` suffit à décaler tout le plan d'adressage |
| Zones choisies par `data "aws_availability_zones"` | zones écrites en dur | le code reste valable si une zone devient indisponible |
| AMI choisie par `data "aws_ami"` avec `most_recent` | identifiant d'AMI figé en variable | toujours la dernière AL2023 corrigée ; en contrepartie, une nouvelle AMI publiée fait apparaître un changement au `plan`, à vérifier avant le gel |
| Instances `t3.micro` | taille supérieure | suffisant pour servir une page ; préserve les crédits étudiants |
| State dans S3 avec `use_lockfile` | table DynamoDB pour le verrou | le verrou natif S3 suffit depuis Terraform 1.10 |
| Bucket du state créé par script AWS CLI, hors du state | bucket géré par Terraform | le backend doit exister avant le premier `init` ; hors du state, un `destroy` ne peut pas le supprimer |
| Amorçage par script court | image Packer | plus rapide à mettre au point ; Packer était une extension possible |
| Secret en `value_wo` | `value` classique | `value_wo` n'est jamais écrit dans le state |
| CI authentifiée par rôle OIDC | clés d'accès AWS dans les secrets GitHub | aucun secret long terme stocké ; credentials de quelques minutes, limités au dépôt (voir SECURITE.md) |
| Rôle IAM dédié par environnement pour les instances | un profil commun aux permissions larges | moindre privilège : l'instance de dev ne lit pas le secret de prod |
| Organisation à deux comptes : gestion (facturation, Organizations, Identity Center) et compte projet `novasphere` 193131272485 | tout déployer dans le compte de départ | le compte de gestion ne porte aucune ressource ; les coéquipiers n'ont accès qu'au compte projet |
| dev et prod dans le même compte, séparés par la clé du state | un compte AWS par environnement | isolation plus forte en entreprise, mais hors périmètre du cahier des charges et plus lourd à gérer sur quatre semaines |
| Identity Center en région unique (eu-west-3), chiffrement par clé gérée par AWS | instance multi-région avec clé KMS gérée par le client | la réplication impose une clé KMS facturée, inutile pour une équipe de quatre sur une seule région |
| MFA par application d'authentification, exigé à chaque connexion | clés FIDO2 / Windows Hello | FIDO2 résiste au hameçonnage et serait le choix en entreprise, mais exige du matériel que l'équipe n'a pas |
| Un utilisateur SSO par membre dans le compte projet | partager les identifiants d'un compte | traçabilité et révocation individuelle |

## Extension : administration sans SSH (Session Manager)

Les instances sont administrées par AWS Systems Manager Session Manager. Aucun port 22 n'est ouvert et aucune paire de clés n'existe. L'agent SSM est préinstallé sur Amazon Linux 2023 et joint les endpoints SSM par l'IP publique de l'instance, sans NAT ni VPC endpoint.

Le fonctionnement a été vérifié dès la séance 8 : une instance de test portant la politique `AmazonSSMManagedInstanceCore` est remontée en *Online* dans Systems Manager → Fleet Manager, puis a été détruite. Le mécanisme est donc validé sur ce compte.

Écartés : le bastion (il réintroduit SSH et une instance de plus) et les VPC endpoints SSM (facturés à l'heure, inutiles ici).

Le rôle des instances porte uniquement les actions nécessaires à Session Manager (voir SECURITE.md).

À COMPLÉTER : capture ou commande de la session ouverte sur une instance de prod.
