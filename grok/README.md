# Obra Ipiranga — Gestão Financeira

Sistema web para controle de notas fiscais e aportes dos sócios **Elismar** e **Miquelangelo**.

## O que já está pronto (MVP)

- **Tela inicial** focada na decisão principal: totais grandes de NFs por CPF de cada sócio + botão evidente “Confirmar notas pendentes”.
- Lista de notas com **edição inline** (sócio + confirmar).
- Lançamento manual de nova nota.
- Rateio automático por CPF (quando o sócio é informado).
- Webhook preparado para **Evolution API**.
- Estrutura de **sincronização bidirecional** com Google Sheets (Sheets vence em conflito) — mapeamento de colunas ainda precisa ser ajustado à planilha real.
- Docker Compose (Postgres + Redis + API + Web).
- Seed com os dois sócios e categorias básicas.

## Como subir localmente

```bash
cd obra-ipiranga
cp .env.example .env
# edite .env com senhas reais e, se quiser, credenciais Google + Evolution

# Backend
cd api
npm install
npx prisma generate
npx prisma migrate dev --name init
npm run prisma:seed
npm run dev          # porta 3001

# Frontend (outro terminal)
cd ../web
npm install
npm run dev          # porta 3000
```

Ou com Docker:

```bash
docker compose up -d --build
```

Login padrão (após seed):  
`admin@obra.local` / `Admin@123`

## Próximos passos naturais

1. Mapear as colunas reais da aba **CONTROLE NF** (e APORTE CAIXA) no `sync.service.ts`.
2. Ajustar o parsing do webhook da Evolution conforme o payload real.
3. Importar os dados históricos da planilha Excel atual (exceto COTAÇÕES).
4. Conciliação bancária via upload de CSV/PDF.
5. Separar formalmente em dois repositórios se desejar (hoje está em monorepo por praticidade de Docker).

## Decisões de negócio já incorporadas

- Fonte da verdade em conflito: **Google Sheets**.
- Preferência de sync: o mais perto de tempo real possível.
- Ação principal do usuário: confirmar pendentes + lançar nova nota.
- Visual: clean, minimalista, mobile-first, botões grandes e evidentes.
