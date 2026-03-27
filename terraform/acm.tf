resource "aws_acm_certificate" "gitlab" {
  domain_name               = local.gitlab_domain
  subject_alternative_names = [local.gitlab_domain, "*.${local.gitlab_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-certificate"
  }
}

resource "aws_route53_record" "gitlab_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.gitlab.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.this.zone_id
}

resource "aws_acm_certificate_validation" "gitlab" {
  certificate_arn         = aws_acm_certificate.gitlab.arn
  validation_record_fqdns = [for record in aws_route53_record.gitlab_cert_validation : record.fqdn]
}
