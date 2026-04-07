resource "aws_backup_vault" "gitlab" {
  name = "${var.project_name}-backup"
}

resource "aws_backup_plan" "gitlab" {
  name = "${var.project_name}-backup"

  rule {
    rule_name         = "daily-7d-retention"
    target_vault_name = aws_backup_vault.gitlab.name
    schedule          = "cron(0 2 * * ? *)"

    lifecycle {
      delete_after = 7
    }

    recovery_point_tags = {
      "gitlab-backup" = var.project_name
    }
  }
}

resource "aws_backup_selection" "gitlab" {
  name         = "${var.project_name}-ec2"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.gitlab.id

  resources = [aws_instance.gitlab.arn]
}
