import { Router } from 'express';
import { prisma } from '../lib/prisma';
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();
router.use(authMiddleware);

router.get('/', async (_req, res) => {
  const list = await prisma.participante.findMany({ where: { ativo: true }, orderBy: { nome: 'asc' } });
  res.json(list);
});

router.post('/', async (req, res) => {
  const { nome, cpf } = req.body;
  const created = await prisma.participante.create({
    data: { nome, cpf: String(cpf).replace(/\D/g, '') },
  });
  res.status(201).json(created);
});

export const participantesRoutes = router;
