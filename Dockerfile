# Development stage: install all deps, bind mount with hot reload
FROM node:22-slim AS dev

WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN npm install
COPY backend/ ./

ENV PORT=8000
EXPOSE 8000
CMD ["npm", "run", "dev"]

# Frontend stage: Build the frontend into static files
FROM node:22-slim AS frontend

WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm install
COPY frontend/ ./
RUN npm run build

# Production stage: runtime dependencies only, no build tools,
FROM node:22-slim AS production

WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN npm install --omit=dev
COPY backend/ ./

# Copies static build from frontend stage into the ./dist folder
COPY --from=frontend /backend/dist ./dist

ENV PORT=8000
EXPOSE 8000
CMD ["node", "server.js"]
