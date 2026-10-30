# Base stage: the setup that the dev and production stages share
FROM node:22-slim AS base

WORKDIR /app

# Copy the dependency list on its own first, so Docker can cache the
# npm ci layer and only reinstall when package.json or package-lock.json change
COPY backend/package.json backend/package-lock.json ./

ENV PORT=8000
EXPOSE 8000

# Development stage: every dependency, including nodemon for hot reloading
FROM base AS dev

RUN npm ci
COPY backend/ ./

CMD ["npm", "run", "dev"]

# Frontend stage: builds the frontend into static files
FROM node:22-slim AS frontend

WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# Production stage: only the dependencies the app needs to run
FROM base AS production

ENV NODE_ENV=production

RUN npm ci --omit=dev
COPY backend/ ./

# Copies the static build from the frontend stage into the ./dist folder
COPY --from=frontend /backend/dist ./dist

# The folder for uploads when S3_BUCKET is not set. Owned by the node user,
# so the app can write to it without running as root.
RUN mkdir -p uploads && chown node:node uploads

# Don't run the app as root
USER node

# Run node directly, not npm start, so the app receives stop signals from Docker
CMD ["node", "server.js"]
