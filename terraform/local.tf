locals {
  ses_domain        = trimsuffix(data.aws_route53_zone.this.name, ".")
  smtp_address      = "email-smtp.${var.aws_region}.amazonaws.com"
  smtp_port         = 587
  gitlab_domain     = "gitlab.${var.route53_zone_name}"
  smtp_from_address = "gitlab@${local.ses_domain}"
}