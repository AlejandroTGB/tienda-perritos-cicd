#!/bin/bash
set -e

REGION="us-east-1"
CREDENTIALS_FILE="credentials.txt"

if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "ERROR: No se encontro $CREDENTIALS_FILE"
  echo "Crealo con las credenciales de AWS Academy (AWS Details > AWS CLI)"
  exit 1
fi

# Lee las creds frescas
AWS_ACCESS_KEY_ID=$(grep aws_access_key_id "$CREDENTIALS_FILE" | cut -d= -f2 | tr -d ' ')
AWS_SECRET_ACCESS_KEY=$(grep aws_secret_access_key "$CREDENTIALS_FILE" | cut -d= -f2 | tr -d ' ')
AWS_SESSION_TOKEN=$(grep aws_session_token "$CREDENTIALS_FILE" | cut -d= -f2 | tr -d ' ')

# Sube las 4 secrets de AWS a GitHub
gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID"
gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY"
gh secret set AWS_SESSION_TOKEN --body "$AWS_SESSION_TOKEN"
gh secret set AWS_REGION --body "$REGION"

# Descubre Account ID y arma URLs de ECR del profe
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION=$REGION
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

gh secret set ECR_REPO_URL_FRONTEND --body "${ECR_REGISTRY}/tienda-frontend"
gh secret set ECR_REPO_URL_BACKEND --body "${ECR_REGISTRY}/tienda-backend"
gh secret set ECR_REPO_URL_DB --body "${ECR_REGISTRY}/tienda-db"

echo ""
echo "Done. 7 secrets actualizadas en GitHub."