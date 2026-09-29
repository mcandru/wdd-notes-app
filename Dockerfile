FROM node:22-slim

WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN npm ci
COPY backend/ ./

ENV PORT=8000
EXPOSE 8000
CMD ["npm", "run", "dev"]
