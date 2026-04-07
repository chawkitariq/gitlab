variable "aws_region" {
  type        = string
  description = "AWS region to deploy into"
}

variable "project_name" {
  type        = string
  description = "Name prefix for resources"
  default     = "gitlab"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for all resources"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for ALB"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for EC2, RDS, ElastiCache"
}

variable "route53_zone_name" {
  type        = string
  description = "Route53 hosted zone name (e.g. example.com)"
}

variable "gitlab_version" {
  description = "GitLab CE version to deploy (e.g. \"17.9.1\")"
  type        = string
}

variable "ec2_instance_type" {
  description = "EC2 instance type for GitLab"
  type        = string
  default     = "t3.xlarge"
}

variable "ebs_volume_size" {
  description = "Size in GB of the EC2 root volume"
  type        = number
  default     = 100
}

variable "rds_master_username" {
  description = "Master username for the GitLab RDS instance"
  type        = string
  default     = "gitlab"
}

variable "runner_instance_type" {
  description = "EC2 instance type for the GitLab Runner"
  type        = string
  default     = "t3.medium"
}
