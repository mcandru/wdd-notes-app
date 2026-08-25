FROM node:22-slim

WORKDIR /app

# Copy the package files and install dependencies
COPY backend/package.json backend/package-lock.json ./
RUN npm install

# Create uploads directory
RUN mkdir -p /app/uploads

# Source code is volume-mounted in development, so no COPY for src/
# This keeps the image lean and lets bind mounts handle live code

EXPOSE 8000
CMD ["npm", "run", "dev"]
