#!/bin/bash
set -euo pipefail

# Install AWS CLI v2 via snap (snapd is already running - SSM agent uses it)
snap install aws-cli --classic
export PATH="$PATH:/snap/bin"

# Récupérer les secrets depuis Secrets Manager
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --region ${aws_region} \
  --secret-id ${rds_secret_arn} \
  --query SecretString \
  --output text)

REDIS_PASSWORD=$(aws secretsmanager get-secret-value \
  --region ${aws_region} \
  --secret-id ${redis_secret_arn} \
  --query SecretString \
  --output text)

SMTP_PASSWORD=$(aws secretsmanager get-secret-value \
  --region ${aws_region} \
  --secret-id ${smtp_secret_arn} \
  --query SecretString \
  --output text)

# Écrire /etc/gitlab/gitlab.rb
cat > /etc/gitlab/gitlab.rb <<EOF
external_url 'https://${external_url}'
letsencrypt['enable'] = false
nginx['listen_port'] = 80
nginx['listen_https'] = false
nginx['real_ip_trusted_addresses'] = ['${vpc_cidr}']
nginx['real_ip_header'] = 'X-Forwarded-For'
nginx['real_ip_recursive'] = 'on'
gitlab_rails['trusted_proxies'] = ['${vpc_cidr}']
gitlab_rails['gitlab_ssh_host'] = '${ssh_host}'
gitlab_rails['gitlab_shell_ssh_port'] = 22
gitlab_rails['time_zone'] = 'UTC'

postgresql['enable'] = false
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'utf8'
gitlab_rails['db_host'] = '${db_host}'
gitlab_rails['db_port'] = ${db_port}
gitlab_rails['db_database'] = '${db_name}'
gitlab_rails['db_username'] = '${db_username}'
gitlab_rails['db_password'] = '$${DB_PASSWORD}'

redis['enable'] = false
gitlab_rails['redis_host'] = '${redis_host}'
gitlab_rails['redis_port'] = 6379
gitlab_rails['redis_password'] = '$${REDIS_PASSWORD}'
gitlab_rails['redis_ssl'] = true

gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8', '${vpc_cidr}']

gitlab_rails['object_store'] = {
  'enabled' => true,
  'connection' => {
    'provider' => 'AWS',
    'region' => '${aws_region}',
    'use_iam_profile' => true
  },
  'objects' => {
    'artifacts'        => { 'bucket' => '${s3_bucket}' },
    'uploads'          => { 'bucket' => '${s3_bucket}' },
    'lfs'              => { 'bucket' => '${s3_bucket}' },
    'packages'         => { 'bucket' => '${s3_bucket}' },
    'terraform_state'  => { 'bucket' => '${s3_bucket}' },
    'ci_secure_files'  => { 'bucket' => '${s3_bucket}' },
    'pages'            => { 'bucket' => '${s3_bucket}' },
    'dependency_proxy' => { 'bucket' => '${s3_bucket}' }
  }
}

gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = '${smtp_address}'
gitlab_rails['smtp_port'] = ${smtp_port}
gitlab_rails['smtp_user_name'] = '${smtp_user_name}'
gitlab_rails['smtp_password'] = '$${SMTP_PASSWORD}'
gitlab_rails['smtp_authentication'] = 'login'
gitlab_rails['smtp_enable_starttls_auto'] = true
gitlab_rails['gitlab_email_from'] = '${smtp_from_address}'
EOF

# Configurer GitLab
gitlab-ctl reconfigure
