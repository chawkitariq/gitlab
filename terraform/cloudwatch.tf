resource "aws_cloudwatch_log_group" "gitlab" {
  name              = "/ec2/${var.project_name}-gitlab"
  retention_in_days = 30
}

resource "aws_cloudwatch_metric_alarm" "gitlab_auto_recover" {
  alarm_name          = "${var.project_name}-auto-recover"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = aws_instance.gitlab.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = ["arn:aws:automate:${var.aws_region}:ec2:recover"]
}
