#!/bin/bash

echo "Criando diretórios da Fase 4..."
mkdir -p obra-ipiranga/backend
mkdir -p obra-ipiranga/frontend/src/app

echo "Gerando Dockerfile e package.json do Backend..."
cat << 'EOF' > obra-ipiranga/backend/Dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma/
RUN npm install
COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./
COPY --from=builder /app/prisma ./prisma
EXPOSE 3333
CMD ["npm", "run", "start:api"]
EOF

cat << 'EOF' > obra-ipiranga/backend/package.json
{
  "name": "obra-backend",
  "version": "1.0.0",
  "scripts": {
    "dev:api": "ts-node-dev --transpile-only src/api/server.ts",
    "dev:worker": "ts-node-dev --transpile-only src/worker/index.ts",
    "build": "tsc",
    "start:api": "node dist/api/server.js",
    "start:worker": "node dist/worker/index.js",
    "prisma:generate": "prisma generate",
    "prisma:migrate": "prisma migrate deploy",
    "seed": "ts-node prisma/seed.ts"
  },
  "dependencies": {
    "@prisma/client": "^5.0.0",
    "axios": "^1.6.0",
    "bcrypt": "^5.1.0",
    "bullmq": "^4.10.0",
    "cookie-parser": "^1.4.6",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "ioredis": "^5.3.0",
    "jsonwebtoken": "^9.0.0",
    "pino": "^8.14.0",
    "zod": "^3.21.0"
  },
  "devDependencies": {
    "@types/bcrypt": "^5.0.0",
    "@types/cookie-parser": "^1.4.3",
    "@types/cors": "^2.8.13",
    "@types/express": "^4.17.17",
    "@types/jsonwebtoken": "^9.0.2",
    "@types/node": "^20.0.0",
    "prisma": "^5.0.0",
    "ts-node": "^10.9.1",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

cat << 'EOF' > obra-ipiranga/backend/tsconfig.json
{
  "compilerOptions": {
    "target": "es2022",
    "module": "commonjs",
    "lib": ["es2022", "esnext.asynciterable"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"]
}
EOF

echo "Gerando arquivos do Frontend (Next.js + Tailwind)..."
cat << 'EOF' > obra-ipiranga/frontend/Dockerfile
FROM node:20-alpine AS base

FROM base AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM base AS runner
WORKDIR /app
ENV NODE_ENV production
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
EXPOSE 3000
ENV PORT 3000
CMD ["node", "server.js"]
EOF

cat << 'EOF' > obra-ipiranga/frontend/package.json
{
  "name": "obra-frontend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "lucide-react": "^0.292.0",
    "next": "14.0.0",
    "react": "^18",
    "react-dom": "^18",
    "tailwind-merge": "^2.0.0"
  },
  "devDependencies": {
    "@types/node": "^20",
    "@types/react": "^18",
    "@types/react-dom": "^18",
    "autoprefixer": "^10",
    "postcss": "^8",
    "tailwindcss": "^3",
    "typescript": "^5"
  }
}
EOF

cat << 'EOF' > obra-ipiranga/frontend/next.config.js
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
}
module.exports = nextConfig
EOF

cat << 'EOF' > obra-ipiranga/frontend/tailwind.config.ts
import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
export default config
EOF

cat << 'EOF' > obra-ipiranga/frontend/postcss.config.js
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF

cat << 'EOF' > obra-ipiranga/frontend/src/app/globals.css
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  --background: #f8fafc;
  --foreground: #0f172a;
}
body {
  background-color: var(--background);
  color: var(--foreground);
}
EOF

cat << 'EOF' > obra-ipiranga/frontend/src/app/layout.tsx
import './globals.css'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Gestão Obra Ipiranga',
  description: 'Sistema de gestão financeira para a obra Ipiranga 1',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  )
}
EOF

cat << 'EOF' > obra-ipiranga/frontend/src/app/page.tsx
export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-24">
      <div className="z-10 max-w-5xl w-full items-center justify-between font-mono text-sm lg:flex">
        <h1 className="text-4xl font-bold">Gestão Obra Ipiranga</h1>
      </div>
      <div className="mt-8 text-center">
        <p>Frontend inicializado com Next.js App Router e Tailwind CSS.</p>
        <p className="text-gray-500 mt-4">Pronto para iniciar o desenvolvimento dos componentes Shadcn UI.</p>
      </div>
    </main>
  )
}
EOF

echo "Compactando projeto final..."
cd obra-ipiranga
zip -r ../obra-ipiranga-completo.zip .
cd ..

echo "✅ Sucesso! O arquivo obra-ipiranga-completo.zip contendo todas as fases foi gerado."