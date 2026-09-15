#!/usr/bin/env bash
# Depois de rodar npm install e o seed, você já consegue testar POST /auth/login com o e-mail e senha definidos no .env.
set -euo pipefail

PROJETO="obra-ipiranga"

if [[ ! -d "${PROJETO}" ]]; then
  echo "Pasta ${PROJETO} não encontrada. Rode o setup-fase1.sh primeiro."
  exit 1
fi

cd "${PROJETO}"

echo "Escrevendo arquivos da Fase 2..."

# --- api/package.json ---
cat > api/package.json <<'EOF'
{
  "name": "obra-api",
  "version": "1.0.0",
  "private": true,
  "main": "dist/server.js",
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "dev:worker": "tsx watch src/worker.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/server.js",
    "start:worker": "node dist/worker.js",
    "prisma:generate": "prisma generate",
    "prisma:migrate": "prisma migrate deploy",
    "prisma:seed": "tsx prisma/seed.ts"
  },
  "dependencies": {
    "@prisma/client": "^5.20.0",
    "bcrypt": "^5.1.1",
    "bullmq": "^5.12.0",
    "cookie-parser": "^1.4.6",
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.19.2",
    "helmet": "^7.1.0",
    "ioredis": "^5.4.1",
    "jsonwebtoken": "^9.0.2",
    "pino": "^9.4.0",
    "pino-http": "^10.3.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/bcrypt": "^5.0.2",
    "@types/cookie-parser": "^1.4.7",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/jsonwebtoken": "^9.0.7",
    "@types/node": "^20.14.15",
    "prisma": "^5.20.0",
    "tsx": "^4.19.1",
    "typescript": "^5.5.4"
  }
}
EOF

# --- api/tsconfig.json ---
cat > api/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "moduleResolution": "node",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src"]
}
EOF

# --- api/Dockerfile ---
cat > api/Dockerfile <<'EOF'
FROM node:20-alpine AS base
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
RUN npx prisma generate
RUN npm run build
EXPOSE 3000
CMD ["node", "dist/server.js"]
EOF

# --- src/config/env.ts ---
cat > api/src/config/env.ts <<'EOF'
import { z } from 'zod';

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().min(1),
  JWT_SECRET: z.string().min(16),
  JWT_EXPIRES_IN: z.string().default('7d'),
  PORT: z.string().default('3000'),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error('Variáveis de ambiente inválidas:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;
EOF

# --- src/lib/logger.ts ---
cat > api/src/lib/logger.ts <<'EOF'
import pino from 'pino';
import { env } from '../config/env';

export const logger = pino({
  level: env.NODE_ENV === 'production' ? 'info' : 'debug',
  transport:
    env.NODE_ENV === 'production'
      ? undefined
      : { target: 'pino-pretty', options: { colorize: true } },
});
EOF

# --- src/lib/prisma.ts ---
cat > api/src/lib/prisma.ts <<'EOF'
import { PrismaClient } from '@prisma/client';

declare global {
  // eslint-disable-next-line no-var
  var prismaGlobal: PrismaClient | undefined;
}

export const prisma = global.prismaGlobal ?? new PrismaClient();

if (process.env.NODE_ENV !== 'production') {
  global.prismaGlobal = prisma;
}
EOF

# --- src/lib/queue.ts ---
cat > api/src/lib/queue.ts <<'EOF'
import { Queue } from 'bullmq';
import { env } from '../config/env';

const connection = { url: env.REDIS_URL };

export const alertasQueue = new Queue('alertas', { connection });
export const ocrQueue = new Queue('ocr', { connection });
export const whatsappQueue = new Queue('whatsapp', { connection });
EOF

# --- src/lib/errors.ts ---
cat > api/src/lib/errors.ts <<'EOF'
export class AppError extends Error {
  public readonly status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
    this.name = 'AppError';
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = 'Não autenticado.') {
    super(message, 401);
    this.name = 'UnauthorizedError';
  }
}
EOF

# --- src/middlewares/errorHandler.ts ---
cat > api/src/middlewares/errorHandler.ts <<'EOF'
import { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';
import { AppError } from '../lib/errors';
import { logger } from '../lib/logger';

export function errorHandler(
  err: unknown,
  req: Request,
  res: Response,
  _next: NextFunction
) {
  if (err instanceof ZodError) {
    return res.status(422).json({
      erro: 'Dados inválidos.',
      detalhes: err.flatten().fieldErrors,
    });
  }

  if (err instanceof AppError) {
    return res.status(err.status).json({ erro: err.message });
  }

  logger.error({ err, path: req.path }, 'Erro não tratado');
  return res.status(500).json({ erro: 'Erro interno do servidor.' });
}
EOF

# --- src/middlewares/auth.ts ---
cat > api/src/middlewares/auth.ts <<'EOF'
import { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { UnauthorizedError } from '../lib/errors';

export interface TokenPayload {
  userId: number;
  papel: 'admin' | 'socio';
  participanteId: number | null;
}

declare global {
  namespace Express {
    interface Request {
      usuario?: TokenPayload;
    }
  }
}

export function autenticar(req: Request, _res: Response, next: NextFunction) {
  const token = req.cookies?.token;

  if (!token) {
    return next(new UnauthorizedError());
  }

  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as TokenPayload;
    req.usuario = payload;
    next();
  } catch {
    next(new UnauthorizedError('Sessão inválida ou expirada.'));
  }
}

export function exigirPapel(...papeis: TokenPayload['papel'][]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.usuario || !papeis.includes(req.usuario.papel)) {
      return next(new UnauthorizedError('Sem permissão para este recurso.'));
    }
    next();
  };
}
EOF

# --- src/schemas/auth.schema.ts ---
cat > api/src/schemas/auth.schema.ts <<'EOF'
import { z } from 'zod';

export const loginSchema = z.object({
  body: z.object({
    email: z.string().email('E-mail inválido.'),
    senha: z.string().min(8, 'A senha deve ter ao menos 8 caracteres.'),
  }),
});

export type LoginInput = z.infer<typeof loginSchema>['body'];
EOF

# --- src/middlewares/validate.ts ---
cat > api/src/middlewares/validate.ts <<'EOF'
import { NextFunction, Request, Response } from 'express';
import { AnyZodObject } from 'zod';

export function validar(schema: AnyZodObject) {
  return (req: Request, _res: Response, next: NextFunction) => {
    try {
      schema.parse({ body: req.body, query: req.query, params: req.params });
      next();
    } catch (erro) {
      next(erro);
    }
  };
}
EOF

# --- src/routes/auth.routes.ts ---
cat > api/src/routes/auth.routes.ts <<'EOF'
import { Router } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { prisma } from '../lib/prisma';
import { env } from '../config/env';
import { validar } from '../middlewares/validate';
import { autenticar, TokenPayload } from '../middlewares/auth';
import { loginSchema } from '../schemas/auth.schema';
import { AppError } from '../lib/errors';

export const authRouter = Router();

const COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'lax' as const,
  maxAge: 7 * 24 * 60 * 60 * 1000,
};

authRouter.post('/login', validar(loginSchema), async (req, res, next) => {
  try {
    const { email, senha } = req.body;

    const usuario = await prisma.usuario.findUnique({ where: { email } });
    if (!usuario) {
      throw new AppError('E-mail ou senha incorretos.', 401);
    }

    const senhaValida = await bcrypt.compare(senha, usuario.senhaHash);
    if (!senhaValida) {
      throw new AppError('E-mail ou senha incorretos.', 401);
    }

    const payload: TokenPayload = {
      userId: usuario.id,
      papel: usuario.papel,
      participanteId: usuario.participanteId,
    };

    const token = jwt.sign(payload, env.JWT_SECRET, { expiresIn: env.JWT_EXPIRES_IN });

    res.cookie('token', token, COOKIE_OPTIONS);
    res.json({
      usuario: { id: usuario.id, nome: usuario.nome, email: usuario.email, papel: usuario.papel },
    });
  } catch (erro) {
    next(erro);
  }
});

authRouter.post('/logout', (_req, res) => {
  res.clearCookie('token', COOKIE_OPTIONS);
  res.status(204).send();
});

authRouter.get('/me', autenticar, async (req, res, next) => {
  try {
    const usuario = await prisma.usuario.findUnique({
      where: { id: req.usuario!.userId },
      select: { id: true, nome: true, email: true, papel: true, participanteId: true },
    });
    res.json({ usuario });
  } catch (erro) {
    next(erro);
  }
});
EOF

# --- src/server.ts ---
cat > api/src/server.ts <<'EOF'
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import pinoHttp from 'pino-http';
import { env } from './config/env';
import { logger } from './lib/logger';
import { authRouter } from './routes/auth.routes';
import { errorHandler } from './middlewares/errorHandler';

const app = express();

app.use(helmet());
app.use(
  cors({
    origin: process.env.NEXT_PUBLIC_API_URL ? undefined : true,
    credentials: true,
  })
);
app.use(cookieParser());
app.use(express.json());
app.use(pinoHttp({ logger }));

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.use('/auth', authRouter);

// Fase 3: montar aqui notasFiscais.routes, aportes.routes,
// participantes.routes, categorias.routes, conciliacao.routes, webhooks.routes

app.use(errorHandler);

app.listen(Number(env.PORT), () => {
  logger.info(`API rodando na porta ${env.PORT}`);
});
EOF

# --- src/worker.ts ---
cat > api/src/worker.ts <<'EOF'
import { Worker } from 'bullmq';
import { env } from './config/env';
import { logger } from './lib/logger';

const connection = { url: env.REDIS_URL };

const alertasWorker = new Worker(
  'alertas',
  async (job) => {
    logger.info({ jobId: job.id, data: job.data }, 'Processando alerta');
    // Fase 3: implementar envio real via WhatsApp/n8n
  },
  { connection }
);

alertasWorker.on('failed', (job, err) => {
  logger.error({ jobId: job?.id, err }, 'Falha ao processar alerta');
});

logger.info('Worker de alertas iniciado');
EOF

echo "Arquivos da Fase 2 gerados em ${PROJETO}/api"

read -p "Fazer commit da Fase 2 agora? (s/n) " resposta
if [[ "$resposta" == "s" ]]; then
  git add .
  git commit -q -m "feat: setup do Express, autenticacao JWT e schemas Zod"
  echo "Commit da Fase 2 criado."
fi