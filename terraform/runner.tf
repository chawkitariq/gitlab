data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "gitlab_runner" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.runner_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.runner.id]
  iam_instance_profile   = aws_iam_instance_profile.runner.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/runner_user_data.sh.tpl", {
    aws_region              = var.aws_region
    gitlab_url              = aws_route53_record.gitlab.fqdn
    admin_pat_secret_arn    = aws_secretsmanager_secret.gitlab_admin_pat.arn
    runner_token_secret_arn = aws_secretsmanager_secret.runner_token.arn
    runner_description      = "${var.project_name}-runner"
    runner_tag_list         = "ec2,docker,linux"
  })

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data_replace_on_change = true

  # Runner boots after GitLab EC2 so user_data can reach the GitLab API
  depends_on = [aws_instance.gitlab]

  tags = {
    Name = "${var.project_name}-runner"
  }
}
