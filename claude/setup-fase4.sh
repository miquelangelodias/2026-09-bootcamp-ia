#!/usr/bin/env bash
# Com isso, o backend cobre todas as regras que definimos: rateio por CPF, categorização com fallback manual, alertas via fila, conciliação bancária e exportação CSV.

set -euo pipefail

PROJETO="obra-ipiranga"

if [[ ! -d "${PROJETO}/api/src" ]]; then
  echo "Estrutura da api não encontrada. Rode as fases 1, 2 e 3 primeiro."
  exit 1
fi

cd "${PROJETO}"

echo "Escrevendo arquivos da Fase 4..."

# --- package.json (adiciona dependências de upload e csv) ---
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
    "csv-parse": "^5.5.6",
    "csv-stringify": "^6.5.1",
    "dotenv": "^16.4.5",
    "express": "^4.19.2",
    "helmet": "^7.1.0",
    "ioredis": "^5.4.1",
    "jsonwebtoken": "^9.0.2",
    "multer": "^1.4.5-lts.1",
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
    "@types/multer": "^1.4.11",
    "@types/node": "^20.14.15",
    "prisma": "^5.20.0",
    "tsx": "^4.19.1",
    "typescript": "^5.5.4"
  }
}
EOF

# --- prisma/schema.prisma (adiciona aporteId em TransacaoBancaria) ---
cat > api/prisma/schema.prisma <<'EOF'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

enum PapelUsuario {
  admin
  socio
}

enum StatusNota {
  pendente_revisao
  confirmada
}

enum OrigemLancamento {
  whatsapp
  upload_web
  planilha
}

enum TipoTransacao {
  credito
  debito
}

model Obra {
  id           Int      @id @default(autoincrement())
  nome         String
  endereco     String?
  areaM2       Decimal? @map("area_m2")
  valorOrcado  Decimal? @map("valor_orcado")
  dataInicio   DateTime? @map("data_inicio")
  notasFiscais NotaFiscal[]
  aportes      Aporte[]

  @@map("obras")
}

model Participante {
  id           Int      @id @default(autoincrement())
  nome         String
  cpf          String   @unique
  chavePix     String?  @map("chave_pix")
  usuarios     Usuario[]
  notasFiscais NotaFiscal[]
  aportes      Aporte[]

  @@map("participantes")
}

model Fornecedor {
  id           Int      @id @default(autoincrement())
  nome         String   @unique
  notasFiscais NotaFiscal[]

  @@map("fornecedores")
}

model Categoria {
  id           Int      @id @default(autoincrement())
  nome         String
  etapa        String?
  notasFiscais NotaFiscal[]

  @@map("categorias")
}

model NotaFiscal {
  id                      Int              @id @default(autoincrement())
  obraId                  Int              @map("obra_id")
  obra                    Obra             @relation(fields: [obraId], references: [id])
  fornecedorId            Int?             @map("fornecedor_id")
  fornecedor              Fornecedor?      @relation(fields: [fornecedorId], references: [id])
  numeroNota              String?          @map("numero_nota")
  chaveAcesso             String?          @unique @map("chave_acesso")
  dataEmissao             DateTime?        @map("data_emissao")
  valorTotal              Decimal          @map("valor_total")
  categoriaId             Int?             @map("categoria_id")
  categoria               Categoria?       @relation(fields: [categoriaId], references: [id])
  categorizadoManualmente Boolean          @default(false) @map("categorizado_manualmente")
  cpfDestinatario         String?          @map("cpf_destinatario")
  participanteId          Int?             @map("participante_id")
  participante            Participante?    @relation(fields: [participanteId], references: [id])
  imagemUrl               String?          @map("imagem_url")
  status                  StatusNota       @default(pendente_revisao)
  origem                  OrigemLancamento
  criadoEm                DateTime         @default(now()) @map("criado_em")
  transacoesBancarias     TransacaoBancaria[]

  @@map("notas_fiscais")
}

model Aporte {
  id                  Int          @id @default(autoincrement())
  obraId              Int          @map("obra_id")
  obra                Obra         @relation(fields: [obraId], references: [id])
  participanteId      Int          @map("participante_id")
  participante        Participante @relation(fields: [participanteId], references: [id])
  data                DateTime
  valor               Decimal
  transacoesBancarias TransacaoBancaria[]

  @@map("aportes")
}

model TransacaoBancaria {
  id           Int           @id @default(autoincrement())
  data         DateTime
  descricao    String?
  valor        Decimal
  tipo         TipoTransacao
  conciliado   Boolean       @default(false)
  notaFiscalId Int?          @map("nota_fiscal_id")
  notaFiscal   NotaFiscal?   @relation(fields: [notaFiscalId], references: [id])
  aporteId     Int?          @map("aporte_id")
  aporte       Aporte?       @relation(fields: [aporteId], references: [id])

  @@map("transacoes_bancarias")
}

model Usuario {
  id             Int           @id @default(autoincrement())
  nome           String
  email          String        @unique
  senhaHash      String        @map("senha_hash")
  papel          PapelUsuario
  participanteId Int?          @map("participante_id")
  participante   Participante? @relation(fields: [participanteId], references: [id])
  criadoEm       DateTime      @default(now()) @map("criado_em")

  @@map("usuarios")
}

model Alerta {
  id               Int      @id @default(autoincrement())
  tipo             String
  origem           String
  referenciaTabela String   @map("referencia_tabela")
  referenciaId     Int      @map("referencia_id")
  mensagem         String
  enviadoEm        DateTime @default(now()) @map("enviado_em")

  @@map("alertas")
}
EOF

# --- lib/n8n.ts ---
cat > api/src/lib/n8n.ts <<'EOF'
interface OcrResultado {
  fornecedorNome: string;
  valorTotal: number;
  dataEmissao?: string;
  cpfDestinatario?: string;
  chaveAcesso?: string;
}

export async function chamarN8nOcr(imagemUrl: string): Promise<OcrResultado> {
  const resposta = await fetch(`${process.env.N8N_WEBHOOK_URL}/ocr`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Webhook-Secret': process.env.N8N_WEBHOOK_SECRET ?? '',
    },
    body: JSON.stringify({ imagemUrl }),
  });

  if (!resposta.ok) {
    throw new Error(`Falha ao chamar OCR no n8n: ${resposta.status}`);
  }

  return resposta.json();
}

export async function chamarN8nWhatsapp(mensagem: string, telefone?: string) {
  const resposta = await fetch(`${process.env.N8N_WEBHOOK_URL}/whatsapp/enviar`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Webhook-Secret': process.env.N8N_WEBHOOK_SECRET ?? '',
    },
    body: JSON.stringify({ mensagem, telefone }),
  });

  if (!resposta.ok) {
    throw new Error(`Falha ao enviar WhatsApp via n8n: ${resposta.status}`);
  }
}
EOF

# --- worker.ts (adiciona processamento de ocr e whatsapp, e alerta real) ---
cat > api/src/worker.ts <<'EOF'
import { Worker } from 'bullmq';
import { env } from './config/env';
import { logger } from './lib/logger';
import { chamarN8nOcr, chamarN8nWhatsapp } from './lib/n8n';
import { notaFiscalService } from './services/notaFiscal.service';

const connection = { url: env.REDIS_URL };

const alertasWorker = new Worker(
  'alertas',
  async (job) => {
    logger.info({ jobId: job.id, data: job.data }, 'Processando alerta');
    const origemTexto = job.data.origem === 'planilha' ? '(via planilha)' : '(via site)';
    await chamarN8nWhatsapp(`${job.data.mensagem} ${origemTexto}`);
  },
  { connection }
);

const ocrWorker = new Worker(
  'ocr',
  async (job) => {
    logger.info({ jobId: job.id }, 'Processando OCR de nota fiscal');
    const resultado = await chamarN8nOcr(job.data.imagemUrl);

    await notaFiscalService.criar({
      obraId: job.data.obraId,
      fornecedorNome: resultado.fornecedorNome,
      valorTotal: resultado.valorTotal,
      dataEmissao: resultado.dataEmissao ? new Date(resultado.dataEmissao) : undefined,
      cpfDestinatario: resultado.cpfDestinatario,
      chaveAcesso: resultado.chaveAcesso,
      imagemUrl: job.data.imagemUrl,
      origem: 'whatsapp',
    });
  },
  { connection }
);

const whatsappWorker = new Worker(
  'whatsapp',
  async (job) => {
    logger.info({ jobId: job.id, data: job.data }, 'Processando mensagem do WhatsApp');
    // Mensagens de texto com comandos simples (ex: "aporte 3000 elismar")
    // podem ser tratadas aqui futuramente. Imagens já chegam encaminhadas
    // para a fila "ocr" pelo endpoint de webhook.
  },
  { connection }
);

for (const worker of [alertasWorker, ocrWorker, whatsappWorker]) {
  worker.on('failed', (job, err) => {
    logger.error({ jobId: job?.id, err }, `Falha ao processar job na fila ${worker.name}`);
  });
}

logger.info('Worker iniciado: alertas, ocr, whatsapp');
EOF

# --- schemas/webhook.schema.ts ---
cat > api/src/schemas/webhook.schema.ts <<'EOF'
import { z } from 'zod';

export const webhookWhatsappSchema = z.object({
  body: z.object({
    tipo: z.enum(['imagem', 'texto']),
    obraId: z.coerce.number().int(),
    imagemUrl: z.string().url().optional(),
    texto: z.string().optional(),
    telefone: z.string().optional(),
  }),
});

export const webhookSheetsSchema = z.object({
  body: z.object({
    origem: z.literal('planilha'),
    aba: z.string(),
    linha: z.number(),
    valores: z.array(z.union([z.string(), z.number()])),
  }),
});
EOF

# --- middlewares/webhookAuth.ts ---
cat > api/src/middlewares/webhookAuth.ts <<'EOF'
import { NextFunction, Request, Response } from 'express';
import { UnauthorizedError } from '../lib/errors';

export function validarSegredoWebhook(variavelEnv: string) {
  return (req: Request, _res: Response, next: NextFunction) => {
    const esperado = process.env[variavelEnv];
    const recebido = req.header('X-Webhook-Secret');

    if (!esperado || recebido !== esperado) {
      return next(new UnauthorizedError('Segredo de webhook inválido.'));
    }

    next();
  };
}
EOF

# --- routes/webhooks.routes.ts ---
cat > api/src/routes/webhooks.routes.ts <<'EOF'
import { Router } from 'express';
import { validar } from '../middlewares/validate';
import { validarSegredoWebhook } from '../middlewares/webhookAuth';
import { webhookWhatsappSchema, webhookSheetsSchema } from '../schemas/webhook.schema';
import { ocrQueue, whatsappQueue } from '../lib/queue';
import { notaFiscalService } from '../services/notaFiscal.service';
import { aporteService } from '../services/aporte.service';
import { AppError } from '../lib/errors';

export const webhooksRouter = Router();

// Chamado pelo n8n, que recebe as mensagens reais do WhatsApp e as encaminha já tratadas.
webhooksRouter.post(
  '/whatsapp',
  validarSegredoWebhook('N8N_WEBHOOK_SECRET'),
  validar(webhookWhatsappSchema),
  async (req, res, next) => {
    try {
      const { tipo, obraId, imagemUrl, texto, telefone } = req.body;

      if (tipo === 'imagem' && imagemUrl) {
        await ocrQueue.add('foto-nota-fiscal', { obraId, imagemUrl });
      } else {
        await whatsappQueue.add('mensagem-texto', { obraId, texto, telefone });
      }

      res.status(202).json({ recebido: true });
    } catch (erro) {
      next(erro);
    }
  }
);

// Chamado pelo Apps Script da planilha a cada edição de linha.
webhooksRouter.post(
  '/sheets',
  validarSegredoWebhook('SHEETS_WEBHOOK_SECRET'),
  validar(webhookSheetsSchema),
  async (req, res, next) => {
    try {
      const { aba, valores } = req.body;

      // Ajuste os índices de "valores" conforme a ordem real das colunas
      // de cada aba da sua planilha.
      if (aba === 'DESP MATERIAIS') {
        await notaFiscalService.criar({
          obraId: 1,
          fornecedorNome: String(valores[1]),
          dataEmissao: valores[2] ? new Date(valores[2]) : undefined,
          valorTotal: Number(valores[3]),
          origem: 'planilha',
        });
      } else if (aba === 'APORTE CAIXA') {
        await aporteService.criar({
          obraId: 1,
          participanteId: Number(valores[0]),
          data: new Date(valores[1]),
          valor: Number(valores[2]),
        });
      } else {
        throw new AppError(`Aba "${aba}" não mapeada para importação.`, 422);
      }

      res.status(202).json({ recebido: true });
    } catch (erro) {
      next(erro);
    }
  }
);
EOF

# --- schemas/conciliacao.schema.ts ---
cat > api/src/schemas/conciliacao.schema.ts <<'EOF'
import { z } from 'zod';

export const listarPendenciasSchema = z.object({
  query: z.object({
    page: z.coerce.number().int().optional(),
    pageSize: z.coerce.number().int().optional(),
  }),
});
EOF

# --- services/conciliacao.service.ts ---
cat > api/src/services/conciliacao.service.ts <<'EOF'
import { parse } from 'csv-parse/sync';
import { prisma } from '../lib/prisma';
import { parsePaginacao } from '../lib/pagination';

const TOLERANCIA_DIAS = 3;

interface LinhaExtrato {
  data: string;
  descricao: string;
  valor: string;
  tipo: string;
}

function diferencaEmDias(a: Date, b: Date) {
  return Math.abs(a.getTime() - b.getTime()) / (1000 * 60 * 60 * 24);
}

async function tentarConciliar(transacaoId: number, data: Date, valor: number, tipo: 'credito' | 'debito') {
  if (tipo === 'debito') {
    const notas = await prisma.notaFiscal.findMany({
      where: { valorTotal: valor },
    });
    const nota = notas.find(
      (n) => n.dataEmissao && diferencaEmDias(n.dataEmissao, data) <= TOLERANCIA_DIAS
    );
    if (nota) {
      await prisma.transacaoBancaria.update({
        where: { id: transacaoId },
        data: { conciliado: true, notaFiscalId: nota.id },
      });
      return true;
    }
  } else {
    const aportes = await prisma.aporte.findMany({ where: { valor } });
    const aporte = aportes.find((a) => diferencaEmDias(a.data, data) <= TOLERANCIA_DIAS);
    if (aporte) {
      await prisma.transacaoBancaria.update({
        where: { id: transacaoId },
        data: { conciliado: true, aporteId: aporte.id },
      });
      return true;
    }
  }
  return false;
}

export const conciliacaoService = {
  importarExtrato: async (conteudoCsv: Buffer) => {
    const linhas: LinhaExtrato[] = parse(conteudoCsv, {
      columns: true,
      skip_empty_lines: true,
      trim: true,
    });

    let importadas = 0;
    let conciliadasAutomaticamente = 0;

    for (const linha of linhas) {
      const valor = Number(linha.valor);
      const tipo = valor >= 0 ? 'credito' : 'debito';
      const data = new Date(linha.data);

      const transacao = await prisma.transacaoBancaria.create({
        data: {
          data,
          descricao: linha.descricao,
          valor: Math.abs(valor),
          tipo,
        },
      });

      importadas += 1;

      const conciliada = await tentarConciliar(transacao.id, data, Math.abs(valor), tipo);
      if (conciliada) conciliadasAutomaticamente += 1;
    }

    return { importadas, conciliadasAutomaticamente };
  },

  listarPendencias: async (filtros: { page?: number; pageSize?: number }) => {
    const { page, pageSize, skip, take } = parsePaginacao(filtros);

    const where = { conciliado: false };

    const [dados, total] = await Promise.all([
      prisma.transacaoBancaria.findMany({ where, orderBy: { data: 'desc' }, skip, take }),
      prisma.transacaoBancaria.count({ where }),
    ]);

    return { dados, total, page, pageSize };
  },
};
EOF

# --- controllers/conciliacao.controller.ts ---
cat > api/src/controllers/conciliacao.controller.ts <<'EOF'
import { Request, Response, NextFunction } from 'express';
import { conciliacaoService } from '../services/conciliacao.service';
import { AppError } from '../lib/errors';

export const conciliacaoController = {
  importar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      if (!req.file) {
        throw new AppError('Envie o arquivo CSV do extrato no campo "arquivo".', 422);
      }
      const resultado = await conciliacaoService.importarExtrato(req.file.buffer);
      res.status(201).json(resultado);
    } catch (erro) {
      next(erro);
    }
  },

  listarPendencias: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await conciliacaoService.listarPendencias(req.query as any));
    } catch (erro) {
      next(erro);
    }
  },
};
EOF

# --- routes/conciliacao.routes.ts ---
cat > api/src/routes/conciliacao.routes.ts <<'EOF'
import { Router } from 'express';
import multer from 'multer';
import { autenticar } from '../middlewares/auth';
import { validar } from '../middlewares/validate';
import { conciliacaoController } from '../controllers/conciliacao.controller';
import { listarPendenciasSchema } from '../schemas/conciliacao.schema';

const upload = multer({ storage: multer.memoryStorage() });

export const conciliacaoRouter = Router();

conciliacaoRouter.use(autenticar);
conciliacaoRouter.post('/importar', upload.single('arquivo'), conciliacaoController.importar);
conciliacaoRouter.get('/pendencias', validar(listarPendenciasSchema), conciliacaoController.listarPendencias);
EOF

# --- services/exportacao.service.ts ---
cat > api/src/services/exportacao.service.ts <<'EOF'
import { stringify } from 'csv-stringify/sync';
import { prisma } from '../lib/prisma';

export const exportacaoService = {
  notasFiscaisCsv: async () => {
    const notas = await prisma.notaFiscal.findMany({
      include: { fornecedor: true, categoria: true, participante: true },
      orderBy: { dataEmissao: 'asc' },
    });

    const linhas = notas.map((n) => ({
      data: n.dataEmissao?.toISOString().slice(0, 10) ?? '',
      fornecedor: n.fornecedor?.nome ?? '',
      categoria: n.categoria?.nome ?? '',
      socio: n.participante?.nome ?? '',
      valor: n.valorTotal.toString(),
      status: n.status,
    }));

    return stringify(linhas, {
      header: true,
      columns: ['data', 'fornecedor', 'categoria', 'socio', 'valor', 'status'],
    });
  },

  aportesCsv: async () => {
    const aportes = await prisma.aporte.findMany({
      include: { participante: true },
      orderBy: { data: 'asc' },
    });

    const linhas = aportes.map((a) => ({
      data: a.data.toISOString().slice(0, 10),
      socio: a.participante.nome,
      valor: a.valor.toString(),
    }));

    return stringify(linhas, { header: true, columns: ['data', 'socio', 'valor'] });
  },
};
EOF

# --- controllers/exportacao.controller.ts ---
cat > api/src/controllers/exportacao.controller.ts <<'EOF'
import { Request, Response, NextFunction } from 'express';
import { exportacaoService } from '../services/exportacao.service';

export const exportacaoController = {
  notasFiscais: async (_req: Request, res: Response, next: NextFunction) => {
    try {
      const csv = await exportacaoService.notasFiscaisCsv();
      res.header('Content-Type', 'text/csv');
      res.attachment('notas-fiscais.csv');
      res.send(csv);
    } catch (erro) {
      next(erro);
    }
  },

  aportes: async (_req: Request, res: Response, next: NextFunction) => {
    try {
      const csv = await exportacaoService.aportesCsv();
      res.header('Content-Type', 'text/csv');
      res.attachment('aportes.csv');
      res.send(csv);
    } catch (erro) {
      next(erro);
    }
  },
};
EOF

# --- routes/exportacao.routes.ts ---
cat > api/src/routes/exportacao.routes.ts <<'EOF'
import { Router } from 'express';
import { autenticar } from '../middlewares/auth';
import { exportacaoController } from '../controllers/exportacao.controller';

export const exportacaoRouter = Router();

exportacaoRouter.use(autenticar);
exportacaoRouter.get('/notas-fiscais.csv', exportacaoController.notasFiscais);
exportacaoRouter.get('/aportes.csv', exportacaoController.aportes);
EOF

# --- server.ts (monta as rotas da fase 4) ---
cat > api/src/server.ts <<'EOF'
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import pinoHttp from 'pino-http';
import { env } from './config/env';
import { logger } from './lib/logger';
import { authRouter } from './routes/auth.routes';
import { categoriasRouter } from './routes/categorias.routes';
import { participantesRouter } from './routes/participantes.routes';
import { aportesRouter } from './routes/aportes.routes';
import { notasFiscaisRouter } from './routes/notasFiscais.routes';
import { webhooksRouter } from './routes/webhooks.routes';
import { conciliacaoRouter } from './routes/conciliacao.routes';
import { exportacaoRouter } from './routes/exportacao.routes';
import { errorHandler } from './middlewares/errorHandler';

const app = express();

app.use(helmet());
app.use(cors({ origin: true, credentials: true }));
app.use(cookieParser());
app.use(express.json());
app.use(pinoHttp({ logger }));

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.use('/auth', authRouter);
app.use('/categorias', categoriasRouter);
app.use('/participantes', participantesRouter);
app.use('/aportes', aportesRouter);
app.use('/notas-fiscais', notasFiscaisRouter);
app.use('/webhooks', webhooksRouter);
app.use('/conciliacao', conciliacaoRouter);
app.use('/export', exportacaoRouter);

app.use(errorHandler);

app.listen(Number(env.PORT), () => {
  logger.info(`API rodando na porta ${env.PORT}`);
});
EOF

echo "Arquivos da Fase 4 gerados em ${PROJETO}/api"

read -p "Fazer commit da Fase 4 agora? (s/n) " resposta
if [[ "$resposta" == "s" ]]; then
  git add .
  git commit -q -m "feat: webhooks WhatsApp/Sheets via n8n, conciliacao bancaria e exportacao CSV"
  echo "Commit da Fase 4 criado."
fi