#!/bin/bash
# ============================================================
# cleanup-aws-infra.sh
# Elimina TODA la infraestructura creada por setup-aws-infra.sh
# Úsalo al terminar de trabajar para no gastar créditos
#
# USO:
#   chmod +x cleanup-aws-infra.sh
#   ./cleanup-aws-infra.sh
# ============================================================

set -e

REGION="us-east-1"
PROJECT="innovatech"

echo "================================================"
echo " EP3 - Limpiando infraestructura AWS"
echo " ADVERTENCIA: Esto elimina TODO lo creado"
echo "================================================"
read -p " ¿Estás seguro? (escribe 'si' para continuar): " CONFIRM
if [ "$CONFIRM" != "si" ]; then
  echo "Cancelado."
  exit 0
fi

# ── Leer valores guardados ────────────────────────────────────
if [ -f "infra-output.env" ]; then
  source infra-output.env
  echo "Valores cargados desde infra-output.env"
else
  echo "No se encontró infra-output.env — ingresa los valores manualmente"
  read -p "VPC_ID: " VPC_ID
  read -p "ALB_ARN: " ALB_ARN
  read -p "TG_FRONT_ARN: " TG_FRONT_ARN
  read -p "TG_DESPACHOS_ARN: " TG_DESPACHOS_ARN
  read -p "TG_VENTAS_ARN: " TG_VENTAS_ARN
fi

echo ""

# ── 1. Eliminar servicios ECS ─────────────────────────────────
echo "[1] Eliminando servicios ECS..."
for SVC in innovatech-frontend-service innovatech-despachos-service innovatech-ventas-service; do
  aws ecs update-service --cluster innovatech-cluster --service $SVC --desired-count 0 --region $REGION 2>/dev/null && \
  aws ecs delete-service --cluster innovatech-cluster --service $SVC --region $REGION 2>/dev/null && \
  echo "  Eliminado: $SVC" || echo "  No existía: $SVC"
done

# ── 2. Eliminar cluster ECS ───────────────────────────────────
echo "[2] Eliminando cluster ECS..."
aws ecs delete-cluster --cluster innovatech-cluster --region $REGION 2>/dev/null && \
  echo "  Cluster eliminado" || echo "  No existía el cluster"

# ── 3. Eliminar Load Balancer ─────────────────────────────────
echo "[3] Eliminando Application Load Balancer..."
if [ -n "$ALB_ARN" ]; then
  # Eliminar listeners primero
  LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query 'Listeners[*].ListenerArn' --output text --region $REGION 2>/dev/null)
  for L in $LISTENERS; do
    aws elbv2 delete-listener --listener-arn $L --region $REGION 2>/dev/null
  done
  aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region $REGION 2>/dev/null
  echo "  ALB eliminado — esperando 15s..."
  sleep 15
fi

# ── 4. Eliminar Target Groups ─────────────────────────────────
echo "[4] Eliminando Target Groups..."
for TG in "$TG_FRONT_ARN" "$TG_DESPACHOS_ARN" "$TG_VENTAS_ARN"; do
  if [ -n "$TG" ]; then
    aws elbv2 delete-target-group --target-group-arn $TG --region $REGION 2>/dev/null && \
      echo "  Target group eliminado" || echo "  No se pudo eliminar target group"
  fi
done

# ── 5. Eliminar Security Groups ───────────────────────────────
echo "[5] Eliminando Security Groups..."
for SG_NAME in "$PROJECT-sg-ecs" "$PROJECT-sg-rds" "$PROJECT-sg-alb"; do
  SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' --output text --region $REGION 2>/dev/null)
  if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    aws ec2 delete-security-group --group-id $SG_ID --region $REGION 2>/dev/null && \
      echo "  Eliminado: $SG_NAME ($SG_ID)" || echo "  No se pudo eliminar: $SG_NAME"
  fi
done

# ── 6. Eliminar subredes ──────────────────────────────────────
echo "[6] Eliminando subredes..."
SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].SubnetId' --output text --region $REGION 2>/dev/null)
for SN in $SUBNETS; do
  aws ec2 delete-subnet --subnet-id $SN --region $REGION 2>/dev/null && \
    echo "  Eliminada subred: $SN" || echo "  No se pudo eliminar: $SN"
done

# ── 7. Eliminar Route Tables (no la principal) ────────────────
echo "[7] Eliminando Route Tables..."
RTS=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$PROJECT-rt-public" \
  --query 'RouteTables[*].RouteTableId' --output text --region $REGION 2>/dev/null)
for RT in $RTS; do
  aws ec2 delete-route-table --route-table-id $RT --region $REGION 2>/dev/null && \
    echo "  Eliminada route table: $RT" || echo "  No se pudo eliminar: $RT"
done

# ── 8. Desconectar y eliminar Internet Gateway ────────────────
echo "[8] Eliminando Internet Gateway..."
IGW=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[0].InternetGatewayId' --output text --region $REGION 2>/dev/null)
if [ -n "$IGW" ] && [ "$IGW" != "None" ]; then
  aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID --region $REGION 2>/dev/null
  aws ec2 delete-internet-gateway --internet-gateway-id $IGW --region $REGION 2>/dev/null && \
    echo "  Internet Gateway eliminado: $IGW"
fi

# ── 9. Eliminar VPC ───────────────────────────────────────────
echo "[9] Eliminando VPC..."
if [ -n "$VPC_ID" ]; then
  aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION 2>/dev/null && \
    echo "  VPC eliminada: $VPC_ID" || echo "  No se pudo eliminar la VPC (puede tener recursos aún activos)"
fi

# ── 10. Eliminar imágenes ECR (opcional) ─────────────────────
echo ""
read -p "[10] ¿Eliminar también los repositorios ECR? (escribe 'si' para confirmar): " DEL_ECR
if [ "$DEL_ECR" == "si" ]; then
  for REPO in innovatech-frontend innovatech-back-despachos innovatech-back-ventas; do
    aws ecr delete-repository --repository-name $REPO --force --region $REGION 2>/dev/null && \
      echo "  ECR eliminado: $REPO" || echo "  No existía: $REPO"
  done
fi

echo ""
echo "============================================================"
echo " ✅ Limpieza completada — créditos protegidos"
echo "============================================================"
echo ""
echo " Recuerda: la próxima vez que trabajes, ejecuta primero:"
echo "   ./setup-aws-infra.sh"
echo "   Y actualiza los secrets de GitHub con las nuevas credenciales"
echo "============================================================"
