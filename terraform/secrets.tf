resource "random_password" "rds" {
  length  = 32
  special = false
}

resource "random_password" "redis" {
  length           = 32
  special          = true
  override_special = "!&#"
}

resource "aws_secretsmanager_secret" "rds_password" {
  name = "${var.project_name}/rds-password"
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id     = aws_secretsmanager_secret.rds_password.id
  secret_string = random_password.rds.result
}

resource "aws_secretsmanager_secret" "redis_auth_token" {
  name = "${var.project_name}/redis-auth-token"
}

resource "aws_secretsmanager_secret_version" "redis_auth_token" {
  secret_id     = aws_secretsmanager_secret.redis_auth_token.id
  secret_string = random_password.redis.result
}

resource "aws_secretsmanager_secret" "smtp_password" {
  name = "${var.project_name}/smtp-password"
}

resource "aws_secretsmanager_secret_version" "smtp_password" {
  secret_id     = aws_secretsmanager_secret.smtp_password.id
  secret_string = aws_iam_access_key.ses.ses_smtp_password_v4
}
