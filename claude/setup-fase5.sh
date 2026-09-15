#!/usr/bin/env bash
# Com isso, as cinco fases fecham o sistema completo: infraestrutura, autenticação, CRUD com rateio por CPF, integrações/conciliação, e agora o frontend. Como você pediu no início, cabe agora rodar um pentest antes de considerar isso padrão — quer que eu monte o checklist de segurança para revisar (JWT, CORS, cookies, validação, upload de arquivos) antes de ir para produção?

set -euo pipefail

PROJETO="obra-ipiranga"

if [[ ! -d "${PROJETO}/api/src" ]]; then
  echo "Estrutura da api não encontrada. Rode as fases 1 a 4 primeiro."
  exit 1
fi

cd "${PROJETO}"

echo "== Parte 1: endpoints de dashboard no backend =="

# --- services/dashboard.service.ts ---
cat > api/src/services/dashboard.service.ts <<'EOF'
import { prisma } from '../lib/prisma';

export const dashboardService = {
  resumoGeral: async (obraId: number) => {
    const obra = await prisma.obra.findUnique({ where: { id: obraId } });
    const [gastos, aportes] = await Promise.all([
      prisma.notaFiscal.aggregate({ where: { obraId }, _sum: { valorTotal: true } }),
      prisma.aporte.aggregate({ where: { obraId }, _sum: { valor: true } }),
    ]);

    const realizado = Number(gastos._sum.valorTotal ?? 0);
    const totalAportado = Number(aportes._sum.valor ?? 0);

    return {
      orcado: Number(obra?.valorOrcado ?? 0),
      realizado,
      saldoCaixa: totalAportado - realizado,
    };
  },

  porSocio: async (obraId: number) => {
    const participantes = await prisma.participante.findMany();

    return Promise.all(
      participantes.map(async (p) => {
        const [gasto, aportado] = await Promise.all([
          prisma.notaFiscal.aggregate({
            where: { obraId, participanteId: p.id },
            _sum: { valorTotal: true },
          }),
          prisma.aporte.aggregate({
            where: { obraId, participanteId: p.id },
            _sum: { valor: true },
          }),
        ]);

        const totalGasto = Number(gasto._sum.valorTotal ?? 0);
        const totalAportado = Number(aportado._sum.valor ?? 0);

        return {
          participanteId: p.id,
          nome: p.nome,
          aportado: totalAportado,
          gasto: totalGasto,
          saldo: totalAportado - totalGasto,
        };
      })
    );
  },

  porCategoria: async (obraId: number) => {
    const categorias = await prisma.categoria.findMany();

    return Promise.all(
      categorias.map(async (c) => {
        const soma = await prisma.notaFiscal.aggregate({
          where: { obraId, categoriaId: c.id },
          _sum: { valorTotal: true },
        });
        return { categoriaId: c.id, nome: c.nome, realizado: Number(soma._sum.valorTotal ?? 0) };
      })
    );
  },

  porPeriodo: async (obraId: number) => {
    const notas = await prisma.notaFiscal.findMany({
      where: { obraId, dataEmissao: { not: null } },
      select: { dataEmissao: true, valorTotal: true },
    });
    const aportes = await prisma.aporte.findMany({
      where: { obraId },
      select: { data: true, valor: true },
    });

    const meses: Record<string, { gasto: number; aporte: number }> = {};

    for (const n of notas) {
      const chave = n.dataEmissao!.toISOString().slice(0, 7);
      meses[chave] ??= { gasto: 0, aporte: 0 };
      meses[chave].gasto += Number(n.valorTotal);
    }

    for (const a of aportes) {
      const chave = a.data.toISOString().slice(0, 7);
      meses[chave] ??= { gasto: 0, aporte: 0 };
      meses[chave].aporte += Number(a.valor);
    }

    return Object.entries(meses)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([mes, valores]) => ({ mes, ...valores }));
  },
};
EOF

# --- controllers/dashboard.controller.ts ---
cat > api/src/controllers/dashboard.controller.ts <<'EOF'
import { Request, Response, NextFunction } from 'express';
import { dashboardService } from '../services/dashboard.service';

function obraIdDaQuery(req: Request) {
  return Number(req.query.obraId ?? 1);
}

export const dashboardController = {
  geral: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await dashboardService.resumoGeral(obraIdDaQuery(req)));
    } catch (erro) {
      next(erro);
    }
  },
  porSocio: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await dashboardService.porSocio(obraIdDaQuery(req)));
    } catch (erro) {
      next(erro);
    }
  },
  porCategoria: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await dashboardService.porCategoria(obraIdDaQuery(req)));
    } catch (erro) {
      next(erro);
    }
  },
  porPeriodo: async (req: Request, res: Response, next: NextFunction) => {
    try {
      res.json(await dashboardService.porPeriodo(obraIdDaQuery(req)));
    } catch (erro) {
      next(erro);
    }
  },
};
EOF

# --- routes/dashboard.routes.ts ---
cat > api/src/routes/dashboard.routes.ts <<'EOF'
import { Router } from 'express';
import { autenticar } from '../middlewares/auth';
import { dashboardController } from '../controllers/dashboard.controller';

export const dashboardRouter = Router();

dashboardRouter.use(autenticar);
dashboardRouter.get('/geral', dashboardController.geral);
dashboardRouter.get('/por-socio', dashboardController.porSocio);
dashboardRouter.get('/por-categoria', dashboardController.porCategoria);
dashboardRouter.get('/por-periodo', dashboardController.porPeriodo);
EOF

# --- routes/auth.routes.ts (ajusta cookie para funcionar entre subdominios) ---
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
  domain: process.env.NODE_ENV === 'production' ? '.iastudio.shop' : undefined,
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

# --- server.ts (monta dashboard.routes) ---
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
import { dashboardRouter } from './routes/dashboard.routes';
import { errorHandler } from './middlewares/errorHandler';

const app = express();

app.use(helmet());
app.use(
  cors({
    origin: ['https://obra.iastudio.shop', 'http://localhost:3001'],
    credentials: true,
  })
);
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
app.use('/dashboard', dashboardRouter);

app.use(errorHandler);

app.listen(Number(env.PORT), () => {
  logger.info(`API rodando na porta ${env.PORT}`);
});
EOF

echo "== Parte 2: frontend Next.js =="

cat > web/package.json <<'EOF'
{
  "name": "obra-web",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev -p 3001",
    "build": "next build",
    "start": "next start -p 3000"
  },
  "dependencies": {
    "next": "^14.2.13",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "recharts": "^2.12.7",
    "lucide-react": "^0.445.0"
  },
  "devDependencies": {
    "typescript": "^5.5.4",
    "@types/react": "^18.3.5",
    "@types/node": "^20.14.15",
    "tailwindcss": "^3.4.10",
    "postcss": "^8.4.45",
    "autoprefixer": "^10.4.20"
  }
}
EOF

cat > web/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": false,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules"]
}
EOF

cat > web/next.config.js <<'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = { reactStrictMode: true };
module.exports = nextConfig;
EOF

cat > web/tailwind.config.ts <<'EOF'
import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        border: '#e4e2da',
        surface1: '#f5f4ef',
        surface2: '#ffffff',
        textSecondary: '#6b6a63',
        elismar: '#185FA5',
        miquelangelo: '#993C1D',
      },
    },
  },
  plugins: [],
};
export default config;
EOF

cat > web/postcss.config.js <<'EOF'
module.exports = {
  plugins: { tailwindcss: {}, autoprefixer: {} },
};
EOF

cat > web/Dockerfile <<'EOF'
FROM node:20-alpine AS base
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "start"]
EOF

mkdir -p web/src/lib web/src/components

cat > web/src/app/globals.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  background: #f5f4ef;
  color: #1a1a18;
}
EOF

cat > web/src/lib/api.ts <<'EOF'
const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3000';

async function request(caminho: string, opcoes: RequestInit = {}) {
  const resposta = await fetch(`${API_URL}${caminho}`, {
    ...opcoes,
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', ...opcoes.headers },
  });

  if (!resposta.ok) {
    const erro = await resposta.json().catch(() => ({ erro: 'Erro desconhecido.' }));
    throw new Error(erro.erro ?? `Erro ${resposta.status}`);
  }

  if (resposta.status === 204) return null;
  return resposta.json();
}

export const api = {
  get: (caminho: string) => request(caminho),
  post: (caminho: string, body: unknown) =>
    request(caminho, { method: 'POST', body: JSON.stringify(body) }),
  patch: (caminho: string, body: unknown) =>
    request(caminho, { method: 'PATCH', body: JSON.stringify(body) }),
  delete: (caminho: string) => request(caminho, { method: 'DELETE' }),
};
EOF

cat > web/src/middleware.ts <<'EOF'
import { NextRequest, NextResponse } from 'next/server';

const ROTAS_PROTEGIDAS = ['/dashboard', '/dados', '/cadastros'];

export function middleware(req: NextRequest) {
  const temSessao = req.cookies.has('token');
  const rotaProtegida = ROTAS_PROTEGIDAS.some((r) => req.nextUrl.pathname.startsWith(r));

  if (rotaProtegida && !temSessao) {
    return NextResponse.redirect(new URL('/login', req.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/dashboard/:path*', '/dados/:path*', '/cadastros/:path*'],
};
EOF

cat > web/src/app/layout.tsx <<'EOF'
import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Obra Ipiranga 1',
  description: 'Gestão financeira da obra',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
EOF

cat > web/src/app/page.tsx <<'EOF'
import { redirect } from 'next/navigation';

export default function Home() {
  redirect('/dashboard/por-socio');
}
EOF

cat > web/src/app/login/page.tsx <<'EOF'
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Building2 } from 'lucide-react';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState('');
  const [carregando, setCarregando] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErro('');
    setCarregando(true);

    try {
      const API_URL = process.env.NEXT_PUBLIC_API_URL;
      const resposta = await fetch(`${API_URL}/auth/login`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, senha }),
      });

      if (!resposta.ok) {
        const dados = await resposta.json().catch(() => ({}));
        throw new Error(dados.erro ?? 'E-mail ou senha incorretos.');
      }

      router.push('/dashboard/por-socio');
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível entrar.');
    } finally {
      setCarregando(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-surface1 px-4">
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-sm bg-surface2 border border-border rounded-xl p-8"
      >
        <div className="w-10 h-10 rounded-lg bg-black flex items-center justify-center mx-auto mb-4">
          <Building2 className="text-white" size={20} />
        </div>
        <p className="text-center font-medium mb-1">Obra Ipiranga 1</p>
        <p className="text-center text-sm text-textSecondary mb-6">Entre com sua conta</p>

        <label className="block text-xs text-textSecondary mb-1">E-mail</label>
        <input
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="nome@exemplo.com"
          className="w-full border border-border rounded-md px-3 py-2 mb-4 text-sm"
        />

        <label className="block text-xs text-textSecondary mb-1">Senha</label>
        <input
          type="password"
          required
          value={senha}
          onChange={(e) => setSenha(e.target.value)}
          placeholder="••••••••"
          className="w-full border border-border rounded-md px-3 py-2 mb-4 text-sm"
        />

        {erro && <p className="text-sm text-red-600 mb-4">{erro}</p>}

        <button
          type="submit"
          disabled={carregando}
          className="w-full bg-black text-white rounded-md py-2 text-sm font-medium disabled:opacity-60"
        >
          {carregando ? 'Entrando...' : 'Entrar'}
        </button>
      </form>
    </div>
  );
}
EOF

cat > web/src/components/Sidebar.tsx <<'EOF'
'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  LayoutDashboard,
  Users,
  Tag,
  CalendarRange,
  Table,
  FolderCog,
} from 'lucide-react';

const ITENS_DASHBOARD = [
  { href: '/dashboard/por-socio', label: 'Por sócio', icon: Users },
  { href: '/dashboard/geral', label: 'Visão geral', icon: LayoutDashboard },
  { href: '/dashboard/por-categoria', label: 'Por categoria', icon: Tag },
  { href: '/dashboard/por-periodo', label: 'Por período', icon: CalendarRange },
];

const ITENS_DADOS = [
  { href: '/dados', label: 'Tabela de dados', icon: Table },
  { href: '/cadastros', label: 'Cadastros', icon: FolderCog },
];

function Item({ href, label, icon: Icon }: { href: string; label: string; icon: any }) {
  const pathname = usePathname();
  const ativo = pathname === href;

  return (
    <Link
      href={href}
      className={`flex items-center gap-2 px-3.5 py-2 text-sm rounded-md mx-2 ${
        ativo ? 'bg-black/5 font-medium' : 'text-textSecondary hover:bg-black/5'
      }`}
    >
      <Icon size={16} />
      {label}
    </Link>
  );
}

export function Sidebar() {
  return (
    <aside className="w-[160px] shrink-0 border-r border-border py-3">
      <p className="text-[11px] text-textSecondary px-5 mb-1">Dashboards</p>
      <nav className="flex flex-col gap-0.5 mb-4">
        {ITENS_DASHBOARD.map((item) => (
          <Item key={item.href} {...item} />
        ))}
      </nav>
      <p className="text-[11px] text-textSecondary px-5 mb-1">Dados</p>
      <nav className="flex flex-col gap-0.5">
        {ITENS_DADOS.map((item) => (
          <Item key={item.href} {...item} />
        ))}
      </nav>
    </aside>
  );
}
EOF

cat > web/src/components/Topbar.tsx <<'EOF'
'use client';

import { useRouter } from 'next/navigation';
import { Building2, LogOut } from 'lucide-react';

export function Topbar() {
  const router = useRouter();

  async function sair() {
    const API_URL = process.env.NEXT_PUBLIC_API_URL;
    await fetch(`${API_URL}/auth/logout`, { method: 'POST', credentials: 'include' });
    router.push('/login');
  }

  return (
    <div className="flex items-center justify-between px-4.5 py-3 border-b border-border bg-surface1">
      <span className="flex items-center gap-2 text-sm font-medium">
        <Building2 size={16} />
        Obra Ipiranga 1
      </span>
      <button onClick={sair} className="flex items-center gap-1.5 text-xs text-textSecondary">
        <LogOut size={14} />
        Sair
      </button>
    </div>
  );
}
EOF

cat > web/src/app/dashboard/layout.tsx <<'EOF'
import { Sidebar } from '@/components/Sidebar';
import { Topbar } from '@/components/Topbar';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="border border-border rounded-xl overflow-hidden m-4">
      <Topbar />
      <div className="flex min-h-[500px]">
        <Sidebar />
        <main className="flex-1 p-4.5 min-w-0">{children}</main>
      </div>
    </div>
  );
}
EOF

cat > web/src/components/MetricCard.tsx <<'EOF'
export function MetricCard({ label, valor }: { label: string; valor: string }) {
  return (
    <div className="bg-surface1 rounded-md p-3">
      <p className="text-xs text-textSecondary mb-1">{label}</p>
      <p className="text-lg font-medium">{valor}</p>
    </div>
  );
}

export function formatarMoeda(valor: number) {
  return valor.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}
EOF

cat > web/src/app/dashboard/geral/page.tsx <<'EOF'
'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { MetricCard, formatarMoeda } from '@/components/MetricCard';

interface Resumo {
  orcado: number;
  realizado: number;
  saldoCaixa: number;
}

export default function VisaoGeralPage() {
  const [resumo, setResumo] = useState<Resumo | null>(null);

  useEffect(() => {
    api.get('/dashboard/geral?obraId=1').then(setResumo).catch(console.error);
  }, []);

  if (!resumo) return <p className="text-sm text-textSecondary">Carregando...</p>;

  return (
    <div>
      <p className="text-sm text-textSecondary mb-3">Visão geral</p>
      <div className="grid grid-cols-3 gap-3">
        <MetricCard label="Orçado" valor={formatarMoeda(resumo.orcado)} />
        <MetricCard label="Realizado" valor={formatarMoeda(resumo.realizado)} />
        <MetricCard label="Saldo em caixa" valor={formatarMoeda(resumo.saldoCaixa)} />
      </div>
    </div>
  );
}
EOF

cat > web/src/app/dashboard/por-socio/page.tsx <<'EOF'
'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { formatarMoeda } from '@/components/MetricCard';

interface LinhaSocio {
  participanteId: number;
  nome: string;
  aportado: number;
  gasto: number;
  saldo: number;
}

function CardSocio({ socio, cor }: { socio: LinhaSocio; cor: string }) {
  return (
    <div className="border border-border rounded-r-md p-3.5" style={{ borderLeft: `3px solid ${cor}` }}>
      <p className="text-sm font-medium mb-3">{socio.nome}</p>
      <div className="flex justify-between text-xs text-textSecondary mb-2">
        <span>Aportado</span>
        <span className="text-black">{formatarMoeda(socio.aportado)}</span>
      </div>
      <div className="flex justify-between text-xs text-textSecondary mb-2">
        <span>Gasto (notas por CPF)</span>
        <span className="text-black">{formatarMoeda(socio.gasto)}</span>
      </div>
      <div className="flex justify-between text-xs text-textSecondary">
        <span>Saldo</span>
        <span className="text-black">{formatarMoeda(socio.saldo)}</span>
      </div>
    </div>
  );
}

const CORES = ['#185FA5', '#993C1D', '#0F6E56', '#854F0B'];

export default function PorSocioPage() {
  const [socios, setSocios] = useState<LinhaSocio[]>([]);

  useEffect(() => {
    api.get('/dashboard/por-socio?obraId=1').then(setSocios).catch(console.error);
  }, []);

  return (
    <div>
      <p className="text-sm text-textSecondary mb-3">Comparativo entre sócios</p>
      <div className="grid grid-cols-2 gap-3.5">
        {socios.map((s, i) => (
          <CardSocio key={s.participanteId} socio={s} cor={CORES[i % CORES.length]} />
        ))}
      </div>
    </div>
  );
}
EOF

cat > web/src/app/dashboard/por-categoria/page.tsx <<'EOF'
'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { formatarMoeda } from '@/components/MetricCard';

interface LinhaCategoria {
  categoriaId: number;
  nome: string;
  realizado: number;
}

export default function PorCategoriaPage() {
  const [categorias, setCategorias] = useState<LinhaCategoria[]>([]);

  useEffect(() => {
    api.get('/dashboard/por-categoria?obraId=1').then(setCategorias).catch(console.error);
  }, []);

  return (
    <div>
      <p className="text-sm text-textSecondary mb-3">Gasto por categoria</p>
      <table className="w-full text-sm">
        <tbody>
          {categorias.map((c) => (
            <tr key={c.categoriaId} className="border-b border-border">
              <td className="py-2">{c.nome}</td>
              <td className="py-2 text-right">{formatarMoeda(c.realizado)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
EOF

cat > web/src/app/dashboard/por-periodo/page.tsx <<'EOF'
'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';

interface LinhaMes {
  mes: string;
  gasto: number;
  aporte: number;
}

export default function PorPeriodoPage() {
  const [dados, setDados] = useState<LinhaMes[]>([]);

  useEffect(() => {
    api.get('/dashboard/por-periodo?obraId=1').then(setDados).catch(console.error);
  }, []);

  return (
    <div>
      <p className="text-sm text-textSecondary mb-3">Evolução mensal</p>
      <div style={{ height: 260 }}>
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={dados}>
            <XAxis dataKey="mes" tick={{ fontSize: 11 }} />
            <YAxis tick={{ fontSize: 11 }} />
            <Tooltip />
            <Bar dataKey="gasto" fill="#993C1D" name="Gastos" />
            <Bar dataKey="aporte" fill="#185FA5" name="Aportes" />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
EOF

cat > web/src/app/dados/page.tsx <<'EOF'
'use client';

import { useEffect, useState, useCallback } from 'react';
import { api } from '@/lib/api';

interface Categoria { id: number; nome: string }
interface Participante { id: number; nome: string }
interface NotaFiscal {
  id: number;
  dataEmissao: string | null;
  fornecedor: { nome: string } | null;
  categoria: Categoria | null;
  participante: Participante | null;
  valorTotal: string;
  status: 'pendente_revisao' | 'confirmada';
}

export default function DadosPage() {
  const [notas, setNotas] = useState<NotaFiscal[]>([]);
  const [categorias, setCategorias] = useState<Categoria[]>([]);
  const [participantes, setParticipantes] = useState<Participante[]>([]);
  const [filtroParticipante, setFiltroParticipante] = useState('');
  const [filtroCategoria, setFiltroCategoria] = useState('');
  const [filtroStatus, setFiltroStatus] = useState('');

  const carregar = useCallback(async () => {
    const params = new URLSearchParams();
    if (filtroParticipante) params.set('participanteId', filtroParticipante);
    if (filtroCategoria) params.set('categoriaId', filtroCategoria);
    if (filtroStatus) params.set('status', filtroStatus);

    const resultado = await api.get(`/notas-fiscais?${params.toString()}`);
    setNotas(resultado.dados);
  }, [filtroParticipante, filtroCategoria, filtroStatus]);

  useEffect(() => {
    api.get('/categorias').then(setCategorias);
    api.get('/participantes').then(setParticipantes);
  }, []);

  useEffect(() => {
    carregar();
  }, [carregar]);

  async function atualizarCampo(id: number, campo: string, valor: string) {
    await api.patch(`/notas-fiscais/${id}`, { [campo]: valor ? Number(valor) : null });
    carregar();
  }

  return (
    <div>
      <div className="flex flex-wrap gap-2.5 mb-3.5">
        <select
          value={filtroParticipante}
          onChange={(e) => setFiltroParticipante(e.target.value)}
          className="border border-border rounded-md px-2 py-1.5 text-sm flex-1 min-w-[130px]"
        >
          <option value="">Todos os sócios</option>
          {participantes.map((p) => (
            <option key={p.id} value={p.id}>{p.nome}</option>
          ))}
        </select>

        <select
          value={filtroCategoria}
          onChange={(e) => setFiltroCategoria(e.target.value)}
          className="border border-border rounded-md px-2 py-1.5 text-sm flex-1 min-w-[130px]"
        >
          <option value="">Todas categorias</option>
          {categorias.map((c) => (
            <option key={c.id} value={c.id}>{c.nome}</option>
          ))}
        </select>

        <select
          value={filtroStatus}
          onChange={(e) => setFiltroStatus(e.target.value)}
          className="border border-border rounded-md px-2 py-1.5 text-sm flex-1 min-w-[130px]"
        >
          <option value="">Todos status</option>
          <option value="confirmada">Confirmada</option>
          <option value="pendente_revisao">Pendente</option>
        </select>
      </div>

      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-border text-textSecondary text-left">
            <th className="py-2 font-normal">Data</th>
            <th className="py-2 font-normal">Fornecedor</th>
            <th className="py-2 font-normal">Categoria</th>
            <th className="py-2 font-normal">Sócio</th>
            <th className="py-2 font-normal">Valor</th>
            <th className="py-2 font-normal">Status</th>
          </tr>
        </thead>
        <tbody>
          {notas.map((n) => (
            <tr key={n.id} className="border-b border-border">
              <td className="py-2">{n.dataEmissao?.slice(0, 10) ?? '-'}</td>
              <td className="py-2">{n.fornecedor?.nome ?? '-'}</td>
              <td className="py-2">
                <select
                  value={n.categoria?.id ?? ''}
                  onChange={(e) => atualizarCampo(n.id, 'categoriaId', e.target.value)}
                  className="border border-border rounded px-1.5 py-1 text-xs"
                >
                  <option value="">Sem categoria</option>
                  {categorias.map((c) => (
                    <option key={c.id} value={c.id}>{c.nome}</option>
                  ))}
                </select>
              </td>
              <td className="py-2">
                <select
                  value={n.participante?.id ?? ''}
                  onChange={(e) => atualizarCampo(n.id, 'participanteId', e.target.value)}
                  className="border border-border rounded px-1.5 py-1 text-xs"
                >
                  <option value="">Sem atribuição</option>
                  {participantes.map((p) => (
                    <option key={p.id} value={p.id}>{p.nome}</option>
                  ))}
                </select>
              </td>
              <td className="py-2">
                {Number(n.valorTotal).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })}
              </td>
              <td className="py-2">
                <span
                  className={`text-xs px-2 py-0.5 rounded ${
                    n.status === 'confirmada' ? 'bg-green-100 text-green-800' : 'bg-amber-100 text-amber-800'
                  }`}
                >
                  {n.status === 'confirmada' ? 'Ok' : 'Pendente'}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
EOF

cat > web/src/app/cadastros/page.tsx <<'EOF'
'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface Participante { id: number; nome: string; cpf: string; chavePix: string | null }
interface Categoria { id: number; nome: string; etapa: string | null }

export default function CadastrosPage() {
  const [participantes, setParticipantes] = useState<Participante[]>([]);
  const [categorias, setCategorias] = useState<Categoria[]>([]);
  const [novoSocio, setNovoSocio] = useState({ nome: '', cpf: '', chavePix: '' });
  const [novaCategoria, setNovaCategoria] = useState({ nome: '', etapa: '' });

  async function carregar() {
    setParticipantes(await api.get('/participantes'));
    setCategorias(await api.get('/categorias'));
  }

  useEffect(() => {
    carregar();
  }, []);

  async function adicionarSocio(e: React.FormEvent) {
    e.preventDefault();
    await api.post('/participantes', novoSocio);
    setNovoSocio({ nome: '', cpf: '', chavePix: '' });
    carregar();
  }

  async function removerSocio(id: number) {
    await api.delete(`/participantes/${id}`);
    carregar();
  }

  async function adicionarCategoria(e: React.FormEvent) {
    e.preventDefault();
    await api.post('/categorias', novaCategoria);
    setNovaCategoria({ nome: '', etapa: '' });
    carregar();
  }

  async function removerCategoria(id: number) {
    await api.delete(`/categorias/${id}`);
    carregar();
  }

  return (
    <div className="grid grid-cols-2 gap-6">
      <div>
        <p className="text-sm font-medium mb-3">Sócios</p>
        <form onSubmit={adicionarSocio} className="flex flex-col gap-2 mb-4">
          <input
            placeholder="Nome"
            value={novoSocio.nome}
            onChange={(e) => setNovoSocio({ ...novoSocio, nome: e.target.value })}
            className="border border-border rounded-md px-2 py-1.5 text-sm"
            required
          />
          <input
            placeholder="CPF"
            value={novoSocio.cpf}
            onChange={(e) => setNovoSocio({ ...novoSocio, cpf: e.target.value })}
            className="border border-border rounded-md px-2 py-1.5 text-sm"
            required
          />
          <input
            placeholder="Chave Pix"
            value={novoSocio.chavePix}
            onChange={(e) => setNovoSocio({ ...novoSocio, chavePix: e.target.value })}
            className="border border-border rounded-md px-2 py-1.5 text-sm"
          />
          <button className="bg-black text-white rounded-md py-1.5 text-sm">Adicionar sócio</button>
        </form>
        <ul className="flex flex-col gap-1.5">
          {participantes.map((p) => (
            <li key={p.id} className="flex justify-between text-sm border-b border-border py-1.5">
              <span>{p.nome} — {p.cpf}</span>
              <button onClick={() => removerSocio(p.id)} className="text-red-600 text-xs">Remover</button>
            </li>
          ))}
        </ul>
      </div>

      <div>
        <p className="text-sm font-medium mb-3">Categorias</p>
        <form onSubmit={adicionarCategoria} className="flex flex-col gap-2 mb-4">
          <input
            placeholder="Nome"
            value={novaCategoria.nome}
            onChange={(e) => setNovaCategoria({ ...novaCategoria, nome: e.target.value })}
            className="border border-border rounded-md px-2 py-1.5 text-sm"
            required
          />
          <input
            placeholder="Etapa"
            value={novaCategoria.etapa}
            onChange={(e) => setNovaCategoria({ ...novaCategoria, etapa: e.target.value })}
            className="border border-border rounded-md px-2 py-1.5 text-sm"
          />
          <button className="bg-black text-white rounded-md py-1.5 text-sm">Adicionar categoria</button>
        </form>
        <ul className="flex flex-col gap-1.5">
          {categorias.map((c) => (
            <li key={c.id} className="flex justify-between text-sm border-b border-border py-1.5">
              <span>{c.nome}{c.etapa ? ` — ${c.etapa}` : ''}</span>
              <button onClick={() => removerCategoria(c.id)} className="text-red-600 text-xs">Remover</button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
EOF

echo "Arquivos da Fase 5 gerados."

read -p "Fazer commit da Fase 5 agora? (s/n) " resposta
if [[ "$resposta" == "s" ]]; then
  git add .
  git commit -q -m "feat: frontend Next.js com login, dashboards, tabela com filtros e cadastros"
  echo "Commit da Fase 5 criado."
fi