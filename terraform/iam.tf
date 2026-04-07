resource "aws_iam_role" "ec2_instance" {
  name = "${var.project_name}-ec2-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "gitlab" {
  name = "${var.project_name}-ec2-instance"
  role = aws_iam_role.ec2_instance.name
}

data "aws_iam_policy_document" "ec2_instance_inline" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.gitlab.arn,
      "${aws_s3_bucket.gitlab.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.gitlab.arn}:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      aws_secretsmanager_secret.rds_password.arn,
      aws_secretsmanager_secret.redis_auth_token.arn,
      aws_secretsmanager_secret.smtp_password.arn
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:PutSecretValue"]
    resources = [aws_secretsmanager_secret.gitlab_admin_pat.arn]
  }

}

resource "aws_iam_role_policy" "ec2_instance_inline" {
  name   = "${var.project_name}-ec2-instance-inline"
  role   = aws_iam_role.ec2_instance.id
  policy = data.aws_iam_policy_document.ec2_instance_inline.json
}

resource "aws_iam_role" "backup" {
  name = "${var.project_name}-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_user" "ses_smtp" {
  name = "${var.project_name}-ses-smtp"
}

resource "aws_iam_user_policy" "ses_smtp" {
  name = "${var.project_name}-ses-smtp"
  user = aws_iam_user.ses_smtp.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ses:SendRawEmail"
      Resource = aws_ses_domain_identity.gitlab.arn
    }]
  })
}

resource "aws_iam_access_key" "ses" {
  user = aws_iam_user.ses_smtp.name
}

# --- GitLab Runner ---

resource "aws_iam_role" "runner" {
  name = "${var.project_name}-runner"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "runner_ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "runner" {
  name = "${var.project_name}-runner"
  role = aws_iam_role.runner.name
}

data "aws_iam_policy_document" "runner_inline" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.gitlab_admin_pat.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"]
    resources = [aws_secretsmanager_secret.runner_token.arn]
  }
}

resource "aws_iam_role_policy" "runner_inline" {
  name   = "${var.project_name}-runner-inline"
  role   = aws_iam_role.runner.id
  policy = data.aws_iam_policy_document.runner_inline.json
}
