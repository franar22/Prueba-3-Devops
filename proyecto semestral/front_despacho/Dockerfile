# ---- Stage 1: Build ----
FROM node:20-alpine AS builder

WORKDIR /app

# Copiar dependencias primero (aprovecha cache de Docker)
COPY package*.json ./
RUN npm ci

# Copiar código fuente
COPY . .

# Variable para que el frontend sepa la URL del backend en producción
# Se pasa en tiempo de build: docker build --build-arg VITE_API_URL=http://...
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL

RUN npm run build

# ---- Stage 2: Serve con nginx ----
FROM nginx:alpine

# Copiar build estático
COPY --from=builder /app/dist /usr/share/nginx/html

# Config nginx para que React Router funcione correctamente
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
