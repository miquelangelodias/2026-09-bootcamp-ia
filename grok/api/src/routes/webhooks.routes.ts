import { Router } from 'express';
import { notasService } from '../services/notas.service';

const router = Router();

/**
 * Webhook da Evolution API (WhatsApp).
 * Esperamos um payload com dados da NF ou texto contendo chave de acesso / valor.
 * Ajuste o parsing conforme o formato real que a Evolution envia.
 */
router.post('/evolution', async (req, res) => {
  try {
    const body = req.body;

    // Exemplo de extração (adapte ao payload real da Evolution)
    const texto = body?.data?.message?.conversation || body?.message || JSON.stringify(body);
    const valorMatch = texto.match(/R\$\s*([\d.,]+)/i);
    const chaveMatch = texto.match(/\d{44}/);

    const valor = valorMatch ? parseFloat(valorMatch[1].replace(/\./g, '').replace(',', '.')) : 0;

    if (!valor && !chaveMatch) {
      return res.status(400).json({ error: 'Não foi possível extrair dados da nota' });
    }

    const nota = await notasService.criar({
      chaveAcesso: chaveMatch ? chaveMatch[0] : undefined,
      valorTotal: valor || 0,
      fornecedor: 'Via WhatsApp',
      origem: 'EVOLUTION',
      observacao: texto.slice(0, 500),
    });

    // Aqui poderia chamar rateio se tiver CPF no texto
    res.status(201).json({ ok: true, notaId: nota.id });
  } catch (err: any) {
    console.error('Webhook Evolution error:', err);
    res.status(500).json({ error: err.message });
  }
});

export const webhooksRoutes = router;
