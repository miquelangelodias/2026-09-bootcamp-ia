import { Router } from 'express';
import { dashboardController } from '../controllers/dashboard.controller';
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();

router.use(authMiddleware);

router.get('/por-socio', dashboardController.porSocio);
router.get('/resumo', dashboardController.resumo);
router.get('/pendentes', dashboardController.pendentes);

export const dashboardRoutes = router;
