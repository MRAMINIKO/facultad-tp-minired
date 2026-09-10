# Imagen para desplegar en el homelab (dokploy / Traefik).
# IMPORTANTE: el contexto de build es la carpeta tp/, no tp/landing/.
#   docker build -t minired -f Dockerfile .        (parado en tp/)
FROM node:20-alpine
WORKDIR /app

# dependencias primero, para aprovechar la cache de capas
COPY landing/backend/package.json ./landing/backend/package.json
RUN cd landing/backend && npm install --omit=dev

# el backend sirve los estaticos de ../ y lee ../../sql/03_payload.sql
COPY landing/backend/ ./landing/backend/
COPY landing/index.html landing/datos.js ./landing/
# ojo: COPY de un directorio copia su CONTENIDO, asi que el destino
# tiene que nombrar la carpeta explicitamente o los PNG quedan sueltos
COPY landing/assets/ ./landing/assets/
COPY sql/ ./sql/

# Variables a definir en dokploy: DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME
ENV PORT=3000
EXPOSE 3000
WORKDIR /app/landing/backend
CMD ["node", "server.js"]
