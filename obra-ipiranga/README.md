# Obra Ipiranga — Gestão Financeira

Sistema web para controle de notas fiscais e aportes dos sócios **Elismar** e **Miquelangelo**.

## O que já está pronto (MVP)

- **Tela inicial** focada na decisão principal: totais grandes de NFs por CPF de cada sócio + botão evidente “Confirmar notas pendentes”.
- Lista de notas com **edição inline** (sócio + confirmar).
- Lançamento manual de nova nota.
- Rateio automático por CPF (quando o sócio é informado).
- Webhook preparado para **Evolution API**.
- Estrutura de **sincronização bidirecional** com Google Sheets.
- Docker Compose (Postgres + Redis + API + Web).
- Seed com os dois sócios e categorias básicas.

## Como subir

```bash
cd obra-ipiranga
cp .env.example .env
# edite .env

docker compose up -d --build

docker compose exec api npx prisma migrate deploy
docker compose exec api npm run prisma:seed
```

### Login inicial

| Campo  | Valor                  |
|--------|------------------------|
| E-mail | valor de SEED_ADMIN_EMAIL no .env |
| Senha  | valor de SEED_ADMIN_PASSWORD no .env |

## Stack

- API: Node.js + Express + Prisma + PostgreSQL
- Web: Next.js 14 + Tailwind
- Deploy local: Docker Compose
