#!/bin/bash

echo "Criando estrutura de diretórios..."
mkdir -p obra-ipiranga/backend/prisma
mkdir -p obra-ipiranga/backend/src/api/controllers
mkdir -p obra-ipiranga/backend/src/api/middlewares
mkdir -p obra-ipiranga/backend/src/api/routes
mkdir -p obra-ipiranga/backend/src/api/schemas
mkdir -p obra-ipiranga/backend/src/core/config
mkdir -p obra-ipiranga/backend/src/core/utils
mkdir -p obra-ipiranga/backend/src/types/express
mkdir -p obra-ipiranga/backend/src/worker/jobs
mkdir -p obra-ipiranga/backend/src/worker/queues
mkdir -p obra-ipiranga/frontend/src/app
mkdir -p obra-ipiranga/frontend/src/components
mkdir -p obra-ipiranga/frontend/src/hooks
mkdir -p obra-ipiranga/frontend/src/lib
mkdir -p obra-ipiranga/frontend/src/services
mkdir -p obra-ipiranga/frontend/src/types

echo "Gerando docker-compose.yml..."
cat << 'EOF' > obra-ipiranga/docker-compose.yml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: obra_postgres
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - app_network

  redis:
    image: redis:7-alpine
    container_name: obra_redis
    restart: always
    command: redis-server --requirepass "${REDIS_PASSWORD:-}"
    volumes:
      - redis_data:/data
    networks:
      - app_network

  api:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: obra_api
    restart: always
    command: npm run start:api
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - REDIS_HOST=${REDIS_HOST}
      - JWT_SECRET=${JWT_SECRET}
      - PORT=${API_PORT}
    networks:
      - app_network
      - traefik_proxy
    depends_on:
      - postgres
      - redis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.obra-api.rule=Host(`api.iastudio.shop`)"
      - "traefik.http.routers.obra-api.entrypoints=websecure"
      - "traefik.http.routers.obra-api.tls.certresolver=letsencrypt"
      - "traefik.http.services.obra-api.loadbalancer.server.port=${API_PORT}"

  worker:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: obra_worker
    restart: always
    command: npm run start:worker
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - REDIS_HOST=${REDIS_HOST}
      - N8N_WEBHOOK_OCR_URL=${N8N_WEBHOOK_OCR_URL}
      - N8N_WEBHOOK_WHATSAPP_URL=${N8N_WEBHOOK_WHATSAPP_URL}
    networks:
      - app_network
    depends_on:
      - postgres
      - redis

  web:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: obra_web
    restart: always
    environment:
      - NEXT_PUBLIC_API_URL=https://api.iastudio.shop
    networks:
      - app_network
      - traefik_proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.obra-web.rule=Host(`obra.iastudio.shop`)"
      - "traefik.http.routers.obra-web.entrypoints=websecure"
      - "traefik.http.routers.obra-web.tls.certresolver=letsencrypt"
      - "traefik.http.services.obra-web.loadbalancer.server.port=3000"

volumes:
  postgres_data:
  redis_data:

networks:
  app_network:
    driver: bridge
  traefik_proxy:
    external: true
EOF

echo "Gerando .env.example..."
cat << 'EOF' > obra-ipiranga/.env.example
# ==========================================
# GERAL
# ==========================================
NODE_ENV=development

# ==========================================
# BANCO DE DADOS (PostgreSQL)
# ==========================================
POSTGRES_USER=obra_user
POSTGRES_PASSWORD=obra_password
POSTGRES_DB=obra_ipiranga
DATABASE_URL="postgresql://obra_user:obra_password@postgres:5432/obra_ipiranga?schema=public"

# ==========================================
# FILAS (Redis)
# ==========================================
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=

# ==========================================
# API E AUTENTICAÇÃO
# ==========================================
API_PORT=3333
JWT_SECRET=super_secret_key_change_in_production
JWT_EXPIRES_IN=7d
ADMIN_DEFAULT_EMAIL=admin@iastudio.shop
ADMIN_DEFAULT_PASSWORD=mudar123

# ==========================================
# INTEGRAÇÕES (n8n / WhatsApp)
# ==========================================
N8N_WEBHOOK_OCR_URL=https://n8n.seu-dominio.com/webhook/ocr
N8N_WEBHOOK_WHATSAPP_URL=https://n8n.seu-dominio.com/webhook/whatsapp
EOF

echo "Gerando schema.prisma..."
cat << 'EOF' > obra-ipiranga/backend/prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model Obra {
  id           String   @id @default(uuid())
  nome         String
  endereco     String
  area_m2      Float
  valor_orcado Decimal  @db.Decimal(10, 2)
  data_inicio  DateTime

  notas_fiscais NotasFiscais[]
  aportes       Aportes[]

  @@map("obras")
}

model Participante {
  id        String @id @default(uuid())
  nome      String
  cpf       String @unique
  chave_pix String

  notas_fiscais NotasFiscais[]
  aportes       Aportes[]
  usuarios      Usuario[]

  @@map("participantes")
}

model Fornecedor {
  id   String @id @default(uuid())
  nome String @unique

  notas_fiscais NotasFiscais[]

  @@map("fornecedores")
}

model Categoria {
  id    String @id @default(uuid())
  nome  String
  etapa String

  notas_fiscais NotasFiscais[]

  @@map("categorias")
}

enum StatusNota {
  pendente_revisao
  confirmada
}

enum OrigemNota {
  whatsapp
  upload_web
  planilha
}

model NotasFiscais {
  id                       String     @id @default(uuid())
  obra_id                  String
  fornecedor_id            String
  numero_nota              String
  chave_acesso             String     @unique @db.VarChar(44)
  data_emissao             DateTime
  valor_total              Decimal    @db.Decimal(10, 2)
  categoria_id             String?
  categorizado_manualmente Boolean    @default(false)
  cpf_destinatario         String
  participante_id          String?
  imagem_url               String?
  status                   StatusNota @default(pendente_revisao)
  origem                   OrigemNota
  criado_em                DateTime   @default(now())

  obra         Obra         @relation(fields: [obra_id], references: [id])
  fornecedor   Fornecedor   @relation(fields: [fornecedor_id], references: [id])
  categoria    Categoria?   @relation(fields: [categoria_id], references: [id])
  participante Participante? @relation(fields: [participante_id], references: [id])
  
  transacoes   TransacoesBancarias[]

  @@map("notas_fiscais")
}

model Aportes {
  id              String   @id @default(uuid())
  obra_id         String
  participante_id String
  data            DateTime
  valor           Decimal  @db.Decimal(10, 2)

  obra         Obra         @relation(fields: [obra_id], references: [id])
  participante Participante @relation(fields: [participante_id], references: [id])

  @@map("aportes")
}

enum TipoTransacao {
  credito
  debito
}

model TransacoesBancarias {
  id             String        @id @default(uuid())
  data           DateTime
  descricao      String
  valor          Decimal       @db.Decimal(10, 2)
  tipo           TipoTransacao
  conciliado     Boolean       @default(false)
  nota_fiscal_id String?

  nota_fiscal NotasFiscais? @relation(fields: [nota_fiscal_id], references: [id])

  @@map("transacoes_bancarias")
}

enum PapelUsuario {
  admin
  socio
}

model Usuario {
  id              String       @id @default(uuid())
  nome            String
  email           String       @unique
  senha_hash      String
  papel           PapelUsuario @default(socio)
  participante_id String?

  participante Participante? @relation(fields: [participante_id], references: [id])

  @@map("usuarios")
}

model Alertas {
  id                String   @id @default(uuid())
  tipo              String
  origem            String
  referencia_tabela String
  referencia_id     String
  mensagem          String
  enviado_em        DateTime @default(now())

  @@map("alertas")
}
EOF

echo "Gerando seed.ts..."
cat << 'EOF' > obra-ipiranga/backend/prisma/seed.ts
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  const adminEmail = process.env.ADMIN_DEFAULT_EMAIL;
  const adminPassword = process.env.ADMIN_DEFAULT_PASSWORD;

  if (!adminEmail || !adminPassword) {
    console.error('❌ Credenciais de Admin não encontradas no .env');
    process.exit(1);
  }

  const existingAdmin = await prisma.usuario.findUnique({
    where: { email: adminEmail },
  });

  if (existingAdmin) {
    console.log('✅ Usuário admin já existe no banco de dados.');
    return;
  }

  const saltRounds = 10;
  const senha_hash = await bcrypt.hash(adminPassword, saltRounds);

  await prisma.usuario.create({
    data: {
      nome: 'Administrador do Sistema',
      email: adminEmail,
      senha_hash,
      papel: 'admin',
    },
  });

  console.log(`🚀 Admin inicial criado com sucesso! E-mail: ${adminEmail}`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
EOF

echo "Gerando utils e configurações do Core..."
cat << 'EOF' > obra-ipiranga/backend/src/core/config/prisma.ts
import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient();
EOF

cat << 'EOF' > obra-ipiranga/backend/src/core/utils/logger.ts
import pino from 'pino';

export const logger = pino({
  level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
  transport: process.env.NODE_ENV !== 'production' ? {
    target: 'pino-pretty',
    options: { colorize: true }
  } : undefined,
});
EOF

echo "Gerando tipagens e tratamento de erros do Express..."
cat << 'EOF' > obra-ipiranga/backend/src/types/express/index.d.ts
declare namespace Express {
  export interface Request {
    user?: {
      id: string;
      papel: string;
      participante_id: string | null;
    };
  }
}
EOF

cat << 'EOF' > obra-ipiranga/backend/src/api/middlewares/errorHandler.ts
import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { logger } from '../../core/utils/logger';

export class AppError extends Error {
  public readonly statusCode: number;

  constructor(message: string, statusCode = 400) {
    super(message);
    this.statusCode = statusCode;
  }
}

export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
) {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      status: 'error',
      message: err.message,
    });
  }

  if (err instanceof ZodError) {
    return res.status(400).json({
      status: 'validation_error',
      errors: err.format(),
    });
  }

  logger.error(err);

  return res.status(500).json({
    status: 'error',
    message: 'Erro interno do servidor.',
  });
}
EOF

echo "Gerando schemas, controllers, middlewares e rotas de Auth..."
cat << 'EOF' > obra-ipiranga/backend/src/api/schemas/auth.schema.ts
import { z } from 'zod';

export const loginSchema = z.object({
  body: z.object({
    email: z.string().email('Formato de e-mail inválido.'),
    senha: z.string().min(6, 'A senha deve ter pelo menos 6 caracteres.'),
  }),
});
EOF

cat << 'EOF' > obra-ipiranga/backend/src/api/middlewares/auth.middleware.ts
import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AppError } from './errorHandler';

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const token = req.cookies.token;

  if (!token) {
    return next(new AppError('Não autorizado. Token ausente.', 401));
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET as string) as any;
    req.user = decoded;
    next();
  } catch (error) {
    return next(new AppError('Sessão inválida ou expirada.', 401));
  }
}
EOF

cat << 'EOF' > obra-ipiranga/backend/src/api/controllers/auth.controller.ts
import { Request, Response, NextFunction } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { prisma } from '../../core/config/prisma';
import { AppError } from '../middlewares/errorHandler';

export const authController = {
  async login(req: Request, res: Response, next: NextFunction) {
    try {
      const { email, senha } = req.body;

      const usuario = await prisma.usuario.findUnique({ where: { email } });
      if (!usuario) {
        throw new AppError('Credenciais inválidas.', 401);
      }

      const senhaValida = await bcrypt.compare(senha, usuario.senha_hash);
      if (!senhaValida) {
        throw new AppError('Credenciais inválidas.', 401);
      }

      const token = jwt.sign(
        { 
          id: usuario.id, 
          papel: usuario.papel, 
          participante_id: usuario.participante_id 
        },
        process.env.JWT_SECRET as string,
        { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
      );

      res.cookie('token', token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        maxAge: 7 * 24 * 60 * 60 * 1000,
      });

      return res.json({
        usuario: {
          id: usuario.id,
          nome: usuario.nome,
          email: usuario.email,
          papel: usuario.papel,
        },
      });
    } catch (error) {
      next(error);
    }
  },

  async logout(req: Request, res: Response) {
    res.clearCookie('token');
    return res.status(200).json({ message: 'Logout realizado com sucesso.' });
  },
};
EOF

cat << 'EOF' > obra-ipiranga/backend/src/api/routes/auth.routes.ts
import { Router } from 'express';
import { authController } from '../controllers/auth.controller';
import { loginSchema } from '../schemas/auth.schema';
import { requireAuth } from '../middlewares/auth.middleware';
import { AnyZodObject } from 'zod';

const router = Router();

export const validateSchema = (schema: AnyZodObject) => 
  async (req: any, res: any, next: any) => {
    try {
      await schema.parseAsync({
        body: req.body,
        query: req.query,
        params: req.params,
      });
      return next();
    } catch (error) {
      return next(error);
    }
  };

router.post('/login', validateSchema(loginSchema), authController.login);
router.post('/logout', authController.logout);
router.get('/me', requireAuth, (req, res) => res.json({ user: req.user }));

export default router;
EOF

echo "Gerando server.ts..."
cat << 'EOF' > obra-ipiranga/backend/src/api/server.ts
import express from 'express';
import cookieParser from 'cookie-parser';
import cors from 'cors';
import { logger } from '../core/utils/logger';
import { errorHandler } from './middlewares/errorHandler';
import authRoutes from './routes/auth.routes';

const app = express();

app.use(express.json());
app.use(cookieParser());
app.use(
  cors({
    origin: process.env.FRONTEND_URL || 'https://obra.iastudio.shop',
    credentials: true,
  })
);

app.use('/api/auth', authRoutes);

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.use(errorHandler);

const PORT = process.env.PORT || 3333;

app.listen(PORT, () => {
  logger.info(`🚀 API rodando na porta ${PORT}`);
});
EOF

echo "Compactando projeto..."
cd obra-ipiranga
zip -r ../obra-ipiranga.zip .
cd ..

echo "✅ Sucesso! O arquivo obra-ipiranga.zip foi criado no seu diretório atual."