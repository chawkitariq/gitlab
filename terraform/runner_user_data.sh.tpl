#!/bin/bash
set -euo pipefail

# Install AWS CLI v2
snap install aws-cli --classic
export PATH="$PATH:/snap/bin"

# Install Docker
apt-get update -y
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

# Install gitlab-runner
curl -fsSL https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash
apt-get install -y gitlab-runner

# Add gitlab-runner user to docker group so it can run Docker jobs
usermod -aG docker gitlab-runner

# Attendre que GitLab soit opérationnel
echo "Waiting for GitLab to be ready..."
until curl -sf "https://${gitlab_url}/-/readiness" > /dev/null 2>&1; do
  sleep 30
done
echo "GitLab is ready."

# Récupérer le PAT admin depuis Secrets Manager
ADMIN_PAT=$(aws secretsmanager get-secret-value \
  --region ${aws_region} \
  --secret-id ${admin_pat_secret_arn} \
  --query SecretString \
  --output text)

# Vérifier si un runner token existe déjà (reprovision idempotent)
EXISTING_TOKEN=$(aws secretsmanager get-secret-value \
  --region ${aws_region} \
  --secret-id ${runner_token_secret_arn} \
  --query SecretString \
  --output text 2>/dev/null || true)

if [ -z "$EXISTING_TOKEN" ]; then
  # Créer un nouveau runner via l'API GitLab
  RUNNER_TOKEN=$(curl -sf --request POST \
    "https://${gitlab_url}/api/v4/user/runners" \
    --header "PRIVATE-TOKEN: $ADMIN_PAT" \
    --form "runner_type=instance_type" \
    --form "description=${runner_description}" \
    --form "tag_list=${runner_tag_list}" \
    --form "run_untagged=true" \
    | jq -r '.token')

  # Stocker le token pour les reprovisionnements futurs
  aws secretsmanager put-secret-value \
    --region ${aws_region} \
    --secret-id ${runner_token_secret_arn} \
    --secret-string "$RUNNER_TOKEN"
else
  RUNNER_TOKEN="$EXISTING_TOKEN"
fi

# Enregistrer le runner
gitlab-runner register \
  --non-interactive \
  --url "https://${gitlab_url}" \
  --token "$RUNNER_TOKEN" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --description "${runner_description}"

# Démarrer le runner
systemctl enable gitlab-runner
systemctl start gitlab-runner
