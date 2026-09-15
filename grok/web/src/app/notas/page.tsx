"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

// Componente interno que consome os parâmetros da URL
function NotasContent() {
  const searchParams = useSearchParams();
  
  // Pegando os parâmetros da URL (ex: ?busca=cimento&pagina=2)
  const busca = searchParams.get("busca") || "";
  const pagina = searchParams.get("pagina") || "1";

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <h1 className="text-2xl font-bold text-gray-800">Gerenciamento de Notas</h1>
        <Link 
          href="/notas/nova" 
          className="bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md transition-colors shadow-sm flex items-center justify-center"
        >
          + Nova Nota
        </Link>
      </div>

      <div className="bg-white shadow-sm border border-gray-200 rounded-lg p-6">
        {/* Barra de Busca Fictícia */}
        <div className="mb-6 flex gap-2">
          <input 
            type="text" 
            placeholder="Buscar notas por descrição, fornecedor..." 
            defaultValue={busca}
            className="w-full max-w-md px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 text-gray-700"
          />
          <button className="bg-gray-100 hover:bg-gray-200 text-gray-700 px-4 py-2 rounded-md transition-colors border border-gray-300">
            Buscar
          </button>
        </div>

        {/* Tabela de Notas */}
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse min-w-[600px]">
            <thead>
              <tr className="border-b border-gray-200 bg-gray-50">
                <th className="py-3 px-4 font-semibold text-gray-600 text-sm">ID</th>
                <th className="py-3 px-4 font-semibold text-gray-600 text-sm">Descrição</th>
                <th className="py-3 px-4 font-semibold text-gray-600 text-sm">Data</th>
                <th className="py-3 px-4 font-semibold text-gray-600 text-sm">Valor</th>
                <th className="py-3 px-4 font-semibold text-gray-600 text-sm text-center">Status</th>
              </tr>
            </thead>
            <tbody>
              {/* Exemplo de dados estáticos para você substituir pela integração com sua API */}
              <tr className="border-b border-gray-100 hover:bg-gray-50 transition-colors">
                <td className="py-3 px-4 text-gray-700 text-sm">#1042</td>
                <td className="py-3 px-4 text-gray-700 font-medium">Compra de Cimento Portland</td>
                <td className="py-3 px-4 text-gray-500 text-sm">14/09/2026</td>
                <td className="py-3 px-4 text-gray-700">R$ 1.250,00</td>
                <td className="py-3 px-4 text-center">
                  <span className="px-2 py-1 text-xs font-semibold text-green-700 bg-green-100 rounded-full border border-green-200">
                    Sincronizado
                  </span>
                </td>
              </tr>
              <tr className="border-b border-gray-100 hover:bg-gray-50 transition-colors">
                <td className="py-3 px-4 text-gray-700 text-sm">#1043</td>
                <td className="py-3 px-4 text-gray-700 font-medium">Aluguel de Andaimes</td>
                <td className="py-3 px-4 text-gray-500 text-sm">12/09/2026</td>
                <td className="py-3 px-4 text-gray-700">R$ 800,00</td>
                <td className="py-3 px-4 text-center">
                  <span className="px-2 py-1 text-xs font-semibold text-yellow-700 bg-yellow-100 rounded-full border border-yellow-200">
                    Pendente
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        
        {/* Rodapé / Paginação */}
        <div className="mt-6 flex items-center justify-between text-sm text-gray-500 border-t border-gray-100 pt-4">
          <span>Mostrando página {pagina}</span>
          <div className="flex gap-2">
            <button className="px-3 py-1 border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-50">Anterior</button>
            <button className="px-3 py-1 border border-gray-300 rounded-md hover:bg-gray-50">Próxima</button>
          </div>
        </div>
      </div>
    </div>
  );
}

// Loading state que será exibido enquanto o Suspense aguarda
function NotasSkeleton() {
  return (
    <div className="flex justify-center items-center p-12">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      <span className="ml-3 text-gray-600">Carregando notas...</span>
    </div>
  );
}

// Componente principal exportado para a rota
export default function NotasPage() {
  return (
    <main className="container mx-auto p-4 md:p-8 bg-gray-50 min-h-screen">
      {/* O Suspense é OBRIGATÓRIO ao usar useSearchParams em Client Components no Next.js 14 */}
      <Suspense fallback={<NotasSkeleton />}>
        <NotasContent />
      </Suspense>
    </main>
  );
}