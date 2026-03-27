output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.gitlab.dns_name
}

output "nlb_dns_name" {
  description = "NLB DNS name for SSH"
  value       = aws_lb.gitlab_ssh.dns_name
}

output "gitlab_url" {
  description = "GitLab external URL"
  value       = "https://${local.gitlab_domain}"
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.gitlab.endpoint
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.gitlab.primary_endpoint_address
}

output "s3_bucket" {
  description = "S3 bucket for GitLab"
  value       = aws_s3_bucket.gitlab.bucket
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.gitlab.arn
}
