import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import { syncService } from '../services/sync.service';

const router = Router();
router.use(authMiddleware);

router.post('/sheets-to-app', async (_req, res) => {
  try {
    const result = await syncService.pullFromSheets();
    res.json(result);
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/app-to-sheets', async (_req, res) => {
  try {
    const result = await syncService.pushToSheets();
    res.json(result);
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

export const syncRoutes = router;
