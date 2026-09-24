FROM node:24-alpine

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci --omit=dev

COPY sql ./sql
COPY src ./src

EXPOSE 3000

CMD ["node", "src/server.js"]