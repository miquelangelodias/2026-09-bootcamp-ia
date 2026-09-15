'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { api } from '@/lib/api';
import Link from 'next/link';

interface Participante {
  id: number;
  nome: string;
}

interface Categoria {
  id: number;
  nome: string;
}

export default function NovaNotaPage() {
  const router = useRouter();
  const [participantes, setParticipantes] = useState<Participante[]>([]);
  const [categorias, setCategorias] = useState<Categoria[]>([]);
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({
    fornecedor: '',
    valorTotal: '',
    dataEmissao: '',
    numero: '',
    participanteId: '',
    categoriaId: '',
    observacao: '',
  });

  useEffect(() => {
    Promise.all([
      api<Participante[]>('/participantes'),
      api<Categoria[]>('/categorias'),
    ]).then(([p, c]) => {
      setParticipantes(p);
      setCategorias(c);
    }).catch(() => router.replace('/login'));
  }, [router]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await api('/notas', {
        method: 'POST',
        body: JSON.stringify({
          fornecedor: form.fornecedor || undefined,
          valorTotal: parseFloat(form.valorTotal.replace(',', '.')),
          dataEmissao: form.dataEmissao || undefined,
          numero: form.numero || undefined,
          participanteId: form.participanteId ? Number(form.participanteId) : undefined,
          categoriaId: form.categoriaId ? Number(form.categoriaId) : undefined,
          observacao: form.observacao || undefined,
          origem: 'MANUAL',
        }),
      });
      router.push('/notas');
    } catch (err: any) {
      alert(err.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen pb-20">
      <header className="sticky top-0 z-10 bg-white/90 backdrop-blur border-b border-border px-4 py-3 flex items-center gap-3">
        <Link href="/" className="text-muted text-sm">← Voltar</Link>
        <h1 className="font-semibold">Lançar nova nota</h1>
      </header>

      <main className="px-4 pt-5 max-w-lg mx-auto">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-1.5">Valor *</label>
            <input
              type="text"
              inputMode="decimal"
              placeholder="0,00"
              value={form.valorTotal}
              onChange={(e) => setForm({ ...form, valorTotal: e.target.value })}
              className="w-full border border-border rounded-xl px-3.5 py-3 text-lg font-medium focus:outline-none focus:ring-2 focus:ring-gray-900"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium mb-1.5">Fornecedor</label>
            <input
              type="text"
              value={form.fornecedor}
              onChange={(e) => setForm({ ...form, fornecedor: e.target.value })}
              className="w-full border border-border rounded-xl px-3.5 py-3 focus:outline-none focus:ring-2 focus:ring-gray-900"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-medium mb-1.5">Data</label>
              <input
                type="date"
                value={form.dataEmissao}
                onChange={(e) => setForm({ ...form, dataEmissao: e.target.value })}
                className="w-full border border-border rounded-xl px-3 py-3 focus:outline-none focus:ring-2 focus:ring-gray-900"
              />
            </div>
            <div>
              <label className="block text-sm font-medium mb-1.5">Nº NF</label>
              <input
                type="text"
                value={form.numero}
                onChange={(e) => setForm({ ...form, numero: e.target.value })}
                className="w-full border border-border rounded-xl px-3 py-3 focus:outline-none focus:ring-2 focus:ring-gray-900"
              />
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium mb-1.5">Sócio</label>
            <select
              value={form.participanteId}
              onChange={(e) => setForm({ ...form, participanteId: e.target.value })}
              className="w-full border border-border rounded-xl px-3.5 py-3 bg-white focus:outline-none focus:ring-2 focus:ring-gray-900"
            >
              <option value="">— Deixar pendente —</option>
              {participantes.map((p) => (
                <option key={p.id} value={p.id}>{p.nome}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium mb-1.5">Categoria</label>
            <select
              value={form.categoriaId}
              onChange={(e) => setForm({ ...form, categoriaId: e.target.value })}
              className="w-full border border-border rounded-xl px-3.5 py-3 bg-white focus:outline-none focus:ring-2 focus:ring-gray-900"
            >
              <option value="">— Sem categoria —</option>
              {categorias.map((c) => (
                <option key={c.id} value={c.id}>{c.nome}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium mb-1.5">Observação</label>
            <textarea
              value={form.observacao}
              onChange={(e) => setForm({ ...form, observacao: e.target.value })}
              rows={2}
              className="w-full border border-border rounded-xl px-3.5 py-3 focus:outline-none focus:ring-2 focus:ring-gray-900"
            />
          </div>

          <button type="submit" disabled={loading} className="btn-primary w-full mt-2">
            {loading ? 'Salvando…' : 'Salvar nota'}
          </button>
        </form>
      </main>
    </div>
  );
}
