# SPECS — GitLab on AWS (EC2 pur)

**Version :** 1.8
**Date :** 2026-03-27
**Statut :** Production
**Cible :** 20–100 utilisateurs

---

## 1. Contexte et objectif

Migration de l'architecture ECS EC2-launch-type vers **EC2 pur avec Auto Recovery**, AMI GitLab CE officielle, et volume EBS persistant centralisé. L'objectif est de simplifier la stack en supprimant la couche ECS/Docker et de faire tourner GitLab Omnibus directement sur l'instance EC2.

---

## 2. Architecture cible

### Vue d'ensemble

```
Internet
  │
  ├── ALB (HTTP/HTTPS 80/443) ──► EC2 t3.xlarge (GitLab Omnibus) ──► EBS 100 GB gp3 (persistant)
  │                                        │
  └── NLB (SSH 22)       ──────────────────┘
                                           │
                              ┌────────────┴────────────┐
                              │                         │
                         RDS PostgreSQL           ElastiCache Valkey
                         db.t3.medium             cache.t4g.small
                         Single-AZ                1 nœud
```

### Composants conservés sans changement

| Composant | Config |
|---|---|
| ALB | HTTP→HTTPS redirect, TLS termination (ACM), health check `/-/readiness` |
| NLB | SSH TCP passthrough port 22 |
| S3 | Bucket unique — artifacts, uploads, LFS, packages, CI secure files, Pages, Dependency Proxy — SSE-AES256 explicite, lifecycle noncurrent 30j + expiry artifacts 90j |
| ACM | Certificat TLS auto-géré |
| Route53 | `gitlab.<domain>` → ALB, `ssh.gitlab.<domain>` → NLB |
| Secrets Manager | Passwords RDS + Redis **générés** (`random_password`), SMTP password dérivé de l'access key SES — aucun secret en variable tfvars |
| CloudWatch | Log group 30j de rétention |
| AWS Backup | Snapshot EC2 quotidien à 02h00, rétention 7 jours, vault custom `${project_name}-backup` |
| SES | Domaine vérifié (DKIM, mail-from, SPF/MX Route53) ; IAM user dédié + access key ; SMTP password stocké dans Secrets Manager ; `smtp_address` et `smtp_port` calculés dynamiquement dans `ses.tf` (locals) |

### Composants modifiés

| Composant | Avant | Après |
|---|---|---|
| RDS PostgreSQL | Multi-AZ | **Single-AZ** (`multi_az = false`) |
| ElastiCache | cache.t4g.micro, 2 nœuds | **cache.t4g.small, 1 nœud** (`num_cache_clusters = 1`) |
| ALB target group | `target_type = "ip"` | `target_type = "instance"` |
| NLB target group | `target_type = "ip"` | `target_type = "instance"` |
| IAM | Rôles ECS séparés | Rôle EC2 unifié |
| Security groups | SG `ecs` + SG `ec2` | SG `ec2` unique |
| AMI | ECS-optimisée (SSM) | **GitLab CE officielle** (owner `782774275127`, filtrée par `gitlab_version`) |
| Résilience EC2 | ASG min=1, max=1 | **`aws_instance` + CloudWatch Auto Recovery** |
| Enregistrement LB | ASG `target_group_arns` | **`aws_lb_target_group_attachment`** x2 |

### Composants supprimés

| Composant | Raison |
|---|---|
| `aws_ecs_cluster` | Plus de ECS |
| `aws_ecs_task_definition` | Plus de container Docker |
| `aws_ecs_service` | Plus de ECS |
| `aws_ecs_capacity_provider` | Plus de ECS |
| `aws_ecs_cluster_capacity_providers` | Plus de ECS |
| `aws_iam_role.ecs_task_execution` | Remplacé par rôle EC2 unifié |
| `aws_iam_role.ecs_task` | Remplacé par rôle EC2 unifié |
| `aws_security_group.ecs` | Remplacé par SG `ec2` étendu |
| `aws_autoscaling_group` | Remplacé par Auto Recovery |
| `aws_launch_template` | Remplacé par `aws_instance` direct |
| `aws_ebs_volume` | Remplacé par `root_block_device` dans `aws_instance` |
| `aws_volume_attachment` | Volume racine géré nativement |
| `aws_dlm_lifecycle_policy` | Données binaires sur S3, snapshot AMI si besoin |
| `aws_iam_role.dlm` | DLM supprimé |

---

## 3. Stratégie HA — "HA ready, payer plus tard"

L'infrastructure est conçue pour être upgradée vers le full HA sans changement d'architecture — uniquement des modifications de variables Terraform.

| Composant | Config initiale | Config HA | Coût initial | Migration |
|---|---|---|---|---|
| EC2 | `aws_instance` unique + Auto Recovery | Multi-instance derrière LB | $138/mois | Refactoring ASG nécessaire |
| RDS | Single-AZ | `multi_az = true` | $60/mois | ~2 min downtime |
| ElastiCache | 1 nœud | `num_cache_clusters = 2` | $21/mois | Live, sans interruption |

**Coût total estimé (eu-west-3, on-demand) : ~$271/mois**
**Coût full HA : ~$352/mois** (+$81/mois quand le besoin se présente)

---

## 4. État des fichiers Terraform

### `backup.tf` — implémenté

- `aws_backup_vault` — vault custom `${project_name}-backup`
- `aws_backup_plan` — snapshot quotidien à 02h00, rétention 7 jours
- `aws_backup_selection` — cible `aws_instance.gitlab` par ARN direct

### `cloudwatch.tf` — implémenté

- `aws_cloudwatch_log_group` — `/ec2/gitlab`, rétention 30 jours
- `aws_cloudwatch_metric_alarm` — Auto Recovery sur `StatusCheckFailed_System` (2× 60s)

### `data.tf` — implémenté

- `data "aws_route53_zone"` — lookup de la zone par `var.route53_zone_name`
- `data "aws_ami" "gitlab_ce"` — AMI GitLab CE officielle (owner `782774275127`), filtrée par `var.gitlab_version`
- `data "aws_subnet"` — subnet privé primaire pour l'instance EC2
- `data "aws_vpc"` — dérive le CIDR VPC depuis `var.vpc_id` (plus de variable `vpc_cidr_block`)

### `ec2.tf` — implémenté

Contient :
- `aws_instance` — instance directe, subnet privé[0], IMDSv2, `root_block_device` 100 GB gp3 chiffré
- `aws_lb_target_group_attachment` x2 — enregistrement manuel ALB + NLB
- `user_data = templatefile(...)` — injection des endpoints statiques au plan

### `iam.tf` — réécrit

Rôles ECS et DLM supprimés. Policy inline attachée au rôle `ec2_instance` couvrant :

| Permission | Usage |
|---|---|
| `s3:GetObject/PutObject/DeleteObject/ListBucket` | Object store GitLab |
| `logs:CreateLogStream/PutLogEvents` | CloudWatch Logs |
| `secretsmanager:GetSecretValue` | RDS password + Redis token + SMTP password au boot |
| `ssm:*` | SSM Session Manager (via `AmazonSSMManagedInstanceCore` dans ec2.tf) |

Rôle AWS Backup séparé (`aws_iam_role.backup`) avec `AWSBackupServiceRolePolicyForBackup`.

IAM user dédié `${project_name}-ses-smtp` avec policy `ses:SendRawEmail` + access key — le `ses_smtp_password_v4` de la clé est stocké dans Secrets Manager et injecté comme mot de passe SMTP au boot.

### `local.tf` — implémenté

- `ses_domain` — domaine extrait du nom de zone Route53
- `smtp_address` — `email-smtp.${var.aws_region}.amazonaws.com`
- `smtp_port` — `587`
- `gitlab_domain` — `gitlab.${var.route53_zone_name}`
- `smtp_from_address` — `gitlab@${local.ses_domain}`

### `security-groups.tf` — mis à jour

- `aws_security_group.ecs` supprimé
- `aws_security_group.ec2` : ingress port 80 depuis `aws_security_group.alb` + ingress port 22 depuis `aws_security_group.nlb`
- `aws_security_group.rds` : référence `ec2` (anciennement `ecs`)
- `aws_security_group.redis` : référence `ec2` (anciennement `ecs`)

### `alb.tf` — mis à jour

- `target_type = "instance"`

### `nlb.tf` — mis à jour

- `target_type = "instance"`

### `elasticache.tf` — mis à jour

- `node_type = "cache.t4g.small"`
- `num_cache_clusters = 1`
- `automatic_failover_enabled` / `multi_az_enabled` supprimés

### `rds.tf` — mis à jour

- `engine_version = "17.2"`, family `postgres17`
- `multi_az = false`

### `variables.tf` — état final

- `gitlab_image` supprimé (plus de Docker)
- `gitlab_version` présent (string, ex: `"17.9.1"`)
- `rds_master_password` / `redis_auth_token` supprimés — générés par `random_password`
- `vpc_cidr_block` supprimé — dérivé via `data "aws_vpc"` depuis `var.vpc_id`
- `route53_zone_id` supprimé — remplacé par `route53_zone_name` (string, ex: `"example.com"`) ; l'ID de zone est lookup par `data "aws_route53_zone"`
- SMTP : seul `smtp_from_address` est une variable ; `smtp_address`, `smtp_port` sont des locals dans `local.tf` (calculés depuis `var.aws_region`) ; `smtp_user_name` et `smtp_password` viennent de l'access key SES (non variables)

### `ses.tf` — implémenté

- `aws_ses_domain_identity` — vérification du domaine Route53
- `aws_ses_domain_dkim` — clés DKIM + 3 `aws_route53_record` CNAME
- `aws_ses_domain_mail_from` — domaine `mail.<domain>` + records MX et SPF Route53

### `user_data.sh.tpl` — implémenté

1. Récupération des secrets depuis Secrets Manager (DB password, Redis token, SMTP password)
2. Écriture `/etc/gitlab/gitlab.rb` avec :
   - `external_url`
   - PostgreSQL externe (RDS)
   - Redis externe (ElastiCache)
   - Object store S3
   - SSH host
   - nginx real_ip (CIDR VPC)
   - letsencrypt désactivé
   - SMTP
4. `gitlab-ctl reconfigure`

**Mécanisme :** valeurs statiques (endpoints RDS, Redis, S3, Route53, ARNs secrets) injectées par `templatefile()` au `terraform plan`. Secrets (passwords) récupérés dynamiquement au boot via `aws secretsmanager get-secret-value` et injectés dans `gitlab.rb` via heredoc bash.

---

## 5. Décisions architecturales et justifications

| Décision | Alternative écartée | Raison |
|---|---|---|
| Garder ALB + NLB séparés | NLB unique (80/443/22) | ALB apporte : redirect HTTP natif, health check HTTP `/-/readiness`, WAF-ready |
| Garder Secrets Manager | SSM Parameter Store (gratuit) | $0.80/mois pour 2 secrets, rotation automatique possible, standard AWS pour credentials en prod |
| Volume racine EC2 (`root_block_device`) | EBS séparé `aws_ebs_volume` | Données lourdes sur S3 — simplicité prime ; supprime DLM, IAM DLM, logique de montage. EBS séparé supprimé. |
| cache.t4g.small | cache.t4g.micro | Plus confortable pour 20-100 users avec usage intensif sessions/cache CI |
| EC2 t3.xlarge (4 vCPU, 16 GB) | t3.medium | GitLab Omnibus recommande minimum 8 GB RAM. 16 GB offre de la marge pour la charge CI |
| RDS Single-AZ | Multi-AZ dès le départ | Stratégie "HA ready, payer plus tard" : upgrade en 1 ligne Terraform + ~2 min downtime |
| ElastiCache 1 nœud | 2 nœuds dès le départ | Stratégie "HA ready, payer plus tard" : upgrade live sans interruption |
| `aws_instance` + Auto Recovery | ASG min=1, max=1 | Plus simple, même résilience pour single-instance. Pas de remplacement d'instance (même ID préservé) |
| AMI GitLab CE officielle | AMI ECS-optimisée + install apt | GitLab pré-installé, pas de bootstrap package au boot |
| AWS SES (`ses:SendRawEmail` IAM) | SMTP vendor externe | Natif AWS, domaine déjà dans Route53, coût négligeable |

---

## 6. Ce qui n'est PAS dans ce plan

- Multi-AZ EC2 — incompatible avec EBS single-AZ persistant
- WAF sur l'ALB — possible ultérieurement sans changement d'architecture
- GitLab Registry (Container Registry) — hors scope initial
- Rotation automatique des secrets Secrets Manager — possible via Lambda rotation, non configuré
