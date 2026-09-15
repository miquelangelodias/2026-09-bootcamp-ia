FROM node:20-alpine AS base
WORKDIR /app

# OpenSSL 3 + compat (Prisma no Alpine/musl)
RUN apk add --no-cache openssl libc6-compat

COPY package*.json ./
RUN npm install

COPY prisma ./prisma
RUN npx prisma generate

COPY . .
RUN npm run build
RUN test -f dist/server.js || (echo "ERRO: dist/server.js nao gerado" && exit 1)

EXPOSE 3000
CMD ["node", "dist/server.js"]
