# SPECS — GitLab on AWS (EC2)

**Version :** 2.0
**Date :** 2026-03-29
**Statut :** Production
**Cible :** 20–100 utilisateurs

---

## 1. Contexte et objectif

GitLab CE tourne en **Omnibus directement sur EC2** via l'AMI officielle GitLab CE. L'architecture privilégie la simplicité opérationnelle : un seul nœud de calcul, des services managés AWS pour la persistance, et une stratégie "HA ready, payer plus tard" permettant de passer en haute disponibilité par simple modification de variables Terraform.

---

## 2. Architecture

### Vue d'ensemble

```
Internet
  │
  ├── ALB (HTTP 80 → HTTPS 443) ──► EC2 t3.xlarge (GitLab Omnibus) ──► EBS 100 GB gp3
  │                                          │
  └── NLB (SSH 22)        ───────────────────┘
                                             │
                                ┌────────────┴────────────┐
                                │                         │
                           RDS PostgreSQL           ElastiCache Redis
                           db.t3.medium             cache.t4g.small
                           Single-AZ                1 nœud
```

### Composants

| Composant | Configuration |
|---|---|
| **EC2** | t3.xlarge (4 vCPU, 16 GB RAM) — AMI GitLab CE officielle (owner `782774275127`), subnet privé, IMDSv2, SSM Session Manager |
| **EBS** | 100 GB gp3 chiffré — volume racine (`root_block_device`), `delete_on_termination = true` |
| **ALB** | HTTP→HTTPS redirect natif, TLS termination (ACM), `target_type = "instance"`, health check `/-/readiness` |
| **NLB** | SSH TCP passthrough port 22, `target_type = "instance"` |
| **RDS** | PostgreSQL 17.2, db.t3.medium, Single-AZ, 20 GB (autoscale jusqu'à 100), chiffrement au repos, `deletion_protection = true`, rétention backup 7 jours |
| **ElastiCache** | Redis 7.0, cache.t4g.small, 1 nœud, chiffrement en transit + au repos, auth token |
| **S3** | Bucket unique — artifacts, uploads, LFS, packages, CI secure files, Pages, Dependency Proxy — SSE-AES256, versioning, politique TLS-only, lifecycle noncurrent 30j + expiry artifacts 90j |
| **ACM** | Certificat TLS auto-géré pour `gitlab.<domain>` |
| **Secrets Manager** | Passwords RDS + Redis générés par `random_password` ; SMTP password dérivé de l'access key SES — aucun secret en variable tfvars |
| **SES** | Domaine vérifié (DKIM, mail-from), records Route53 (3 CNAME DKIM, MX, SPF TXT) ; IAM user dédié + access key ; SMTP via `email-smtp.<region>.amazonaws.com:587` |
| **Route53** | `gitlab.<zone>` → ALB ; `ssh.gitlab.<zone>` → NLB |
| **CloudWatch** | Log group `/ec2/${project_name}-gitlab` (30j rétention) ; alarme Auto Recovery sur `StatusCheckFailed_System` (2× 60s → `ec2:recover`) |
| **AWS Backup** | Vault `${project_name}-backup`, snapshot EC2 quotidien à 02h00 UTC, rétention 7 jours |
| **IAM** | Rôle EC2 unifié (`AmazonSSMManagedInstanceCore` + inline S3/Logs/Secrets) ; rôle Backup (`AWSBackupServiceRolePolicyForBackup`) ; IAM user SES SMTP (`ses:SendRawEmail`) |

---

## 3. Variables Terraform

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `aws_region` | string | — | Région AWS de déploiement |
| `project_name` | string | `"gitlab"` | Préfixe des ressources |
| `vpc_id` | string | — | ID du VPC |
| `public_subnet_ids` | list(string) | — | Subnets publics pour l'ALB |
| `private_subnet_ids` | list(string) | — | Subnets privés pour EC2, RDS, ElastiCache |
| `route53_zone_name` | string | — | Zone hosted Route53 (ex : `example.com`) |
| `gitlab_version` | string | — | Version GitLab CE (ex : `"17.9.1"`) |
| `ec2_instance_type` | string | `"t3.xlarge"` | Type d'instance EC2 |
| `ebs_volume_size` | number | `100` | Taille GB du volume racine |
| `rds_master_username` | string | `"gitlab"` | Utilisateur maître RDS |

### Locals calculés (`local.tf`)

| Local | Valeur |
|---|---|
| `ses_domain` | Domaine extrait du nom de zone Route53 |
| `smtp_address` | `email-smtp.${var.aws_region}.amazonaws.com` |
| `smtp_port` | `587` |
| `gitlab_domain` | `gitlab.${var.route53_zone_name}` |
| `smtp_from_address` | `gitlab@${local.ses_domain}` |

---

## 4. Boot sequence (`user_data.sh.tpl`)

1. Récupération des 3 secrets depuis Secrets Manager (RDS password, Redis auth token, SMTP password)
2. Écriture de `/etc/gitlab/gitlab.rb` avec :
   - `external_url`
   - PostgreSQL externe (RDS endpoint + port + credentials)
   - Redis externe (ElastiCache primary endpoint + auth token)
   - Object store S3 (bucket + région, connexion IAM role)
   - SSH host (`ssh.gitlab.<domain>`)
   - nginx `real_ip_trusted_addresses` (CIDR VPC)
   - Let's Encrypt désactivé (TLS géré par ACM sur l'ALB)
   - SMTP (SES)
3. `gitlab-ctl reconfigure`

**Mécanisme de templating :** les valeurs statiques (endpoints RDS, Redis, S3, ARNs secrets, SMTP address) sont injectées par `templatefile()` au `terraform plan`. Les secrets (passwords) sont récupérés dynamiquement au boot via `aws secretsmanager get-secret-value`.

`user_data_replace_on_change = true` : toute modification du template ou de ses variables déclenche un remplacement d'instance.

---

## 5. Stratégie HA — "HA ready, payer plus tard"

L'infrastructure est upgradeable vers le full HA sans changement d'architecture — uniquement des modifications de variables Terraform.

| Composant | Config actuelle | Config HA | Coût actuel | Migration |
|---|---|---|---|---|
| EC2 | `aws_instance` unique + Auto Recovery | Multi-instance derrière LB | ~$138/mois | Refactoring ASG nécessaire |
| RDS | Single-AZ | `multi_az = true` | ~$60/mois | ~2 min downtime |
| ElastiCache | 1 nœud | `num_cache_clusters = 2` | ~$21/mois | Live, sans interruption |

**Coût total estimé (eu-west-3, on-demand) : ~$271/mois**
**Coût full HA : ~$352/mois** (+$81/mois sur activation)

---

## 6. Sécurité

| Mesure | Détail |
|---|---|
| Réseau | RDS et ElastiCache en subnets privés uniquement ; security groups restreints par composant |
| EC2 | IMDSv2 obligatoire (`http_tokens = "required"`) |
| Credentials | Secrets Manager pour tous les credentials — aucun secret en variable tfvars ni en state Terraform en clair |
| S3 | Politique TLS-only (`aws:SecureTransport`), accès restreint au rôle EC2 |
| RDS | `deletion_protection = true`, `storage_encrypted = true`, snapshot final à la suppression |
| ElastiCache | `transit_encryption_enabled = true`, `at_rest_encryption_enabled = true` |
| EBS | Volume racine chiffré (`encrypted = true`) |
| Accès opérationnel | SSM Session Manager — aucun port SSH exposé sur l'instance, aucune clé SSH nécessaire |

---

## 7. Décisions architecturales

| Décision | Alternative écartée | Raison |
|---|---|---|
| ALB + NLB séparés | NLB unique (80/443/22) | ALB apporte : redirect HTTP natif, health check HTTP `/-/readiness`, WAF-ready |
| Secrets Manager | SSM Parameter Store (gratuit) | $0.80/mois pour 3 secrets — rotation automatique possible, standard AWS pour credentials prod |
| Volume racine EC2 (`root_block_device`) | EBS séparé `aws_ebs_volume` | Données lourdes sur S3 — supprime DLM, IAM DLM, logique de montage |
| cache.t4g.small | cache.t4g.micro | Plus confortable pour 20-100 users avec charge CI |
| EC2 t3.xlarge | t3.medium | GitLab Omnibus recommande minimum 8 GB RAM — 16 GB donne de la marge CI |
| RDS Single-AZ | Multi-AZ dès le départ | Stratégie "HA ready" : upgrade en 1 ligne Terraform + ~2 min downtime |
| ElastiCache 1 nœud | 2 nœuds dès le départ | Stratégie "HA ready" : upgrade live sans interruption |
| `aws_instance` + Auto Recovery | ASG min=1, max=1 | Plus simple, même résilience — ID d'instance préservé lors d'un recovery |
| AMI GitLab CE officielle (owner `782774275127`) | AMI générique + install apt | GitLab pré-installé — bootstrap réduit à la configuration |
| SES (`ses:SendRawEmail`) | SMTP vendor externe | Natif AWS, domaine déjà dans Route53, coût négligeable |

---

## 8. Hors scope

- Multi-AZ EC2 — incompatible avec EBS single-AZ persistant
- WAF sur l'ALB — possible ultérieurement sans changement d'architecture
- GitLab Container Registry — hors scope initial
- Rotation automatique des secrets Secrets Manager — possible via Lambda, non configuré
