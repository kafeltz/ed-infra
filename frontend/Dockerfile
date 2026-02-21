FROM node:20-alpine AS build
WORKDIR /app
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
