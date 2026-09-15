import { google } from 'googleapis';
import { prisma } from '../lib/prisma';

/**
 * Sincronização bidirecional com Google Sheets.
 * Regra de conflito: Sheets vence (conforme definido).
 *
 * Configure:
 * - GOOGLE_SERVICE_ACCOUNT_EMAIL
 * - GOOGLE_PRIVATE_KEY (com \n reais)
 * - GOOGLE_SHEETS_ID
 */
function getAuth() {
  const email = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL;
  const key = process.env.GOOGLE_PRIVATE_KEY?.replace(/\\n/g, '\n');
  if (!email || !key) {
    throw new Error('Credenciais Google Sheets não configuradas');
  }

  return new google.auth.JWT({
    email,
    key,
    scopes: ['https://www.googleapis.com/auth/spreadsheets'],
  });
}

export const syncService = {
  async pullFromSheets() {
    const auth = getAuth();
    const sheets = google.sheets({ version: 'v4', auth });
    const spreadsheetId = process.env.GOOGLE_SHEETS_ID!;

    // Exemplo: lê uma aba. Ajuste o range conforme a estrutura real da planilha.
    const response = await sheets.spreadsheets.values.get({
      spreadsheetId,
      range: process.env.GOOGLE_SHEETS_RANGE || 'CONTROLE NF!A1:Z100',
    });

    const rows = response.data.values || [];
    let imported = 0;
    let conflicts = 0;

    // TODO: mapear as colunas reais da planilha CONTROLE NF
    // Por enquanto apenas registra o log
    await prisma.syncLog.create({
      data: {
        direction: 'SHEETS_TO_APP',
        entity: 'NOTA',
        status: 'SUCCESS',
        message: `Lidas ${rows.length} linhas do Sheets`,
        payload: { rowCount: rows.length },
      },
    });

    return { imported, conflicts, rowsRead: rows.length, message: 'Pull executado (mapeamento de colunas a ser refinado)' };
  },

  async pushToSheets() {
    // Implementação inicial: apenas log. Em produção escreve de volta nas linhas.
    await prisma.syncLog.create({
      data: {
        direction: 'APP_TO_SHEETS',
        entity: 'NOTA',
        status: 'SUCCESS',
        message: 'Push iniciado (implementação completa depende do mapeamento de colunas)',
      },
    });

    return { message: 'Push registrado. Mapeamento de colunas será feito na próxima iteração.' };
  },
};
