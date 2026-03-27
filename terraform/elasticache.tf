resource "aws_elasticache_subnet_group" "gitlab" {
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_parameter_group" "gitlab" {
  name   = "${var.project_name}-redis-pg"
  family = "redis7"
}

resource "aws_elasticache_replication_group" "gitlab" {
  replication_group_id       = "${var.project_name}-redis"
  description                = "GitLab Redis"
  engine                     = "redis"
  engine_version             = "7.0"
  node_type                  = "cache.t4g.small"
  parameter_group_name       = aws_elasticache_parameter_group.gitlab.name
  subnet_group_name          = aws_elasticache_subnet_group.gitlab.name
  security_group_ids         = [aws_security_group.redis.id]
  num_cache_clusters         = 1
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = random_password.redis.result

  lifecycle {
    prevent_destroy = true
  }
}
