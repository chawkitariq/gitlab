resource "aws_route53_record" "gitlab" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.gitlab_domain
  type    = "A"

  alias {
    name                   = aws_lb.gitlab.dns_name
    zone_id                = aws_lb.gitlab.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "gitlab_ssh" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "ssh.${aws_route53_record.gitlab.name}"
  type    = "A"

  alias {
    name                   = aws_lb.gitlab_ssh.dns_name
    zone_id                = aws_lb.gitlab_ssh.zone_id
    evaluate_target_health = true
  }
}
