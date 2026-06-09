# EP3 - Innovatech Chile | Orquestación y CI/CD en AWS ECS

## Arquitectura

- **Frontend**: React + Vite → contenedor nginx, puerto 80
- **Backend Despachos**: Spring Boot, puerto 8081
- **Backend Ventas**: Spring Boot, puerto 8080
- **Base de datos**: MySQL en AWS RDS
- **Orquestación**: AWS ECS Fargate
- **CI/CD**: GitHub Actions (build → push ECR → deploy ECS)

## Estructura del repositorio

```
├── Dockerfile.front              # Imagen del frontend
├── Dockerfile.back-despachos     # Imagen backend despachos
├── Dockerfile.back-ventas        # Imagen backend ventas
├── nginx.conf                    # Config nginx para el frontend
├── docker-compose.yml            # Para desarrollo local
├── setup-aws-infra.sh            # Script para crear VPC/SG/ALB
├── .github/
│   └── workflows/
│       └── cicd.yml              # Pipeline CI/CD
├── front_despacho/               # Código fuente frontend
├── back-Despachos_SpringBoot/    # Código fuente backend despachos
└── back-Ventas_SpringBoot/       # Código fuente backend ventas
```

## Cómo ejecutar localmente

```bash
docker-compose up --build
```

La app queda disponible en http://localhost

## Cómo desplegar en AWS

### 1. Crear la infraestructura

```bash
chmod +x setup-aws-infra.sh
./setup-aws-infra.sh
```

Guarda el archivo `infra-output.env` que genera el script.

### 2. Crear repositorios ECR

```bash
aws ecr create-repository --repository-name innovatech-frontend --region us-east-1
aws ecr create-repository --repository-name innovatech-back-despachos --region us-east-1
aws ecr create-repository --repository-name innovatech-back-ventas --region us-east-1
```

### 3. Configurar GitHub Secrets

En GitHub → Settings → Secrets and variables → Actions, agregar:

| Secret | Descripción |
|---|---|
| `AWS_ACCESS_KEY_ID` | Credencial del laboratorio AWS |
| `AWS_SECRET_ACCESS_KEY` | Credencial del laboratorio AWS |
| `AWS_SESSION_TOKEN` | Token de sesión del laboratorio |
| `AWS_ACCOUNT_ID` | ID de tu cuenta AWS (12 dígitos) |
| `ALB_DNS` | DNS del ALB (del infra-output.env) |

### 4. Crear el cluster ECS y servicios

Crear el cluster:
```bash
aws ecs create-cluster --cluster-name innovatech-cluster --region us-east-1
```

Las Task Definitions y Services se crean desde la consola AWS ECS usando los valores del `infra-output.env`.

### 5. Desplegar

Hacer push a `main` activa automáticamente el pipeline.

## Variables de entorno en ECS (Task Definition)

Los backends requieren estas variables configuradas en la Task Definition:

| Variable | Descripción |
|---|---|
| `DB_ENDPOINT` | Endpoint de RDS MySQL |
| `DB_PORT` | 3306 |
| `DB_NAME` | Nombre de la base de datos |
| `DB_USERNAME` | Usuario MySQL |
| `DB_PASSWORD` | Contraseña MySQL (usar Secrets Manager o SSM) |

## Pipeline CI/CD

El pipeline corre automáticamente al hacer push a `main`:

1. **Build**: Compila las 3 imágenes Docker
2. **Push**: Sube las imágenes a ECR con tag del commit SHA
3. **Deploy**: Actualiza los 3 servicios ECS con las nuevas imágenes

Los PRs solo ejecutan el build (sin deploy).
