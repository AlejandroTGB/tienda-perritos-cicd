# Tienda Perritos - Pipeline CI/CD con GitHub Actions

Aplicacion web CRUD para gestion de productos de una tienda de alimentos para perritos, desplegada en AWS con pipeline de Integracion y Entrega Continua.

## Arquitectura

```
GitHub Repository
        |
        v
GitHub Actions (CI/CD)
        |
        v
Amazon ECR (imagenes Docker)
        |
        v
AWS EC2 (instancias de despliegue)
   +---> EC2 Frontend (Nginx:80)
   +---> EC2 Backend  (Node.js:3001)
   +---> EC2 Database (MySQL:3306)
```

## Stack Tecnologico

| Capa | Tecnologia | Puerto |
|------|-----------|--------|
| Frontend | HTML5, JavaScript, Nginx | 80 |
| Backend | Node.js, Express.js | 3001 |
| Base de Datos | MySQL 8.0 | 3306 |
| Containerizacion | Docker | - |
| CI/CD | GitHub Actions | - |
| Registro | Amazon ECR | - |
| Despliegue | AWS EC2 + SSM | - |

## Estructura del Proyecto

```
tienda-perritos-cicd/
├── .github/
│   └── workflows/
│       ├── cicd-tienda-frontend.yml
│       ├── cicd-tienda-backend.yml
│       └── cicd-tienda-db.yml
├── frontend/
│   ├── Dockerfile
│   ├── index.html
│   ├── app.js
│   └── default.conf
├── backend/
│   ├── Dockerfile
│   ├── server.js
│   └── package.json
├── db/
│   ├── Dockerfile
│   └── init.sql
└── .gitignore
```

## API Endpoints

| Metodo | Endpoint | Descripcion |
|--------|----------|-------------|
| GET | /api/productos | Obtener todos los productos |
| GET | /api/productos/:id | Obtener un producto por ID |
| POST | /api/productos | Crear un nuevo producto |
| PUT | /api/productos/:id | Actualizar un producto |
| DELETE | /api/productos/:id | Eliminar un producto |
| GET | /api/health | Health check del backend |

## Pipeline CI/CD

Cada componente tiene su propio workflow que se dispara al hacer push en `main` cuando se modifican los archivos correspondientes:

| Workflow | Trigger | Que hace |
|----------|---------|----------|
| Frontend | Push en `frontend/**` | Build -> Push a ECR -> Deploy via SSM |
| Backend | Push en `backend/**` | Build -> Push a ECR -> Deploy via SSM |
| DB | Push en `db/**` | Build -> Push a ECR -> Deploy via SSM |

Flujo de cada pipeline:

1. Checkout del codigo
2. Configuracion de credenciales AWS
3. Login en Amazon ECR
4. Build de la imagen Docker
5. Tag y push al repositorio ECR
6. Deploy a EC2 via AWS Systems Manager (SSM)

## Infraestructura en AWS

### Instancias EC2

| Instancia | Servicio | Puerto | Security Group |
|-----------|---------|--------|----------------|
| tienda-frontend | Nginx | 80 | tienda-frontend-sg |
| tienda-backend | Express.js | 3001 | tienda-backend-sg |
| tienda-db | MySQL | 3306 | tienda-db-sg |

### Repositorios ECR

| Repositorio | Contiene |
|-------------|----------|
| tienda-perritos-frontend | Imagen Docker del frontend |
| tienda-perritos-backend | Imagen Docker del backend |
| tienda-perritos-db | Imagen Docker de la base de datos |

### Security Groups

| SG | Inbound |
|----|---------|
| tienda-frontend-sg | 22 (SSH), 80 (HTTP) |
| tienda-backend-sg | 22 (SSH), 3001 (API) |
| tienda-db-sg | 22 (SSH), 3306 (MySQL) |

## Requisitos Previos

- Cuenta AWS con instancias EC2 y repositorios ECR creados
- Docker instalado en cada instancia EC2
- AWS Systems Manager Agent habilitado en las instancias
- Cuenta de GitHub
- 12 secrets configurados en el repositorio

## Despliegue Manual (alternativa)

Si se necesita desplegar manualmente en una instancia EC2:

```bash
# Login a ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 583164901451.dkr.ecr.us-east-1.amazonaws.com

# Pull y run del contenedor deseado
docker pull 583164901451.dkr.ecr.us-east-1.amazonaws.com/tienda-perritos-frontend:latest
docker run -d --name tienda-frontend -p 80:80 583164901451.dkr.ecr.us-east-1.amazonaws.com/tienda-perritos-frontend:latest
```

## Verificacion

```bash
# Health check del backend
curl http://<IP_BACKEND>:3001/api/health

# Obtener productos
curl http://<IP_BACKEND>:3001/api/productos

# Ver contenedores corriendo
docker ps
```

## Autores

Alejandro TGB