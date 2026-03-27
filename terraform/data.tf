data "aws_caller_identity" "current" {}

data "aws_route53_zone" "this" {
  name = var.route53_zone_name
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_ami" "gitlab_ce" {
  most_recent = true
  owners      = ["782774275127"] # GitLab Inc.

  filter {
    name   = "name"
    values = ["GitLab CE ${var.gitlab_version}*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

