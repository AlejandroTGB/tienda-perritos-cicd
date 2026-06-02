#!/bin/bash
set -e

echo "========================================="
echo " Tienda Perritos - Destroy EKS"
echo "========================================="

CREDENTIALS_FILE="credentials.txt"

if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "ERROR: No se encontro $CREDENTIALS_FILE"
  echo "Necesitas las credenciales para borrar los recursos."
  exit 1
fi

# Configurar credenciales (mismo que bootstrap)
AWS_ACCESS_KEY_ID=$(grep aws_access_key_id "$CREDENTIALS_FILE" | cut -d= -f2 | tr -d ' ')
AWS_SECRET_ACCESS_KEY=$(grep aws_secret_access_key "$CREDENTIALS_FILE" | cut -d= -f2 | tr -d ' ')
AWS_SESSION_TOKEN=$(grep aws_session_token "$CREDENTIALS_FILE" | cut -d= -f2 | tr -d ' ')

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN
export AWS_REGION=us-east-1

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"

echo ""
echo "ATENCION: Esto va a borrar TODOS los recursos de AWS."
echo "  - Cluster EKS (tienda-perritos)"
echo "  - Repositorios ECR"
echo "  - Todos los pods, services, ingress"
echo ""
read -p "Estas seguro? (si/no): " CONFIRM

if [ "$CONFIRM" != "si" ]; then
  echo "Cancelado."
  exit 0
fi

# 1. Borrar repos ECR
echo "[1/3] Borrando repositorios ECR..."
aws ecr delete-repository --repository-name tienda-perritos-frontend --force --region us-east-1 || echo "  Repo frontend ya borrado"
aws ecr delete-repository --repository-name tienda-perritos-backend --force --region us-east-1 || echo "  Repo backend ya borrado"
aws ecr delete-repository --repository-name tienda-perritos-db --force --region us-east-1 || echo "  Repo db ya borrado"

echo "  Repositorios ECR borrados."

# 2. Borrar cluster EKS
echo "[2/3] Borrando cluster EKS (esto tarda unos minutos)..."
eksctl delete cluster --name tienda-perritos --region us-east-1

echo "  Cluster borrado."

# 3. Restaurar ECR_REGISTRY en manifiestos
echo "[3/3] Restaurando ECR_REGISTRY en manifiestos..."
find k8s/ -name "*.yaml" -type f -exec sed -i "s|${ECR_REGISTRY}|ECR_REGISTRY|g" {} +

echo "  Manifiestos restaurados."

echo ""
echo "========================================="
echo " Destroy completado!"
echo "========================================="
echo ""
echo "Creditos de AWS preservados."
echo ""