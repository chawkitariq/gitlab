locals {
  runner_instance_arn = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.gitlab_runner.id}"
}

resource "aws_iam_role" "runner_scheduler" {
  name = "${var.project_name}-runner-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "runner_scheduler" {
  name = "${var.project_name}-runner-scheduler"
  role = aws_iam_role.runner_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:StartInstances", "ec2:StopInstances"]
      Resource = local.runner_instance_arn
    }]
  })
}

resource "aws_scheduler_schedule" "runner_stop" {
  name       = "${var.project_name}-runner-stop"
  group_name = "default"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = var.runner_schedule_stop
  schedule_expression_timezone = var.runner_schedule_timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.runner_scheduler.arn
    input    = jsonencode({ InstanceIds = [aws_instance.gitlab_runner.id] })
  }
}

resource "aws_scheduler_schedule" "runner_start" {
  name       = "${var.project_name}-runner-start"
  group_name = "default"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = var.runner_schedule_start
  schedule_expression_timezone = var.runner_schedule_timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.runner_scheduler.arn
    input    = jsonencode({ InstanceIds = [aws_instance.gitlab_runner.id] })
  }
}
