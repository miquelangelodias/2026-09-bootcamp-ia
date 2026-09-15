'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { api } from '@/lib/api';
import Link from 'next/link';

interface SocioTotais {
  id: number;
  nome: string;
  cpf: string;
  totalConfirmado: number;
  quantidadeNotas: number;
  quantidadePendentes: number;
}

interface DashboardData {
  socios: SocioTotais[];
  pendentesSemSocio: { total: number; quantidade: number };
}

function formatBRL(value: number) {
  return value.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

export default function HomePage() {
  const router = useRouter();
  const [data, setData] = useState<DashboardData | null>(null);
  const [resumo, setResumo] = useState<{ saldoCaixa: number; totalAportado: number; totalGasto: number; notasPendentes: number } | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (!token) {
      router.replace('/login');
      return;
    }

    Promise.all([
      api<DashboardData>('/dashboard/por-socio'),
      api('/dashboard/resumo'),
    ])
      .then(([porSocio, resumoGeral]) => {
        setData(porSocio);
        setResumo(resumoGeral);
      })
      .catch(() => router.replace('/login'))
      .finally(() => setLoading(false));
  }, [router]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-muted">
        Carregando…
      </div>
    );
  }

  const totalPendentes =
    (data?.pendentesSemSocio.quantidade || 0) +
    (data?.socios.reduce((acc, s) => acc + s.quantidadePendentes, 0) || 0);

  return (
    <div className="min-h-screen pb-24">
      {/* Header minimalista */}
      <header className="sticky top-0 z-10 bg-white/90 backdrop-blur border-b border-border px-4 py-3 flex items-center justify-between">
        <h1 className="font-semibold text-lg">Obra Ipiranga</h1>
        <button
          onClick={() => {
            localStorage.removeItem('token');
            router.push('/login');
          }}
          className="text-sm text-muted"
        >
          Sair
        </button>
      </header>

      <main className="px-4 pt-5 max-w-lg mx-auto space-y-5">
        {/* Resumo rápido de caixa */}
        {resumo && (
          <div className="card flex justify-between items-center text-sm">
            <div>
              <p className="text-muted">Saldo em caixa</p>
              <p className="text-xl font-semibold tracking-tight">{formatBRL(resumo.saldoCaixa)}</p>
            </div>
            <div className="text-right text-muted">
              <p>Aportado {formatBRL(resumo.totalAportado)}</p>
              <p>Gasto {formatBRL(resumo.totalGasto)}</p>
            </div>
          </div>
        )}

        {/* Cards grandes por sócio — prioridade de decisão */}
        <section className="space-y-3">
          <h2 className="text-sm font-medium text-muted uppercase tracking-wide">Total de NFs por sócio</h2>
          {data?.socios.map((socio) => (
            <div key={socio.id} className="card">
              <div className="flex justify-between items-start">
                <div>
                  <p className="font-medium">{socio.nome.split(' ')[0]}</p>
                  <p className="text-xs text-muted mt-0.5">CPF {socio.cpf}</p>
                </div>
                {socio.quantidadePendentes > 0 && (
                  <span className="text-xs bg-amber-50 text-amber-700 px-2 py-0.5 rounded-full">
                    {socio.quantidadePendentes} pendente{socio.quantidadePendentes > 1 ? 's' : ''}
                  </span>
                )}
              </div>
              <p className="text-2xl font-semibold mt-3 tracking-tight">
                {formatBRL(socio.totalConfirmado)}
              </p>
              <p className="text-xs text-muted mt-1">{socio.quantidadeNotas} nota{socio.quantidadeNotas !== 1 ? 's' : ''} confirmada{socio.quantidadeNotas !== 1 ? 's' : ''}</p>
            </div>
          ))}
        </section>

        {/* Botão principal evidente */}
        <Link
          href="/notas?status=PENDENTE"
          className="btn-primary w-full flex items-center justify-center gap-2 text-center"
        >
          Confirmar notas pendentes
          {totalPendentes > 0 && (
            <span className="bg-white/20 rounded-full px-2 py-0.5 text-sm">
              {totalPendentes}
            </span>
          )}
        </Link>

        {/* Ações secundárias */}
        <div className="grid grid-cols-2 gap-3">
          <Link href="/notas/nova" className="btn-secondary text-center">
            Lançar nova nota
          </Link>
          <Link href="/notas" className="btn-secondary text-center">
            Ver todas
          </Link>
        </div>
      </main>
    </div>
  );
}
