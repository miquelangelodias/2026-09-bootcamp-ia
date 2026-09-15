#!/usr/bin/env bash
# Pronto. Depois de rodar, é só editar .env (copiando de .env.example com suas senhas de verdade) antes de subir os containers.
set -euo pipefail

PROJETO="obra-ipiranga"

echo "Criando estrutura em ./${PROJETO}..."

mkdir -p "${PROJETO}"/{api/prisma,api/src/config,api/src/middlewares,api/src/routes,api/src/controllers,api/src/services,api/src/schemas,api/src/jobs,api/src/lib}
mkdir -p "${PROJETO}"/web/src/{app/login,app/dashboard/geral,app/dashboard/por-socio,app/dashboard/por-categoria,app/dashboard/por-periodo,app/dados,app/cadastros,components,lib}

cd "${PROJETO}"

# --- docker-compose.yml ---
cat > docker-compose.yml <<'EOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: obra_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - internal

  redis:
    image: redis:7-alpine
    container_name: obra_redis
    restart: unless-stopped
    volumes:
      - redis_data:/data
    networks:
      - internal

  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    container_name: obra_api
    restart: unless-stopped
    command: ["node", "dist/server.js"]
    depends_on:
      - postgres
      - redis
    env_file: .env
    networks:
      - internal
      - traefik_proxy
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik_proxy
      - traefik.http.routers.obra-api.rule=Host(`api.iastudio.shop`)
      - traefik.http.routers.obra-api.entrypoints=websecure
      - traefik.http.routers.obra-api.tls.certresolver=letsencrypt
      - traefik.http.services.obra-api.loadbalancer.server.port=3000

  worker:
    build:
      context: ./api
      dockerfile: Dockerfile
    container_name: obra_worker
    restart: unless-stopped
    command: ["node", "dist/worker.js"]
    depends_on:
      - postgres
      - redis
    env_file: .env
    networks:
      - internal

  web:
    build:
      context: ./web
      dockerfile: Dockerfile
    container_name: obra_web
    restart: unless-stopped
    depends_on:
      - api
    env_file: .env
    networks:
      - internal
      - traefik_proxy
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik_proxy
      - traefik.http.routers.obra-web.rule=Host(`obra.iastudio.shop`)
      - traefik.http.routers.obra-web.entrypoints=websecure
      - traefik.http.routers.obra-web.tls.certresolver=letsencrypt
      - traefik.http.services.obra-web.loadbalancer.server.port=3000

networks:
  internal:
  traefik_proxy:
    external: true

volumes:
  postgres_data:
  redis_data:
EOF

# --- .env.example ---
cat > .env.example <<'EOF'
# Postgres
POSTGRES_USER=obra_admin
POSTGRES_PASSWORD=troque_essa_senha
POSTGRES_DB=obra_ipiranga
DATABASE_URL=postgresql://obra_admin:troque_essa_senha@postgres:5432/obra_ipiranga

# Redis
REDIS_URL=redis://redis:6379

# JWT
JWT_SECRET=gere_com_openssl_rand_hex_32
JWT_EXPIRES_IN=7d

# Admin inicial (usado pelo seed.ts)
SEED_ADMIN_NAME=Elismar Oliveira Guimarães
SEED_ADMIN_EMAIL=admin@iastudio.shop
SEED_ADMIN_PASSWORD=defina_uma_senha_forte

# Integrações
N8N_WEBHOOK_URL=https://seu-n8n.exemplo.com/webhook/obra
N8N_WEBHOOK_SECRET=gere_outro_segredo
SHEETS_WEBHOOK_SECRET=gere_outro_segredo

# Frontend
NEXT_PUBLIC_API_URL=https://api.iastudio.shop
EOF

# --- .gitignore ---
cat > .gitignore <<'EOF'
.env
node_modules/
dist/
.next/
postgres_data/
redis_data/
EOF

# --- prisma/schema.prisma ---
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
  id             Int          @id @default(autoincrement())
  obraId         Int          @map("obra_id")
  obra           Obra         @relation(fields: [obraId], references: [id])
  participanteId Int          @map("participante_id")
  participante   Participante @relation(fields: [participanteId], references: [id])
  data           DateTime
  valor          Decimal

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

# --- prisma/seed.ts ---
cat > api/prisma/seed.ts <<'EOF'
import { PrismaClient, PapelUsuario } from '@prisma/client';
import bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  const email = process.env.SEED_ADMIN_EMAIL;
  const senha = process.env.SEED_ADMIN_PASSWORD;
  const nome = process.env.SEED_ADMIN_NAME ?? 'Administrador';

  if (!email || !senha) {
    throw new Error('SEED_ADMIN_EMAIL e SEED_ADMIN_PASSWORD são obrigatórios no .env');
  }

  const existente = await prisma.usuario.findUnique({ where: { email } });
  if (existente) {
    console.log(`Usuário admin já existe: ${email}`);
    return;
  }

  const senhaHash = await bcrypt.hash(senha, 12);

  await prisma.usuario.create({
    data: { nome, email, senhaHash, papel: PapelUsuario.admin },
  });

  console.log(`Usuário admin criado: ${email}`);
}

main()
  .catch((erro) => {
    console.error(erro);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
EOF

# --- placeholders da Fase 2 (arquivos vazios, para a árvore já existir) ---
touch api/Dockerfile api/package.json api/tsconfig.json
touch api/src/server.ts api/src/worker.ts
touch api/src/config/env.ts
touch api/src/middlewares/auth.ts api/src/middlewares/errorHandler.ts
touch api/src/routes/auth.routes.ts api/src/routes/notasFiscais.routes.ts api/src/routes/aportes.routes.ts api/src/routes/participantes.routes.ts api/src/routes/categorias.routes.ts api/src/routes/conciliacao.routes.ts api/src/routes/webhooks.routes.ts
touch api/src/lib/prisma.ts api/src/lib/logger.ts

touch web/Dockerfile web/package.json web/next.config.js web/tailwind.config.ts
touch web/src/app/login/page.tsx
touch web/src/app/dashboard/geral/page.tsx web/src/app/dashboard/por-socio/page.tsx web/src/app/dashboard/por-categoria/page.tsx web/src/app/dashboard/por-periodo/page.tsx
touch web/src/app/dados/page.tsx web/src/app/cadastros/page.tsx
touch web/src/lib/api.ts

echo "Estrutura da Fase 1 criada em ./${PROJETO}"

# --- git init e primeiro commit (opcional) ---
read -p "Inicializar git e criar o primeiro commit agora? (s/n) " resposta
if [[ "$resposta" == "s" ]]; then
  git init -q
  git add .
  git commit -q -m "feat: infraestrutura base (docker compose, prisma schema, seed do admin)"
  echo "Repositório git inicializado com o primeiro commit."
  echo "Para publicar: git remote add origin <sua-url-do-github> && git push -u origin main"
fi