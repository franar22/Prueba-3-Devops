#!/bin/bash
# ============================================================
# setup-aws-infra.sh
# Crea VPC, subredes, internet gateway, security groups y ALB
# para el proyecto EP3 - Innovatech Chile
#
# USO:
#   chmod +x setup-aws-infra.sh
#   ./setup-aws-infra.sh
#
# REQUISITOS:
#   - AWS CLI instalado y configurado (aws configure)
#   - Credenciales del laboratorio AWS Academy activas
# ============================================================

set -e  # Detener si hay cualquier error

# ─── CONFIGURACIÓN ────────────────────────────────────────────────────────────
REGION="us-east-1"
PROJECT="innovatech"
# ──────────────────────────────────────────────────────────────────────────────

echo "================================================"
echo " EP3 - Innovatech: Creando infraestructura AWS"
echo " Región: $REGION"
echo "================================================"

# ─── 1. VPC ───────────────────────────────────────────────────────────────────
echo ""
echo "[1/8] Creando VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region $REGION \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$PROJECT-vpc},{Key=Project,Value=$PROJECT}]" \
  --query 'Vpc.VpcId' \
  --output text)

# Habilitar DNS hostnames (necesario para ECS y RDS)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support

echo "  VPC creada: $VPC_ID"

# ─── 2. INTERNET GATEWAY ──────────────────────────────────────────────────────
echo ""
echo "[2/8] Creando Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$PROJECT-igw}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
echo "  Internet Gateway: $IGW_ID"

# ─── 3. SUBREDES PÚBLICAS (2 AZs para alta disponibilidad) ───────────────────
echo ""
echo "[3/8] Creando subredes públicas en 2 zonas de disponibilidad..."

SUBNET_PUB_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${REGION}a \
  --region $REGION \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT-subnet-pub-1a}]" \
  --query 'Subnet.SubnetId' \
  --output text)

SUBNET_PUB_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ${REGION}b \
  --region $REGION \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT-subnet-pub-1b}]" \
  --query 'Subnet.SubnetId' \
  --output text)

# Habilitar IP pública automática en subredes públicas
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB_1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB_2 --map-public-ip-on-launch

echo "  Subred pública 1 (us-east-1a): $SUBNET_PUB_1"
echo "  Subred pública 2 (us-east-1b): $SUBNET_PUB_2"

# ─── 4. ROUTE TABLE ───────────────────────────────────────────────────────────
echo ""
echo "[4/8] Configurando tabla de rutas..."
RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$PROJECT-rt-public}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)

# Ruta por defecto hacia internet
aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

# Asociar subredes a la route table
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_PUB_1
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_PUB_2
echo "  Route table configurada: $RT_ID"

# ─── 5. SECURITY GROUP: ALB (acepta tráfico HTTP/HTTPS desde internet) ────────
echo ""
echo "[5/8] Creando Security Group para el ALB..."
SG_ALB=$(aws ec2 create-security-group \
  --group-name "$PROJECT-sg-alb" \
  --description "SG para Application Load Balancer - $PROJECT" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$PROJECT-sg-alb}]" \
  --query 'GroupId' \
  --output text)

# HTTP desde cualquier IP
aws ec2 authorize-security-group-ingress --group-id $SG_ALB \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
# HTTPS desde cualquier IP
aws ec2 authorize-security-group-ingress --group-id $SG_ALB \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

echo "  SG ALB: $SG_ALB"

# ─── 6. SECURITY GROUP: ECS Tasks (acepta tráfico solo desde el ALB) ──────────
echo ""
echo "[6/8] Creando Security Group para los contenedores ECS..."
SG_ECS=$(aws ec2 create-security-group \
  --group-name "$PROJECT-sg-ecs" \
  --description "SG para tareas ECS Fargate - $PROJECT" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$PROJECT-sg-ecs}]" \
  --query 'GroupId' \
  --output text)

# Frontend (puerto 80) solo desde el ALB
aws ec2 authorize-security-group-ingress --group-id $SG_ECS \
  --protocol tcp --port 80 --source-group $SG_ALB
# Backend Ventas (8080) solo desde el ALB y otros contenedores ECS
aws ec2 authorize-security-group-ingress --group-id $SG_ECS \
  --protocol tcp --port 8080 --source-group $SG_ALB
# Backend Despachos (8081) solo desde el ALB y otros contenedores ECS
aws ec2 authorize-security-group-ingress --group-id $SG_ECS \
  --protocol tcp --port 8081 --source-group $SG_ALB
# Comunicación interna entre contenedores ECS
aws ec2 authorize-security-group-ingress --group-id $SG_ECS \
  --protocol tcp --port 0-65535 --source-group $SG_ECS

echo "  SG ECS: $SG_ECS"

# ─── 7. SECURITY GROUP: RDS MySQL ─────────────────────────────────────────────
echo ""
echo "[7/8] Creando Security Group para RDS MySQL..."
SG_RDS=$(aws ec2 create-security-group \
  --group-name "$PROJECT-sg-rds" \
  --description "SG para RDS MySQL - $PROJECT" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$PROJECT-sg-rds}]" \
  --query 'GroupId' \
  --output text)

# MySQL (3306) solo desde los contenedores ECS
aws ec2 authorize-security-group-ingress --group-id $SG_RDS \
  --protocol tcp --port 3306 --source-group $SG_ECS

echo "  SG RDS: $SG_RDS"

# ─── 8. APPLICATION LOAD BALANCER ─────────────────────────────────────────────
echo ""
echo "[8/8] Creando Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "$PROJECT-alb" \
  --subnets $SUBNET_PUB_1 $SUBNET_PUB_2 \
  --security-groups $SG_ALB \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --region $REGION \
  --tags Key=Name,Value=$PROJECT-alb Key=Project,Value=$PROJECT \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "  ALB creado: $ALB_DNS"

# Target Group para el Frontend
TG_FRONT_ARN=$(aws elbv2 create-target-group \
  --name "$PROJECT-tg-frontend" \
  --protocol HTTP \
  --port 80 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path "/" \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --region $REGION \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Target Group para Backend Despachos
TG_DESPACHOS_ARN=$(aws elbv2 create-target-group \
  --name "$PROJECT-tg-despachos" \
  --protocol HTTP \
  --port 8081 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path "/actuator/health" \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --region $REGION \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Target Group para Backend Ventas
TG_VENTAS_ARN=$(aws elbv2 create-target-group \
  --name "$PROJECT-tg-ventas" \
  --protocol HTTP \
  --port 8080 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path "/actuator/health" \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --region $REGION \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Listener HTTP en puerto 80 → Frontend por defecto
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_FRONT_ARN \
  --region $REGION > /dev/null

echo ""
echo "============================================================"
echo " ✅ INFRAESTRUCTURA CREADA EXITOSAMENTE"
echo "============================================================"
echo ""
echo " Guarda estos valores — los necesitas para ECS y GitHub Secrets:"
echo ""
echo " VPC_ID=$VPC_ID"
echo " SUBNET_PUB_1=$SUBNET_PUB_1"
echo " SUBNET_PUB_2=$SUBNET_PUB_2"
echo " SG_ALB=$SG_ALB"
echo " SG_ECS=$SG_ECS"
echo " SG_RDS=$SG_RDS"
echo " ALB_ARN=$ALB_ARN"
echo " ALB_DNS=$ALB_DNS"
echo " TG_FRONT_ARN=$TG_FRONT_ARN"
echo " TG_DESPACHOS_ARN=$TG_DESPACHOS_ARN"
echo " TG_VENTAS_ARN=$TG_VENTAS_ARN"
echo ""
echo " URL pública de la app: http://$ALB_DNS"
echo "============================================================"

# Guardar en archivo para referencia
cat > infra-output.env << EOF
VPC_ID=$VPC_ID
SUBNET_PUB_1=$SUBNET_PUB_1
SUBNET_PUB_2=$SUBNET_PUB_2
SG_ALB=$SG_ALB
SG_ECS=$SG_ECS
SG_RDS=$SG_RDS
ALB_ARN=$ALB_ARN
ALB_DNS=$ALB_DNS
TG_FRONT_ARN=$TG_FRONT_ARN
TG_DESPACHOS_ARN=$TG_DESPACHOS_ARN
TG_VENTAS_ARN=$TG_VENTAS_ARN
EOF

echo " Valores guardados en: infra-output.env"
