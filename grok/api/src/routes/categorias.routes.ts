import { Router } from 'express';
import { prisma } from '../lib/prisma';
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();
router.use(authMiddleware);

router.get('/', async (_req, res) => {
  const list = await prisma.categoria.findMany({ where: { ativo: true }, orderBy: { nome: 'asc' } });
  res.json(list);
});

router.post('/', async (req, res) => {
  const { nome, etapa } = req.body;
  const created = await prisma.categoria.create({ data: { nome, etapa } });
  res.status(201).json(created);
});

export const categoriasRoutes = router;
