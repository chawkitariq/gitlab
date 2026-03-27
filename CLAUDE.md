# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Terraform-only repository that deploys a production GitLab instance on AWS. There is no application code — all files are infrastructure definitions.

GitLab runs as **GitLab Omnibus directly on EC2** (t3.xlarge), using the official GitLab CE AMI. ECS/Docker was removed.

## Terraform Commands

```bash
cd terraform

# Initialize with S3 backend
terraform init \
  -backend-config="bucket=ct-s3-state-backend" \
  -backend-config="key=gitlab-terraform.tfstate" \
  -backend-config="region=eu-west-3"

terraform plan
terraform apply
```

## File Responsibilities

| File | Manages |
|---|---|
| `main.tf` | Terraform + provider configuration |
| `backend.tf` | S3 backend |
| `variables.tf` | All input variables |
| `data.tf` | All data sources (Route53 zone, GitLab CE AMI, primary private subnet) |
| `backup.tf` | AWS Backup vault, plan (daily 02h00, 7d retention), selection (EC2 instance by ARN) |
| `ec2.tf` | EC2 instance (`aws_instance`) with `root_block_device` 100 GB gp3 |
| `iam.tf` | EC2 IAM role, SSM attachment, instance profile, inline policy (S3 + Secrets Manager + CloudWatch) ; IAM user + access key for SES SMTP |
| `secrets.tf` | Secrets Manager secrets for RDS password, Redis token, SES SMTP password (derived from IAM access key) |
| `ses.tf` | SES domain identity, DKIM, mail-from, Route53 DNS records (DKIM CNAME, MX, SPF) |
| `user_data.sh.tpl` | Boot script: fetch secrets from Secrets Manager, write `gitlab.rb`, run `gitlab-ctl reconfigure` |
| `alb.tf` | ALB, HTTP→HTTPS redirect, target group, target group attachment |
| `nlb.tf` | NLB, SSH listener, target group, target group attachment |
| `rds.tf` | PostgreSQL instance (Single-AZ) |
| `elasticache.tf` | Valkey replication group (1 node, cache.t4g.small) |
| `s3.tf` | Artifact/storage bucket |
| `acm.tf` | TLS certificate provisioning |
| `route53.tf` | DNS A records for ALB and NLB |
| `security-groups.tf` | Ingress/egress rules between components |
| `cloudwatch.tf` | Log group (30-day retention) + EC2 Auto Recovery alarm |
| `outputs.tf` | Output values |
| `local.tf` | Computed locals: `ses_domain`, `smtp_address`, `smtp_port`, `gitlab_domain`, `smtp_from_address` |

## Repository Layout

| Path | Purpose |
|------|---------|
| `terraform/terraform.tfvars` | Environment-specific variable values (gitignored) |
| `docker-compose.yml` | Runs `hashicorp/terraform-mcp-server` locally (tooling only, not app infrastructure) |
| `docs/` | Architecture diagrams (Excalidraw + PNG) and LocalStack testing notes |
| `scripts/` | Helper scripts |
| `SPECS.md` | Authoritative architecture record (detailed decisions, component config, HA strategy, cost estimates) — **update whenever infrastructure changes** |
| `README.md` | Public-facing overview (architecture summary, quick start, access instructions) — **update whenever infrastructure changes** |

## Workflow Rules

**Before making any change to Terraform files:**
1. Read all affected files
2. Present a detailed plan (files to change, resources added/removed/modified, tradeoffs, risks)
3. Wait for explicit user approval before applying any modification

Never edit, create, or delete Terraform files without prior approval.

## Available Tools

Use these tools proactively — do not guess or web-search when a dedicated tool exists.

### MCP Servers

| Tool | When to use |
|------|-------------|
| `mcp__awslabs_aws-api-mcp-server__call_aws` | Query live AWS resources — verify deployed state, fetch resource IDs, check current config |
| `mcp__awslabs_aws-api-mcp-server__suggest_aws_commands` | Discover the right AWS CLI/API call for a task |
| `mcp__awslabs_aws-documentation-mcp-server__search_documentation` | Look up AWS resource arguments, service limits, or behavior before writing Terraform |
| `mcp__awslabs_cloudwatch-mcp-server__*` | Check logs, metrics, and alarms on the deployed GitLab instance |
| `mcp__awslabs_cost-explorer-mcp-server__*` | Estimate or audit AWS cost impact of infrastructure changes |
| `mcp__localstack-mcp-server__localstack-aws-client` | Simulate AWS resources locally before applying to production |

### Skills

| Skill | When to use |
|-------|-------------|
| `/terraform-code-generation:terraform-style-guide` | Writing or reviewing any new `.tf` code — ensures HCL style + latest provider versions |
| `/terraform-code-generation:terraform-search-import` | Bring existing AWS resources under Terraform management |
| `/commit-commands:commit-push-pr` | Commit, push, and open a PR in one step |
