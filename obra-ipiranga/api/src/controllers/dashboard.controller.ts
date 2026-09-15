import { Request, Response } from 'express';
import { dashboardService } from '../services/dashboard.service';

export const dashboardController = {
  async porSocio(_req: Request, res: Response) {
    const data = await dashboardService.totaisPorSocio();
    res.json(data);
  },

  async resumo(_req: Request, res: Response) {
    const data = await dashboardService.resumoGeral();
    res.json(data);
  },

  async pendentes(_req: Request, res: Response) {
    const data = await dashboardService.notasPendentes();
    res.json(data);
  },
};
