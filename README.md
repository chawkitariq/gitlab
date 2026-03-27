# GitLab Infrastructure on AWS

Deploys a production GitLab instance on AWS using Terraform. GitLab runs as **GitLab Omnibus directly on EC2** using the official GitLab CE AMI.

## Architecture

Dual load balancer pattern with EC2 as the single compute unit:

![GitLab AWS Infrastructure](docs/gitlab-aws-infra.png)

| Component | Details |
|---|---|
| EC2 | t3.xlarge (4 vCPU, 16 GB RAM) — GitLab Omnibus, IMDSv2, SSM access |
| EBS | gp3 100 GB encrypted — root volume (`root_block_device`), daily snapshots via AWS Backup (7-day retention) |
| ALB | HTTP→HTTPS redirect, TLS termination (ACM), health check `/-/readiness` |
| NLB | SSH TCP passthrough port 22 |
| RDS | PostgreSQL 17.2, db.t3.medium, Single-AZ |
| ElastiCache | Valkey/Redis 7.0, cache.t4g.small, 1 node |
| S3 | Artifacts, uploads, LFS, packages, CI secure files — versioning + lifecycle |
| Secrets Manager | RDS password + Redis token auto-generated (`random_password`) + SES SMTP password (from IAM access key) |
| SES | Domain identity, DKIM, mail-from — SMTP via `email-smtp.<region>.amazonaws.com:587` |
| Route53 | `gitlab.<domain>` → ALB, `ssh.gitlab.<domain>` → NLB |
| CloudWatch | Log group (30-day retention) + Auto Recovery alarm |

## Prerequisites

- AWS account with appropriate permissions
- Terraform >= 1.10.0
- Existing VPC with public and private subnets
- Route53 hosted zone

## Quick Start

### 1. Configure Variables

Create `terraform/terraform.tfvars`:

```hcl
aws_region          = "eu-west-3"
project_name        = "gitlab"
vpc_id              = "vpc-xxxxxxxx"
public_subnet_ids   = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]
private_subnet_ids  = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]
route53_zone_name   = "example.com"
gitlab_version      = "17.9.1"
rds_master_username = "gitlab"
```

> `gitlab_domain` (`gitlab.<zone>`) and `smtp_from_address` (`gitlab@<zone>`) are computed automatically from `route53_zone_name`.

### 2. Deploy

```bash
cd terraform

terraform init \
  -backend-config="bucket=ct-s3-state-backend" \
  -backend-config="key=gitlab-terraform.tfstate" \
  -backend-config="region=eu-west-3"

terraform plan
terraform apply
```

### 3. Access GitLab

- **Web UI**: `https://gitlab.<domain>`
- **Git SSH**: `ssh.gitlab.<domain>`

```bash
# Via SSM Session Manager (no SSH key needed)
aws ssm start-session --target <instance-id>

# Initial root password
sudo cat /etc/gitlab/initial_root_password
```

## Updating GitLab

Change the version in `terraform.tfvars`:

```hcl
gitlab_version = "17.10.0"
```

Then apply — the instance will be recreated with the new AMI:

```bash
terraform apply
```

> **Note:** GitLab repository data and artifacts are stored on S3 and persist across instance replacements. The root EBS volume is recreated with the instance; AWS Backup snapshots provide point-in-time recovery.

## Security

- RDS and ElastiCache in private subnets only
- Security groups restrict inter-component traffic
- IMDSv2 enforced on EC2
- Secrets Manager for all credentials (no plaintext passwords in state)
- S3 bucket access restricted to EC2 instance role

## HA Upgrade Path

The infrastructure is designed for zero-architecture HA upgrades (variable changes only):

| Component | Current | HA | Trigger |
|---|---|---|---|
| RDS | Single-AZ | `multi_az = true` | ~2 min downtime |
| ElastiCache | 1 node | `num_cache_clusters = 2` | Live, no interruption |
| EC2 | Single instance + Auto Recovery | ASG | Requires refactoring |
