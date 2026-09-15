#!/usr/bin/env bash
# Depois de rodar: npm run prisma:migrate (ou npx prisma migrate dev --name init se ainda não tiver migração) para criar as tabelas, e testar as rotas com o cookie de sessão do login.

set -euo pipefail

PROJETO="obra-ipiranga"

if [[ ! -d "${PROJETO}/api/src" ]]; then
  echo "Estrutura da api não encontrada. Rode setup-fase1.sh e setup-fase2.sh primeiro."
  exit 1
fi

cd "${PROJETO}"

echo "Escrevendo arquivos da Fase 3..."

# --- lib/errors.ts (adiciona NotFoundError) ---
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

export class NotFoundError extends AppError {
  constructor(message = 'Registro não encontrado.') {
    super(message, 404);
    this.name = 'NotFoundError';
  }
}
EOF

# --- lib/pagination.ts ---
cat > api/src/lib/pagination.ts <<'EOF'
export function parsePaginacao(query: Record<string, unknown>) {
  const page = Math.max(1, Number(query.page) || 1);
  const pageSize = Math.min(100, Math.max(1, Number(query.pageSize) || 20));
  return { page, pageSize, skip: (page - 1) * pageSize, take: pageSize };
}
EOF

# --- schemas/categoria.schema.ts ---
cat > api/src/schemas/categoria.schema.ts <<'EOF'
import { z } from 'zod';

export const criarCategoriaSchema = z.object({
  body: z.object({
    nome: z.string().min(1, 'Informe o nome da categoria.'),
    etapa: z.string().optional(),
  }),
});

export const atualizarCategoriaSchema = z.object({
  params: z.object({ id: z.coerce.number().int() }),
  body: z.object({
    nome: z.string().min(1).optional(),
    etapa: z.string().optional(),
  }),
});

export const idParamSchema = z.object({
  params: z.object({ id: z.coerce.number().int() }),
});
EOF

# --- schemas/participante.schema.ts ---
cat > api/src/schemas/participante.schema.ts <<'EOF'
import { z } from 'zod';

const cpfRegex = /^\d{3}\.?\d{3}\.?\d{3}-?\d{2}$/;

export const criarParticipanteSchema = z.object({
  body: z.object({
    nome: z.string().min(1, 'Informe o nome do sócio.'),
    cpf: z.string().regex(cpfRegex, 'CPF inválido.'),
    chavePix: z.string().optional(),
  }),
});

export const atualizarParticipanteSchema = z.object({
  params: z.object({ id: z.coerce.number().int() }),
  body: z.object({
    nome: z.string().min(1).optional(),
    cpf: z.string().regex(cpfRegex, 'CPF inválido.').optional(),
    chavePix: z.string().optional(),
  }),
});
EOF

# --- schemas/aporte.schema.ts ---
cat > api/src/schemas/aporte.schema.ts <<'EOF'
import { z } from 'zod';

export const criarAporteSchema = z.object({
  body: z.object({
    obraId: z.coerce.number().int(),
    participanteId: z.coerce.number().int(),
    data: z.coerce.date(),
    valor: z.coerce.number().positive('O valor deve ser maior que zero.'),
  }),
});

export const atualizarAporteSchema = z.object({
  params: z.object({ id: z.coerce.number().int() }),
  body: z.object({
    participanteId: z.coerce.number().int().optional(),
    data: z.coerce.date().optional(),
    valor: z.coerce.number().positive().optional(),
  }),
});

export const listarAportesSchema = z.object({
  query: z.object({
    participanteId: z.coerce.number().int().optional(),
    dataInicio: z.coerce.date().optional(),
    dataFim: z.coerce.date().optional(),
    page: z.coerce.number().int().optional(),
    pageSize: z.coerce.number().int().optional(),
  }),
});
EOF

# --- schemas/notaFiscal.schema.ts ---
cat > api/src/schemas/notaFiscal.schema.ts <<'EOF'
import { z } from 'zod';

export const criarNotaFiscalSchema = z.object({
  body: z.object({
    obraId: z.coerce.number().int(),
    fornecedorNome: z.string().min(1, 'Informe o nome do fornecedor.'),
    numeroNota: z.string().optional(),
    chaveAcesso: z.string().length(44).optional(),
    dataEmissao: z.coerce.date().optional(),
    valorTotal: z.coerce.number().positive('O valor deve ser maior que zero.'),
    categoriaId: z.coerce.number().int().optional(),
    cpfDestinatario: z.string().optional(),
    imagemUrl: z.string().url().optional(),
    origem: z.enum(['whatsapp', 'upload_web', 'planilha']).default('upload_web'),
  }),
});

export const atualizarNotaFiscalSchema = z.object({
  params: z.object({ id: z.coerce.number().int() }),
  body: z.object({
    fornecedorNome: z.string().min(1).optional(),
    numeroNota: z.string().optional(),
    dataEmissao: z.coerce.date().optional(),
    valorTotal: z.coerce.number().positive().optional(),
    categoriaId: z.coerce.number().int().nullable().optional(),
    participanteId: z.coerce.number().int().nullable().optional(),
    status: z.enum(['pendente_revisao', 'confirmada']).optional(),
  }),
});

export const listarNotasFiscaisSchema = z.object({
  query: z.object({
    participanteId: z.coerce.number().int().optional(),
    categoriaId: z.coerce.number().int().optional(),
    status: z.enum(['pendente_revisao', 'confirmada']).optional(),
    dataInicio: z.coerce.date().optional(),
    dataFim: z.coerce.date().optional(),
    page: z.coerce.number().int().optional(),
    pageSize: z.coerce.number().int().optional(),
  }),
});
EOF

# --- services/categoria.service.ts ---
cat > api/src/services/categoria.service.ts <<'EOF'
import { prisma } from '../lib/prisma';
import { NotFoundError } from '../lib/errors';

export const categoriaService = {
  listar: () => prisma.categoria.findMany({ orderBy: { nome: 'asc' } }),

  criar: (dados: { nome: string; etapa?: string }) =>
    prisma.categoria.create({ data: dados }),

  atualizar: async (id: number, dados: { nome?: string; etapa?: string }) => {
    const existente = await prisma.categoria.findUnique({ where: { id } });
    if (!existente) throw new NotFoundError('Categoria não encontrada.');
    return prisma.categoria.update({ where: { id }, data: dados });
  },

  remover: async (id: number) => {
    const existente = await prisma.categoria.findUnique({ where: { id } });
    if (!existente) throw new NotFoundError('Categoria não encontrada.');
    return prisma.categoria.delete({ where: { id } });
  },
};
EOF

# --- services/participante.service.ts ---
cat > api/src/services/participante.service.ts <<'EOF'
import { prisma } from '../lib/prisma';
import { NotFoundError, AppError } from '../lib/errors';

function normalizarCpf(cpf: string) {
  return cpf.replace(/\D/g, '');
}

export const participanteService = {
  listar: () => prisma.participante.findMany({ orderBy: { nome: 'asc' } }),

  criar: (dados: { nome: string; cpf: string; chavePix?: string }) =>
    prisma.participante.create({
      data: { ...dados, cpf: normalizarCpf(dados.cpf) },
    }),

  atualizar: async (id: number, dados: { nome?: string; cpf?: string; chavePix?: string }) => {
    const existente = await prisma.participante.findUnique({ where: { id } });
    if (!existente) throw new NotFoundError('Sócio não encontrado.');
    return prisma.participante.update({
      where: { id },
      data: { ...dados, cpf: dados.cpf ? normalizarCpf(dados.cpf) : undefined },
    });
  },

  remover: async (id: number) => {
    const existente = await prisma.participante.findUnique({ where: { id } });
    if (!existente) throw new NotFoundError('Sócio não encontrado.');

    const emUso = await prisma.notaFiscal.count({ where: { participanteId: id } });
    if (emUso > 0) {
      throw new AppError('Não é possível remover um sócio com notas fiscais vinculadas.', 409);
    }

    return prisma.participante.delete({ where: { id } });
  },

  buscarPorCpf: (cpf: string) =>
    prisma.participante.findUnique({ where: { cpf: normalizarCpf(cpf) } }),
};
EOF

# --- services/aporte.service.ts ---
cat > api/src/services/aporte.service.ts <<'EOF'
import { prisma } from '../lib/prisma';
import { NotFoundError } from '../lib/errors';
import { parsePaginacao } from '../lib/pagination';
import { alertasQueue } from '../lib/queue';

interface FiltrosAporte {
  participanteId?: number;
  dataInicio?: Date;
  dataFim?: Date;
  page?: number;
  pageSize?: number;
}

export const aporteService = {
  listar: async (filtros: FiltrosAporte) => {
    const { page, pageSize, skip, take } = parsePaginacao(filtros);

    const where = {
      participanteId: filtros.participanteId,
      data:
        filtros.dataInicio || filtros.dataFim
          ? { gte: filtros.dataInicio, lte: filtros.dataFim }
          : undefined,
    };

    const [dados, total] = await Promise.all([
      prisma.aporte.findMany({
        where,
        include: { participante: true },
        orderBy: { data: 'desc' },
        skip,
        take,
      }),
      prisma.aporte.count({ where }),
    ]);

    return { dados, total, page, pageSize };
  },

  criar: async (dados: { obraId: number; participanteId: number; data: Date; valor: number }) => {
    const aporte = await prisma.aporte.create({ data: dados, include: { participante: true } });

    await alertasQueue.add('novo-aporte', {
      tipo: 'aporte',
      origem: 'site',
      referenciaTabela: 'aportes',
      referenciaId: aporte.id,
      mensagem: `Novo aporte de ${aporte.participante.nome}: R$ ${aporte.valor}`,
    });

    return aporte;
  },

  atualizar: async (id: number, dados: Partial<{ participanteId: number; data: Date; valor: number }>) => {
    const existente = await prisma.aporte.findUnique({ where: { id } });
    if (!existente) throw new NotFoundError('Aporte não encontrado.');
    return prisma.aporte.update({ where: { id }, data: dados });
  },

  remover: async (id: number) => {
    const existente = await prisma.aporte.findUnique({ where: { id } });
    if (!existente) throw new NotFoundError('Aporte não encontrado.');
    return prisma.aporte.delete({ where: { id } });
  },
};
EOF

# --- services/notaFiscal.service.ts ---
cat > api/src/services/notaFiscal.service.ts <<'EOF'
import { prisma } from '../lib/prisma';
import { NotFoundError } from '../lib/errors';
import { parsePaginacao } from '../lib/pagination';
import { alertasQueue } from '../lib/queue';
import { participanteService } from './participante.service';

interface FiltrosNota {
  participanteId?: number;
  categoriaId?: number;
  status?: 'pendente_revisao' | 'confirmada';
  dataInicio?: Date;
  dataFim?: Date;
  page?: number;
  pageSize?: number;
}

interface CriarNotaInput {
  obraId: number;
  fornecedorNome: string;
  numeroNota?: string;
  chaveAcesso?: string;
  dataEmissao?: Date;
  valorTotal: number;
  categoriaId?: number;
  cpfDestinatario?: string;
  imagemUrl?: string;
  origem: 'whatsapp' | 'upload_web' | 'planilha';
}

async function obterOuCriarFornecedor(nome: string) {
  return prisma.fornecedor.upsert({
    where: { nome },
    update: {},
    create: { nome },
  });
}

export const notaFiscalService = {
  listar: async (filtros: FiltrosNota) => {
    const { page, pageSize, skip, take } = parsePaginacao(filtros);

    const where = {
      participanteId: filtros.participanteId,
      categoriaId: filtros.categoriaId,
      status: filtros.status,
      dataEmissao:
        filtros.dataInicio || filtros.dataFim
          ? { gte: filtros.dataInicio, lte: filtros.dataFim }
          : undefined,
    };

    const [dados, total] = await Promise.all([
      prisma.notaFiscal.findMany({
        where,
        include: { fornecedor: true, categoria: true, participante: true },
        orderBy: { dataEmissao: 'desc' },
        skip,
        take,
      }),
      prisma.notaFiscal.count({ where }),
    ]);

    return { dados, total, page, pageSize };
  },

  criar: async (input: CriarNotaInput) => {
    const fornecedor = await obterOuCriarFornecedor(input.fornecedorNome);

    // Regra: CPF do destinatário define o sócio. Sem correspondência, fica pendente.
    let participanteId: number | null = null;
    let status: 'pendente_revisao' | 'confirmada' = 'pendente_revisao';

    if (input.cpfDestinatario) {
      const participante = await participanteService.buscarPorCpf(input.cpfDestinatario);
      if (participante) {
        participanteId = participante.id;
        status = 'confirmada';
      }
    }

    const nota = await prisma.notaFiscal.create({
      data: {
        obraId: input.obraId,
        fornecedorId: fornecedor.id,
        numeroNota: input.numeroNota,
        chaveAcesso: input.chaveAcesso,
        dataEmissao: input.dataEmissao,
        valorTotal: input.valorTotal,
        categoriaId: input.categoriaId,
        categorizadoManualmente: Boolean(input.categoriaId),
        cpfDestinatario: input.cpfDestinatario,
        participanteId,
        imagemUrl: input.imagemUrl,
        status,
        origem: input.origem,
      },
      include: { fornecedor: true, categoria: true, participante: true },
    });

    await alertasQueue.add('nova-nota-fiscal', {
      tipo: 'nota_fiscal',
      origem: input.origem,
      referenciaTabela: 'notas_fiscais',
      referenciaId: nota.id,
      mensagem: `Nova nota de ${fornecedor.nome}: R$ ${nota.valorTotal}${
        participanteId ? '' : ' (pendente de atribuição de sócio)'
      }`,
    });

    return nota;
  },

  atualizar: async (
    id: number,
    dados: Partial<{
      fornecedorNome: string;
      numeroNota: string;
      dataEmissao: Date;
      valorTotal: number;
      categoriaId: number | null;
      participanteId: number | null;
      status: 'pendente_revisao' | 'confirmada';
    }>
  ) => {
    const existente = await prisma.notaFiscal.findUnique({ where: { id } });
    if (!existente) throw new NotFoundError('Nota fiscal não encontrada.');

    let fornecedorId: number | undefined;
    if (dados.fornecedorNome) {
      const fornecedor = await obterOuCriarFornecedor(dados.fornecedorNome);
      fornecedorId = fornecedor.id;
    }

    return prisma.notaFiscal.update({
      where: { id },
      data: {
        fornecedorId,
        numeroNota: dados.numeroNota,
        dataEmissao: dados.dataEmissao,
        valorTotal: dados.valorTotal,
        categoriaId: dados.categoriaId,
        categorizadoManualmente: dados.categoriaId !== undefined ? true : undefined,
        participanteId: dados.participanteId,
        status: dados.status,
      },
      include: { fornecedor: true, categoria: true, participante: true },
    });
  },

  remover: async (id: number) => {
    const existente = await prisma.notaFiscal.findUnique({ where: { id } });
    if (!existente) throw new NotFoundError('Nota fiscal não encontrada.');
    return prisma.notaFiscal.delete({ where: { id } });
  },
};
EOF

# --- controllers ---
cat > api/src/controllers/categoria.controller.ts <<'EOF'
import { Request, Response, NextFunction } from 'express';
import { categoriaService } from '../services/categoria.service';

export const categoriaController = {
  listar: async (_req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await categoriaService.listar());
    } catch (erro) {
      next(erro);
    }
  },
  criar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.status(201).json(await categoriaService.criar(req.body));
    } catch (erro) {
      next(erro);
    }
  },
  atualizar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await categoriaService.atualizar(Number(req.params.id), req.body));
    } catch (erro) {
      next(erro);
    }
  },
  remover: async (req: Request, res: Response, next: NextFunction) => {
    try {
      await categoriaService.remover(Number(req.params.id));
      res.status(204).send();
    } catch (erro) {
      next(erro);
    }
  },
};
EOF

cat > api/src/controllers/participante.controller.ts <<'EOF'
import { Request, Response, NextFunction } from 'express';
import { participanteService } from '../services/participante.service';

export const participanteController = {
  listar: async (_req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await participanteService.listar());
    } catch (erro) {
      next(erro);
    }
  },
  criar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.status(201).json(await participanteService.criar(req.body));
    } catch (erro) {
      next(erro);
    }
  },
  atualizar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await participanteService.atualizar(Number(req.params.id), req.body));
    } catch (erro) {
      next(erro);
    }
  },
  remover: async (req: Request, res: Response, next: NextFunction) => {
    try {
      await participanteService.remover(Number(req.params.id));
      res.status(204).send();
    } catch (erro) {
      next(erro);
    }
  },
};
EOF

cat > api/src/controllers/aporte.controller.ts <<'EOF'
import { Request, Response, NextFunction } from 'express';
import { aporteService } from '../services/aporte.service';

export const aporteController = {
  listar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await aporteService.listar(req.query as any));
    } catch (erro) {
      next(erro);
    }
  },
  criar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.status(201).json(await aporteService.criar(req.body));
    } catch (erro) {
      next(erro);
    }
  },
  atualizar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await aporteService.atualizar(Number(req.params.id), req.body));
    } catch (erro) {
      next(erro);
    }
  },
  remover: async (req: Request, res: Response, next: NextFunction) => {
    try {
      await aporteService.remover(Number(req.params.id));
      res.status(204).send();
    } catch (erro) {
      next(erro);
    }
  },
};
EOF

cat > api/src/controllers/notaFiscal.controller.ts <<'EOF'
import { Request, Response, NextFunction } from 'express';
import { notaFiscalService } from '../services/notaFiscal.service';

export const notaFiscalController = {
  listar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await notaFiscalService.listar(req.query as any));
    } catch (erro) {
      next(erro);
    }
  },
  criar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.status(201).json(await notaFiscalService.criar(req.body));
    } catch (erro) {
      next(erro);
    }
  },
  atualizar: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await notaFiscalService.atualizar(Number(req.params.id), req.body));
    } catch (erro) {
      next(erro);
    }
  },
  remover: async (req: Request, res: Response, next: NextFunction) => {
    try {
      await notaFiscalService.remover(Number(req.params.id));
      res.status(204).send();
    } catch (erro) {
      next(erro);
    }
  },
};
EOF

# --- routes ---
cat > api/src/routes/categorias.routes.ts <<'EOF'
import { Router } from 'express';
import { autenticar } from '../middlewares/auth';
import { validar } from '../middlewares/validate';
import { categoriaController } from '../controllers/categoria.controller';
import { criarCategoriaSchema, atualizarCategoriaSchema, idParamSchema } from '../schemas/categoria.schema';

export const categoriasRouter = Router();

categoriasRouter.use(autenticar);
categoriasRouter.get('/', categoriaController.listar);
categoriasRouter.post('/', validar(criarCategoriaSchema), categoriaController.criar);
categoriasRouter.patch('/:id', validar(atualizarCategoriaSchema), categoriaController.atualizar);
categoriasRouter.delete('/:id', validar(idParamSchema), categoriaController.remover);
EOF

cat > api/src/routes/participantes.routes.ts <<'EOF'
import { Router } from 'express';
import { autenticar, exigirPapel } from '../middlewares/auth';
import { validar } from '../middlewares/validate';
import { participanteController } from '../controllers/participante.controller';
import { criarParticipanteSchema, atualizarParticipanteSchema } from '../schemas/participante.schema';

export const participantesRouter = Router();

participantesRouter.use(autenticar);
participantesRouter.get('/', participanteController.listar);
participantesRouter.post('/', exigirPapel('admin'), validar(criarParticipanteSchema), participanteController.criar);
participantesRouter.patch('/:id', exigirPapel('admin'), validar(atualizarParticipanteSchema), participanteController.atualizar);
participantesRouter.delete('/:id', exigirPapel('admin'), participanteController.remover);
EOF

cat > api/src/routes/aportes.routes.ts <<'EOF'
import { Router } from 'express';
import { autenticar } from '../middlewares/auth';
import { validar } from '../middlewares/validate';
import { aporteController } from '../controllers/aporte.controller';
import { criarAporteSchema, atualizarAporteSchema, listarAportesSchema } from '../schemas/aporte.schema';

export const aportesRouter = Router();

aportesRouter.use(autenticar);
aportesRouter.get('/', validar(listarAportesSchema), aporteController.listar);
aportesRouter.post('/', validar(criarAporteSchema), aporteController.criar);
aportesRouter.patch('/:id', validar(atualizarAporteSchema), aporteController.atualizar);
aportesRouter.delete('/:id', aporteController.remover);
EOF

cat > api/src/routes/notasFiscais.routes.ts <<'EOF'
import { Router } from 'express';
import { autenticar } from '../middlewares/auth';
import { validar } from '../middlewares/validate';
import { notaFiscalController } from '../controllers/notaFiscal.controller';
import {
  criarNotaFiscalSchema,
  atualizarNotaFiscalSchema,
  listarNotasFiscaisSchema,
} from '../schemas/notaFiscal.schema';

export const notasFiscaisRouter = Router();

notasFiscaisRouter.use(autenticar);
notasFiscaisRouter.get('/', validar(listarNotasFiscaisSchema), notaFiscalController.listar);
notasFiscaisRouter.post('/', validar(criarNotaFiscalSchema), notaFiscalController.criar);
notasFiscaisRouter.patch('/:id', validar(atualizarNotaFiscalSchema), notaFiscalController.atualizar);
notasFiscai