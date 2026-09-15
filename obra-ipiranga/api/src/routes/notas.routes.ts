import { Router } from 'express';
import { notasController } from '../controllers/notas.controller';
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();

router.use(authMiddleware);

router.get('/', notasController.listar);
router.post('/', notasController.criar);
router.patch('/:id', notasController.atualizar);
router.post('/:id/confirmar', notasController.confirmar);
router.delete('/:id', notasController.remover);

export const notasRoutes = router;
