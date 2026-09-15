import { Request, Response } from 'express';
import { notasService } from '../services/notas.service';

export const notasController = {
  async listar(req: Request, res: Response) {
    const { status, participanteId } = req.query;
    const data = await notasService.listar({
      status: status as string | undefined,
      participanteId: participanteId ? Number(participanteId) : undefined,
    });
    res.json(data);
  },

  async criar(req: Request, res: Response) {
    const nota = await notasService.criar(req.body);
    res.status(201).json(nota);
  },

  async atualizar(req: Request, res: Response) {
    const id = Number(req.params.id);
    const nota = await notasService.atualizar(id, req.body);
    res.json(nota);
  },

  async confirmar(req: Request, res: Response) {
    const id = Number(req.params.id);
    const { participanteId, categoriaId } = req.body;
    const nota = await notasService.confirmar(id, { participanteId, categoriaId });
    res.json(nota);
  },

  async remover(req: Request, res: Response) {
    const id = Number(req.params.id);
    await notasService.remover(id);
    res.status(204).send();
  },
};
