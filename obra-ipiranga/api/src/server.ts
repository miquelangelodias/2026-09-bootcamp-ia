import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { authRoutes } from './routes/auth.routes';
import { dashboardRoutes } from './routes/dashboard.routes';
import { notasRoutes } from './routes/notas.routes';
import { participantesRoutes } from './routes/participantes.routes';
import { categoriasRoutes } from './routes/categorias.routes';
import { webhooksRoutes } from './routes/webhooks.routes';
import { syncRoutes } from './routes/sync.routes';

dotenv.config();

const app = express();
const PORT = process.env.API_PORT || 3000;

app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '10mb' }));

app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'obra-ipiranga-api' }));

app.use('/auth', authRoutes);
app.use('/dashboard', dashboardRoutes);
app.use('/notas', notasRoutes);
app.use('/participantes', participantesRoutes);
app.use('/categorias', categoriasRoutes);
app.use('/webhooks', webhooksRoutes);
app.use('/sync', syncRoutes);

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err);
  res.status(err.status || 500).json({ error: err.message || 'Erro interno' });
});

app.listen(PORT, () => {
  console.log(`API rodando na porta ${PORT}`);
});
