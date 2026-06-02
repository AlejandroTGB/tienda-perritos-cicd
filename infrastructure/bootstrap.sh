#!/bin/bash
set -e

echo "========================================="
echo " Tienda Perritos - Bootstrap EKS"
echo "========================================="

# -------------------------------------------------
# 1. Leer credenciales del archivo credentials.txt
# -------------------------------------------------
CREDENTIALS_FILE="credentials.txt"

if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "ERROR: No se encontro $CREDENTIALS_FILE"
  echo "Crealo con las credenciales de AWS Academy (AWS Details > AWS CLI)"
  echo "Formato:"
  echo '[default]'
  echo 'aws_access_key_id=ASIAXXXXX'
  echo 'aws_secret_access_key=XXXXXXX'
  echo 'aws_session_token=XXXXXXX'
  exit 1
fi

echo "[1/6] Configurando credenciales AWS..."

# Extraer credenciales del archivo
AWS_ACCESS_KEY_ID=$(grep aws_access_key_id "$CREDENTIALS_FILE" | cut -d= -f2 | tr -d ' ')
AWS_SECRET_ACCESS_KEY=$(grep aws_secret_access_key "$CREDENTIALS_FILE" | cut -d= -f2 | tr -d ' ')
AWS_SESSION_TOKEN=$(grep aws_session_token "$CREDENTIALS_FILE" | cut -d= -f2 | tr -d ' ')

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN
export AWS_REGION=us-east-1

# Configurar AWS CLI
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
aws_session_token = $AWS_SESSION
EOF

cat > ~/.aws/config << EOF
[default]
region = us-east-1
EOF

echo "  Credenciales configuradas."

# -------------------------------------------------
# 2. Crear cluster EKS
# -------------------------------------------------
echo "[2/6] Creando cluster EKS (esto tarda 10-15 minutos)..."
eksctl create cluster -f infrastructure/cluster.yaml

echo "  Cluster creado."

# -------------------------------------------------
# 3. Crear repos ECR
# -------------------------------------------------
echo "[3/6] Creando repositorios ECR..."

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"

aws ecr create-repository --repository-name tienda-perritos-frontend --region us-east-1 || echo "  Repo frontend ya existe"
aws ecr create-repository --repository-name tienda-perritos-backend --region us-east-1 || echo "  Repo backend ya existe"
aws ecr create-repository --repository-name tienda-perritos-db --region us-east-1 || echo "  Repo db ya existe"

echo "  Repositorios ECR creados."

# -------------------------------------------------
# 4. Actualizar ECR_REGISTRY en los manifiestos
# -------------------------------------------------
echo "[4/6] Actualizando ECR_REGISTRY en manifiestos..."

# Reemplazar ECR_REGISTRY en todos los yaml
find k8s/ -name "*.yaml" -type f -exec sed -i "s|ECR_REGISTRY|${ECR_REGISTRY}|g" {} +

echo "  Manifiestos actualizados con: $ECR_REGISTRY"

# -------------------------------------------------
# 5. Aplicar manifiestos Kubernetes
# -------------------------------------------------
echo "[5/6] Aplicando manifiestos Kubernetes..."

# Primero los secrets y configmaps
kubectl apply -f k8s/db/secret.yaml
kubectl apply -f k8s/backend/configmap.yaml

# Despues la base de datos (necesita arrancar primero)
kubectl apply -f k8s/db/service.yaml
kubectl apply -f k8s/db/statefulset.yaml

# Esperar a que la DB este lista
echo "  Esperando a que la base de datos este lista..."
kubectl wait --for=condition=ready pod -l app=db --timeout=120s

# Despues el backend
kubectl apply -f k8s/backend/service.yaml
kubectl apply -f k8s/backend/deployment.yaml

# Despues el frontend
kubectl apply -f k8s/frontend/service.yaml
kubectl apply -f k8s/frontend/deployment.yaml

# Instalar Ingress Controller (nginx)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/aws/deploy.yaml

echo "  Esperando a que el Ingress Controller este listo..."
kubectl wait --namespace ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=120s

# Aplicar Ingress
kubectl apply -f k8s/frontend/ingress.yaml

echo "  Manifiestos aplicados."

# -------------------------------------------------
# 6. Actualizar GitHub Secrets
# -------------------------------------------------
echo "[6/6] Actualizando GitHub Secrets..."

gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID"
gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY"
gh secret set AWS_SESSION_TOKEN --body "$AWS_SESSION_TOKEN"
gh secret set AWS_REGION --body "us-east-1"
gh secret set ECR_REGISTRY --body "$ECR_REGISTRY"
gh secret set ECR_REPO_URL_FRONTEND --body "${ECR_REGISTRY}/tienda-perritos-frontend"
gh secret set ECR_REPO_URL_BACKEND --body "${ECR_REGISTRY}/tienda-perritos-backend"
gh secret set ECR_REPO_URL_DB --body "${ECR_REGISTRY}/tienda-perritos-db"

echo "  GitHub Secrets actualizados."

# -------------------------------------------------
# Listo!
# -------------------------------------------------
echo ""
echo "========================================="
echo " Bootstrap completado!"
echo "========================================="
echo ""
echo "Para ver el estado de los pods:"
echo "  kubectl get pods"
echo ""
echo "Para obtener la URL del Ingress:"
echo "  kubectl get ingress"
echo ""
echo "Para ver los servicios:"
echo "  kubectl get services"
echo ""