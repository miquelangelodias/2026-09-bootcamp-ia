import { prisma } from '../lib/prisma';

export const dashboardService = {
  async totaisPorSocio() {
    const participantes = await prisma.participante.findMany({
      where: { ativo: true },
      orderBy: { nome: 'asc' },
    });

    const resultados = await Promise.all(
      participantes.map(async (p) => {
        const agregados = await prisma.notaFiscal.aggregate({
          where: {
            participanteId: p.id,
            status: 'CONFIRMADA',
          },
          _sum: { valorTotal: true },
          _count: true,
        });

        const pendentes = await prisma.notaFiscal.count({
          where: {
            participanteId: p.id,
            status: 'PENDENTE',
          },
        });

        return {
          id: p.id,
          nome: p.nome,
          cpf: p.cpf,
          totalConfirmado: Number(agregados._sum.valorTotal ?? 0),
          quantidadeNotas: agregados._count,
          quantidadePendentes: pendentes,
        };
      })
    );

    const semSocio = await prisma.notaFiscal.aggregate({
      where: { participanteId: null, status: 'PENDENTE' },
      _sum: { valorTotal: true },
      _count: true,
    });

    return {
      socios: resultados,
      pendentesSemSocio: {
        total: Number(semSocio._sum.valorTotal ?? 0),
        quantidade: semSocio._count,
      },
    };
  },

  async resumoGeral() {
    const [gastos, aportes, pendentes] = await Promise.all([
      prisma.notaFiscal.aggregate({
        where: { status: 'CONFIRMADA' },
        _sum: { valorTotal: true },
      }),
      prisma.aporte.aggregate({
        _sum: { valor: true },
      }),
      prisma.notaFiscal.count({ where: { status: 'PENDENTE' } }),
    ]);

    const realizado = Number(gastos._sum.valorTotal ?? 0);
    const totalAportado = Number(aportes._sum.valor ?? 0);

    return {
      totalAportado,
      totalGasto: realizado,
      saldoCaixa: totalAportado - realizado,
      notasPendentes: pendentes,
    };
  },

  async notasPendentes() {
    return prisma.notaFiscal.findMany({
      where: { status: 'PENDENTE' },
      include: {
        participante: { select: { id: true, nome: true, cpf: true } },
        categoria: { select: { id: true, nome: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  },
};
