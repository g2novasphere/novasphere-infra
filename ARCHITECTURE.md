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
      │ EC2 (ASG)        │      │ EC2 (ASG)         │
      │ SG web : 80 ← SG alb uniquement, aucun port 22
      └────────┬─────────┘      └────────┬──────────┘
               │ IMDSv2, rôle IAM novasphere-<env>-instance (moindre privilège)
               ├──► SSM Parameter Store  /novasphere/<env>/app_secret (SecureString)
               └──► Session Manager (administration sans SSH)

  VPC : module public terraform-aws-modules/vpc, 2 AZ, pas de NAT Gateway
  ASG : minimum 2 instances, Launch Template, health_check_type = "ELB"
  State : S3 novasphere-tfstate-<compte>, versionné, chiffré, use_lockfile
          clés novasphere/dev/terraform.tfstate et novasphere/prod/terraform.tfstate
  CI : GitHub Actions authentifiée par OIDC (aucune clé AWS stockée)
       PR : fmt, validate, plan ; merge : apply dev ; prod après approbation
  Compte : compte AWS personnel du référent AWS (crédits étudiants), un utilisateur SSO par membre
```

## Décisions et alternatives écartées

| Décision | Alternative écartée | Raison |
|---|---|---|
| Deux répertoires `envs/dev` et `envs/prod` | workspaces Terraform | interdits par le cahier des charges ; des répertoires rendent le backend et l'environnement visibles |
| Code commun dans le module `terraform-aws-novasphere-web` appelé par tag | copier le code dans chaque environnement | dev et prod ne doivent différer que par les variables ; un tag fige une version testée |
| Région eu-west-3 (Paris) | us-east-1 | proche des utilisateurs et de l'équipe ; la contrainte us-east-1 ne valait que pour le Learner Lab |
| VPC du registre public | VPC écrit à la main | imposé, et maintenu par la communauté |
| Subnets publics sans NAT Gateway | subnets privés + NAT | une NAT Gateway est facturée à l'heure ; le SG web n'accepte que l'ALB, donc l'IP publique n'expose rien |
| State dans S3 avec `use_lockfile` | table DynamoDB pour le verrou | le verrou natif S3 suffit depuis Terraform 1.10 |
| Bucket du state créé par script AWS CLI | bucket géré par Terraform | le backend doit exister avant le premier `init` |
| Amorçage par script court | image Packer | plus rapide à mettre au point ; Packer était une extension possible |
| Secret en `value_wo` | `value` classique | `value_wo` n'est jamais écrit dans le state |
| CI authentifiée par rôle OIDC | clés d'accès AWS dans les secrets GitHub | aucun secret long terme stocké ; credentials de quelques minutes, limités au dépôt (voir SECURITE.md) |
| Rôle IAM dédié par environnement pour les instances | un profil commun aux permissions larges | moindre privilège : l'instance de dev ne lit pas le secret de prod |
| Un seul compte, un utilisateur SSO par membre | partager les identifiants d'un compte | traçabilité et révocation individuelle |

À COMPLÉTER : toute décision prise pendant le projet (taille d'instance, AMI, etc.).

## Extension : administration sans SSH (Session Manager)

Les instances sont administrées par AWS Systems Manager Session Manager. Aucun port 22 n'est ouvert et aucune paire de clés n'existe. L'agent SSM est préinstallé sur Amazon Linux 2023 et joint les endpoints SSM par l'IP publique de l'instance, sans NAT ni VPC endpoint.

Écartés : le bastion (il réintroduit SSH et une instance de plus) et les VPC endpoints SSM (facturés à l'heure, inutiles ici).

Le rôle des instances porte uniquement les actions nécessaires à Session Manager (voir SECURITE.md).

À COMPLÉTER : capture ou commande de la session ouverte sur une instance de prod.
