resource "aws_instance" "gitlab" {
  ami                    = data.aws_ami.gitlab_ce.id
  instance_type          = var.ec2_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.gitlab.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    aws_region        = var.aws_region
    external_url      = aws_route53_record.gitlab.fqdn
    db_host           = aws_db_instance.gitlab.address
    db_port           = aws_db_instance.gitlab.port
    db_name           = aws_db_instance.gitlab.db_name
    db_username       = aws_db_instance.gitlab.username
    redis_host        = aws_elasticache_replication_group.gitlab.primary_endpoint_address
    s3_bucket         = aws_s3_bucket.gitlab.bucket
    ssh_host          = aws_route53_record.gitlab_ssh.fqdn
    vpc_cidr          = data.aws_vpc.this.cidr_block
    rds_secret_arn    = aws_secretsmanager_secret.rds_password.arn
    redis_secret_arn  = aws_secretsmanager_secret.redis_auth_token.arn
    smtp_secret_arn   = aws_secretsmanager_secret.smtp_password.arn
    smtp_address      = local.smtp_address
    smtp_port         = local.smtp_port
    smtp_user_name    = aws_iam_access_key.ses.id
    smtp_from_address = local.smtp_from_address
  })

  root_block_device {
    volume_size           = var.ebs_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data_replace_on_change = true

  tags = {
    Name = var.project_name
  }
}
