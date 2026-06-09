# ---- Stage 1: Build ----
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /app

COPY pom.xml .
RUN mvn dependency:go-offline -B

COPY src ./src
RUN mvn clean package -DskipTests -B

# ---- Stage 2: Runtime ----
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

COPY --from=builder /app/target/*.jar app.jar

# Puerto default de Spring Boot
EXPOSE 8080

ENV DB_ENDPOINT=""
ENV DB_PORT="3306"
ENV DB_NAME=""
ENV DB_USERNAME=""
ENV DB_PASSWORD=""

ENTRYPOINT ["java", "-jar", "app.jar"]
