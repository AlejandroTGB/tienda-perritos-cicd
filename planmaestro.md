# Plan Maestro - Tienda Perritos: Migracion a EKS

## Estado Actual

- [x] Limpieza del proyecto (credenciales, IPs, .dockerignore, .gitignore)
- [ ] Escribir cluster.yaml (configuracion de eksctl)
- [ ] Escribir manifiestos Kubernetes (k8s/)
- [ ] Escribir bootstrap.sh y destroy.sh
- [ ] Actualizar pipelines de GitHub Actions
- [ ] Instalar herramientas locales (aws cli, eksctl, kubectl, gh)
- [ ] Probar en AWS Academy Lab
- [ ] Probar CI/CD con un push

---

## 1. cluster.yaml - Crear la infraestructura en AWS

Archivo: `infrastructure/cluster.yaml`

Esto le dice a eksctl que cree un cluster EKS con 3 worker nodes.

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: tienda-perritos
  region: us-east-1

managedNodeGroups:
  - name: workers
    instanceType: t3.small
    desiredCapacity: 3
    minSize: 1
    maxSize: 3
```

### Que crea eksctl con este archivo

| Recurso | Descripcion |
|---------|-------------|
| VPC | Red privada virtual con subnets |
| Subnets | 2 publicas, 2 privadas |
| Security Groups | Reglas de firewall para el cluster |
| EKS Cluster | El control plane de Kubernetes |
| 3 EC2 (node group) | Las maquinas donde corren los pods |
| IAM Roles | Permisos para que los nodos funcionen |

### Comando para crear

```bash
eksctl create cluster -f infrastructure/cluster.yaml
```

### Comando para borrar

```bash
eksctl delete cluster --name tienda-perritos --region us-east-1
```

---

## 2. Manifiestos Kubernetes (k8s/)

Los manifiestos le dicen a Kubernetes COMO correr cada componente.
Tu codigo ya esta en las imagenes Docker (en ECR), los manifiestos dicen "corre esta imagen de esta forma".

### Estructura de carpetas

```
k8s/
├── frontend/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── backend/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
├── db/
│   ├── statefulset.yaml
│   ├── service.yaml
│   ├── secret.yaml
│   └── persistent-volume.yaml
```

### 2.1 k8s/frontend/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: ECR_REGISTRY/tienda-perritos-frontend:latest
        ports:
        - containerPort: 80
        env:
        - name: BACKEND_HOST
          value: "backend-service"
```

NOTA: `ECR_REGISTRY` se reemplaza por la URL real de tu ECR.
NOTA: `BACKEND_HOST=backend-service` es el nombre del Service del backend dentro de Kubernetes.

### 2.2 k8s/frontend/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

### 2.3 k8s/frontend/ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tienda-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend-service
            port:
              number: 3001
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
```

NOTA: Se necesita un Ingress Controller (nginx) instalado en el cluster.

### 2.4 k8s/backend/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  labels:
    app: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: ECR_REGISTRY/tienda-perritos-backend:latest
        ports:
        - containerPort: 3001
        envFrom:
        - configMapRef:
            name: backend-config
        - secretRef:
            name: db-credentials
```

### 2.5 k8s/backend/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  selector:
    app: backend
  ports:
  - port: 3001
    targetPort: 3001
  type: ClusterIP
```

### 2.6 k8s/backend/configmap.yaml

ConfigMap = variables de entorno NO sensibles.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
data:
  DB_NAME: "tienda_perritos"
  DB_PORT: "3306"
  DB_HOST: "db-service"
```

NOTA: `DB_HOST=db-service` es el nombre del Service de la DB dentro de Kubernetes. No es una IP.

### 2.7 k8s/db/statefulset.yaml

StatefulSet (no Deployment) porque la base de datos tiene estado (datos persistentes).

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
  labels:
    app: db
spec:
  serviceName: db
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: db
        image: ECR_REGISTRY/tienda-perritos-db:latest
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: MYSQL_ROOT_PASSWORD
        - name: MYSQL_DATABASE
          value: "tienda_perritos"
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: MYSQL_USER
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: MYSQL_PASSWORD
        volumeMounts:
        - name: db-data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:
  - metadata:
      name: db-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 5Gi
```

NOTA: `volumeClaimTemplates` crea almacenamiento persistente para que la DB no pierda datos si el pod se reinicia.

### 2.8 k8s/db/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db-service
spec:
  selector:
    app: db
  ports:
  - port: 3306
    targetPort: 3306
  type: ClusterIP
```

### 2.9 k8s/db/secret.yaml

Secret = variables de entorno sensibles (contrasenas).

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
stringData:
  MYSQL_ROOT_PASSWORD: "changeme_root"
  MYSQL_USER: "tienda_user"
  MYSQL_PASSWORD: "changeme_pass"
  DB_USER: "tienda_user"
  DB_PASSWORD: "changeme_pass"
```

NOTA: Estas contrasenas son placeholders. En produccion se usan secrets de AWS o Sealed Secrets.
Para el lab universitario, esto alcanza. Las contrasenas reales se cambian antes de deployar.

### 2.10 k8s/db/persistent-volume.yaml

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-data
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

NOTA: Esto ya esta incluido en el StatefulSet como volumeClaimTemplates. Se lista aca como referencia, pero NO se aplica por separado si se usa volumeClaimTemplates dentro del StatefulSet.

---

## 3. bootstrap.sh - Crear todo desde cero tras un reset

Archivo: `infrastructure/bootstrap.sh`

```bash
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
```

### credentials.txt (NO va a git)

```ini
[default]
aws_access_key_id=PEGAR_AQUI
aws_secret_access_key=PEGAR_AQUI
aws_session_token=PEGAR_AQUI
```

### .gitignore - Agregar credentials.txt

```
# Ya existe .env en .gitignore, pero agregar explicitamente:
credentials.txt
```

---

## 4. destroy.sh - Borrar todo para no gastar creditos

Archivo: `infrastructure/destroy.sh`

```bash
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
```

---

## 5. Pipelines de GitHub Actions (actualizados)

Los workflows cambian de SSM a kubectl.

### .github/workflows/cicd-tienda-frontend.yml

```yaml
name: CI/CD Tienda Perritos - Frontend

on:
  push:
    branches: ["main"]
    paths:
      - "frontend/**"

jobs:
  build-push-deploy-frontend:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout codigo
        uses: actions/checkout@v3

      - name: Configurar credenciales AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login en Amazon ECR
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build imagen Frontend y push a ECR
        run: |
          cd frontend
          docker build -t tienda-frontend .
          docker tag tienda-frontend:latest ${{ secrets.ECR_REPO_URL_FRONTEND }}:latest
          docker push ${{ secrets.ECR_REPO_URL_FRONTEND }}:latest

      - name: Deploy a EKS via kubectl
        run: |
          aws eks update-kubeconfig --name tienda-perritos --region ${{ secrets.AWS_REGION }}
          kubectl rollout restart deployment/frontend
          kubectl rollout status deployment/frontend --timeout=120s
```

### .github/workflows/cicd-tienda-backend.yml

```yaml
name: CI/CD Tienda Perritos - Backend

on:
  push:
    branches: ["main"]
    paths:
      - "backend/**"

jobs:
  build-push-deploy-backend:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout codigo
        uses: actions/checkout@v3

      - name: Configurar credenciales AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login en Amazon ECR
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build imagen Backend y push a ECR
        run: |
          cd backend
          docker build -t tienda-backend .
          docker tag tienda-backend:latest ${{ secrets.ECR_REPO_URL_BACKEND }}:latest
          docker push ${{ secrets.ECR_REPO_URL_BACKEND }}:latest

      - name: Deploy a EKS via kubectl
        run: |
          aws eks update-kubeconfig --name tienda-perritos --region ${{ secrets.AWS_REGION }}
          kubectl rollout restart deployment/backend
          kubectl rollout status deployment/backend --timeout=120s
```

### .github/workflows/cicd-tienda-db.yml

```yaml
name: CI/CD Tienda Perritos - DB

on:
  push:
    branches: ["main"]
    paths:
      - "db/**"

jobs:
  build-push-deploy-db:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout codigo
        uses: actions/checkout@v3

      - name: Configurar credenciales AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login en Amazon ECR
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build imagen DB y push a ECR
        run: |
          cd db
          docker build -t tienda-db .
          docker tag tienda-db:latest ${{ secrets.ECR_REPO_URL_DB }}:latest
          docker push ${{ secrets.ECR_REPO_URL_DB }}:latest

      - name: Deploy a EKS via kubectl
        run: |
          aws eks update-kubeconfig --name tienda-perritos --region ${{ secrets.AWS_REGION }}
          kubectl rollout restart statefulset/db
          kubectl rollout status statefulset/db --timeout=180s
```

NOTA: El deploy de DB es diferente. Se usa `kubectl rollout restart statefulset/db` en vez de `deployment`.

---

## 6. Herramientas requeridas (instalar en tu computadora)

| Herramienta | Para que | Instalacion |
|-------------|----------|-------------|
| AWS CLI v2 | Configurar credenciales y ECR | `https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html` |
| eksctl | Crear cluster EKS | `https://eksctl.io/installation/` |
| kubectl | Aplicar manifiestos y manejar el cluster | `https://kubernetes.io/docs/tasks/tools/` |
| gh (GitHub CLI) | Actualizar secrets de GitHub | `https://cli.github.com/` |
| Docker | Build de imagenes | `https://docs.docker.com/get-docker/` |

### Verificar instalacion

```bash
aws --version
eksctl version
kubectl version --client
gh --version
docker --version
```

---

## 7. Flujo de trabajo diario

### Arrancar el lab (cada vez que se resetea)

```bash
# 1. Abrir AWS Academy Learner Lab
# 2. Click "AWS Details" > "AWS CLI"
# 3. Copiar las 3 credenciales
# 4. Pegar en credentials.txt

# 5. Dar permisos de ejecucion (solo la primera vez)
chmod +x infrastructure/bootstrap.sh

# 6. Correr bootstrap
cd infrastructure
./bootstrap.sh
```

### Trabajar normalmente

```bash
# Hacer cambios, commits, pushes
git add .
git commit -m "feat: nuevo cambio"
git push

# GitHub Actions se dispara automaticamente
# Build > Push ECR > kubectl rollout restart
```

### Terminar el dia (para no gastar creditos)

```bash
# Dar permisos de ejecucion (solo la primera vez)
chmod +x infrastructure/destroy.sh

# Correr destroy
cd infrastructure
./destroy.sh
```

---

## 8. Orden de implementacion

1. Escribir `infrastructure/cluster.yaml`
2. Escribir los 10 manifiestos K8s (k8s/)
3. Escribir `infrastructure/bootstrap.sh`
4. Escribir `infrastructure/destroy.sh`
5. Agregar `credentials.txt` al `.gitignore`
6. Actualizar los 3 workflows de GitHub Actions
7. Instalar las herramientas locales
8. Probar en AWS Academy Lab (bootstrap.sh > verificar > destroy.sh)
9. Probar CI/CD con un push

---

## 9. Estructura final del proyecto

```
tienda-perritos-cicd/
├── .github/
│   └── workflows/
│       ├── cicd-tienda-frontend.yml
│       ├── cicd-tienda-backend.yml
│       └── cicd-tienda-db.yml
├── backend/
│   ├── .dockerignore
│   ├── Dockerfile
│   ├── package.json
│   └── server.js
├── db/
│   ├── .dockerignore
│   ├── Dockerfile
│   └── init.sql
├── frontend/
│   ├── .dockerignore
│   ├── Dockerfile
│   ├── app.js
│   ├── default.conf.template
│   └── index.html
├── infrastructure/
│   ├── bootstrap.sh
│   ├── cluster.yaml
│   └── destroy.sh
├── k8s/
│   ├── backend/
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── db/
│   │   ├── persistent-volume.yaml
│   │   ├── secret.yaml
│   │   ├── service.yaml
│   │   └── statefulset.yaml
│   └── frontend/
│       ├── deployment.yaml
│       ├── ingress.yaml
│       └── service.yaml
├── .gitignore
├── README.md
└── credentials.txt          # NO VA A GIT
```

---

## 10. Comandos utiles para debugging

```bash
# Ver pods
kubectl get pods

# Ver logs de un pod
kubectl logs <pod-name>

# Ver servicios
kubectl get services

# Ver ingress
kubectl get ingress

# Describir un pod con problemas
kubectl describe pod <pod-name>

# Ver eventos del cluster
kubectl get events --sort-by='.lastTimestamp'

# Port-forward para probar localmente
kubectl port-forward service/frontend-service 8080:80

# Escalar replicas
kubectl scale deployment backend --replicas=3
```