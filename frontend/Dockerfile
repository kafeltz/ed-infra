FROM node:20-alpine AS build
WORKDIR /app

ARG VITE_KEYCLOAK_URL=http://localhost:8080
ARG VITE_KEYCLOAK_REALM=easydoor
ARG VITE_KEYCLOAK_CLIENT_ID=easydoor-frontend
ENV VITE_KEYCLOAK_URL=$VITE_KEYCLOAK_URL
ENV VITE_KEYCLOAK_REALM=$VITE_KEYCLOAK_REALM
ENV VITE_KEYCLOAK_CLIENT_ID=$VITE_KEYCLOAK_CLIENT_ID

COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package*.json ./
COPY vite.config.* ./
ARG PORT=4173
ENV PORT=$PORT
EXPOSE $PORT
CMD ["sh", "-c", "npx vite preview --port $PORT --host 0.0.0.0"]
