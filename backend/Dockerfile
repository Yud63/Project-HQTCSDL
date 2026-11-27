FROM node:22-alpine
WORKDIR /app/backend

COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev

COPY backend/ ./
COPY frontend/ /app/frontend/

RUN mkdir -p uploads && chown node:node uploads
USER node

EXPOSE 3000
CMD ["node", "server.js"]