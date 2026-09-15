import { prisma } from '../lib/prisma';
import { Decimal } from '@prisma/client/runtime/library';

interface CriarNotaInput {
  chaveAcesso?: string;
  numero?: string;
  dataEmissao?: string;
  fornecedor?: string;
  valorTotal: number;
  participanteId?: number;
  categoriaId?: number;
  observacao?: string;
  origem?: 'MANUAL' | 'EVOLUTION' | 'SHEETS' | 'OCR';
}

export const notasService = {
  async listar(filters: { status?: string; participanteId?: number }) {
    return prisma.notaFiscal.findMany({
      where: {
        ...(filters.status && { status: filters.status as any }),
        ...(filters.participanteId && { participanteId: filters.participanteId }),
      },
      include: {
        participante: { select: { id: true, nome: true, cpf: true } },
        categoria: { select: { id: true, nome: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  },

  async criar(data: CriarNotaInput) {
    // Rateio automático por CPF se vier chave ou se já soubermos o destinatário
    let participanteId = data.participanteId ?? null;
    let status: 'PENDENTE' | 'CONFIRMADA' = 'PENDENTE';

    if (participanteId) {
      status = 'CONFIRMADA';
    }

    return prisma.notaFiscal.create({
      data: {
        chaveAcesso: data.chaveAcesso,
        numero: data.numero,
        dataEmissao: data.dataEmissao ? new Date(data.dataEmissao) : null,
        fornecedor: data.fornecedor,
        valorTotal: new Decimal(data.valorTotal),
        participanteId,
        categoriaId: data.categoriaId ?? null,
        observacao: data.observacao,
        origem: data.origem ?? 'MANUAL',
        status,
      },
      include: {
        participante: true,
        categoria: true,
      },
    });
  },

  async atualizar(id: number, data: Partial<CriarNotaInput> & { status?: string }) {
    return prisma.notaFiscal.update({
      where: { id },
      data: {
        ...(data.chaveAcesso !== undefined && { chaveAcesso: data.chaveAcesso }),
        ...(data.numero !== undefined && { numero: data.numero }),
        ...(data.dataEmissao !== undefined && { dataEmissao: data.dataEmissao ? new Date(data.dataEmissao) : null }),
        ...(data.fornecedor !== undefined && { fornecedor: data.fornecedor }),
        ...(data.valorTotal !== undefined && { valorTotal: new Decimal(data.valorTotal) }),
        ...(data.participanteId !== undefined && { participanteId: data.participanteId }),
        ...(data.categoriaId !== undefined && { categoriaId: data.categoriaId }),
        ...(data.observacao !== undefined && { observacao: data.observacao }),
        ...(data.status !== undefined && { status: data.status as any }),
      },
      include: {
        participante: true,
        categoria: true,
      },
    });
  },

  async confirmar(id: number, opts: { participanteId?: number; categoriaId?: number }) {
    return prisma.notaFiscal.update({
      where: { id },
      data: {
        status: 'CONFIRMADA',
        ...(opts.participanteId && { participanteId: opts.participanteId }),
        ...(opts.categoriaId && { categoriaId: opts.categoriaId }),
      },
      include: {
        participante: true,
        categoria: true,
      },
    });
  },

  async remover(id: number) {
    return prisma.notaFiscal.delete({ where: { id } });
  },

  /** Usado pelo rateio automático (CPF do destinatário da NF) */
  async ratearPorCpf(cpf: string, notaId: number) {
    const socio = await prisma.participante.findFirst({
      where: { cpf: cpf.replace(/\D/g, ''), ativo: true },
    });

    if (socio) {
      return prisma.notaFiscal.update({
        where: { id: notaId },
        data: {
          participanteId: socio.id,
          status: 'CONFIRMADA',
        },
      });
    }

    // Sem match → fica pendente
    return null;
  },
};
