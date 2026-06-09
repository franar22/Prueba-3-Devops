# ---- Stage 1: Build ----
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /app

# Copiar pom y descargar dependencias primero (aprovecha cache de Docker)
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copiar código fuente y compilar
COPY src ./src
RUN mvn clean package -DskipTests -B

# ---- Stage 2: Runtime ----
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Copiar el jar generado
COPY --from=builder /app/target/*.jar app.jar

# Puerto que expone el backend de Despachos
EXPOSE 8081

# Variables de entorno requeridas (se inyectan en ECS Task Definition)
ENV DB_ENDPOINT=""
ENV DB_PORT="3306"
ENV DB_NAME=""
ENV DB_USERNAME=""
ENV DB_PASSWORD=""

ENTRYPOINT ["java", "-jar", "app.jar"]
