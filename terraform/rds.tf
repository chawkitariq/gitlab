resource "aws_db_subnet_group" "gitlab" {
  name       = "${var.project_name}-rds-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_parameter_group" "gitlab" {
  name        = "${var.project_name}-rds-pg"
  family      = "postgres17"
  description = "GitLab PostgreSQL parameter group"
}

resource "aws_db_instance" "gitlab" {
  identifier                = "${var.project_name}-rds"
  engine                    = "postgres"
  engine_version            = "17.2"
  instance_class            = "db.t3.medium"
  allocated_storage         = 20
  max_allocated_storage     = 100
  username                  = var.rds_master_username
  db_name                   = "gitlab"
  password                  = random_password.rds.result
  db_subnet_group_name      = aws_db_subnet_group.gitlab.name
  vpc_security_group_ids    = [aws_security_group.rds.id]
  multi_az                  = false
  publicly_accessible       = false
  storage_encrypted         = true
  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-rds-final-snapshot"
  parameter_group_name      = aws_db_parameter_group.gitlab.name

  lifecycle {
    prevent_destroy = true
  }
}
