'use client';

import { useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { api } from '@/lib/api';
import Link from 'next/link';

interface Nota {
  id: number;
  fornecedor: string | null;
  valorTotal: string;
  status: string;
  dataEmissao: string | null;
  participante: { id: number; nome: string; cpf: string } | null;
  categoria: { id: number; nome: string } | null;
}

interface Participante {
  id: number;
  nome: string;
  cpf: string;
}

function formatBRL(value: string | number) {
  return Number(value).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

export default function NotasPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const statusFilter = searchParams.get('status') || '';

  const [notas, setNotas] = useState<Nota[]>([]);
  const [participantes, setParticipantes] = useState<Participante[]>([]);
  const [loading, setLoading] = useState(true);
  const [savingId, setSavingId] = useState<number | null>(null);

  async function load() {
    setLoading(true);
    try {
      const query = statusFilter ? `?status=${statusFilter}` : '';
      const [lista, socios] = await Promise.all([
        api<Nota[]>(`/notas${query}`),
        api<Participante[]>('/participantes'),
      ]);
      setNotas(lista);
      setParticipantes(socios);
    } catch {
      router.replace('/login');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [statusFilter]);

  async function atualizarCampo(id: number, campo: string, valor: any) {
    setSavingId(id);
    try {
      await api(`/notas/${id}`, {
        method: 'PATCH',
        body: JSON.stringify({ [campo]: valor }),
      });
      await load();
    } catch (err: any) {
      alert(err.message);
    } finally {
      setSavingId(null);
    }
  }

  async function confirmar(id: number) {
    setSavingId(id);
    try {
      await api(`/notas/${id}/confirmar`, { method: 'POST', body: JSON.stringify({}) });
      await load();
    } catch (err: any) {
      alert(err.message);
    } finally {
      setSavingId(null);
    }
  }

  return (
    <div className="min-h-screen pb-20">
      <header className="sticky top-0 z-10 bg-white/90 backdrop-blur border-b border-border px-4 py-3 flex items-center gap-3">
        <Link href="/" className="text-muted text-sm">← Voltar</Link>
        <h1 className="font-semibold flex-1">
          {statusFilter === 'PENDENTE' ? 'Notas pendentes' : 'Todas as notas'}
        </h1>
        <Link href="/notas/nova" className="text-sm font-medium">+ Nova</Link>
      </header>

      <main className="px-4 pt-4 max-w-lg mx-auto space-y-3">
        <div className="flex gap-2 overflow-x-auto pb-1">
          <Link
            href="/notas"
            className={`px-3 py-1.5 rounded-full text-sm whitespace-nowrap border ${!statusFilter ? 'bg-gray-900 text-white border-gray-900' : 'border-border'}`}
          >
            Todas
          </Link>
          <Link
            href="/notas?status=PENDENTE"
            className={`px-3 py-1.5 rounded-full text-sm whitespace-nowrap border ${statusFilter === 'PENDENTE' ? 'bg-gray-900 text-white border-gray-900' : 'border-border'}`}
          >
            Pendentes
          </Link>
          <Link
            href="/notas?status=CONFIRMADA"
            className={`px-3 py-1.5 rounded-full text-sm whitespace-nowrap border ${statusFilter === 'CONFIRMADA' ? 'bg-gray-900 text-white border-gray-900' : 'border-border'}`}
          >
            Confirmadas
          </Link>
        </div>

        {loading && <p className="text-center text-muted py-8">Carregando…</p>}

        {!loading && notas.length === 0 && (
          <p className="text-center text-muted py-12">Nenhuma nota encontrada.</p>
        )}

        {notas.map((nota) => (
          <div key={nota.id} className="card space-y-3">
            <div className="flex justify-between items-start gap-2">
              <div className="min-w-0">
                <p className="font-medium truncate">{nota.fornecedor || 'Sem fornecedor'}</p>
                <p className="text-xs text-muted">
                  {nota.dataEmissao
                    ? new Date(nota.dataEmissao).toLocaleDateString('pt-BR')
                    : 'Sem data'}
                </p>
              </div>
              <p className="font-semibold whitespace-nowrap">{formatBRL(nota.valorTotal)}</p>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs text-muted block mb-1">Sócio</label>
                <select
                  value={nota.participante?.id || ''}
                  disabled={savingId === nota.id}
                  onChange={(e) =>
                    atualizarCampo(nota.id, 'participanteId', e.target.value ? Number(e.target.value) : null)
                  }
                  className="w-full border border-border rounded-lg px-2 py-2 text-sm bg-white"
                >
                  <option value="">— Sem sócio —</option>
                  {participantes.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.nome.split(' ')[0]}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs text-muted block mb-1">Status</label>
                <div className="flex items-center h-[38px]">
                  {nota.status === 'PENDENTE' ? (
                    <button
                      onClick={() => confirmar(nota.id)}
                      disabled={savingId === nota.id}
                      className="btn-primary text-sm py-2 px-3 w-full"
                    >
                      {savingId === nota.id ? '…' : 'Confirmar'}
                    </button>
                  ) : (
                    <span className="text-sm text-green-700 font-medium">Confirmada</span>
                  )}
                </div>
              </div>
            </div>
          </div>
        ))}
      </main>
    </div>
  );
}
