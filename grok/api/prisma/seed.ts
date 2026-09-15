import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  const password = await bcrypt.hash(process.env.SEED_ADMIN_PASSWORD || 'Admin@123', 10);

  await prisma.user.upsert({
    where: { email: process.env.SEED_ADMIN_EMAIL || 'admin@obra.local' },
    update: {},
    create: {
      email: process.env.SEED_ADMIN_EMAIL || 'admin@obra.local',
      password,
      name: 'Administrador',
      role: 'ADMIN',
    },
  });

  // Sócios principais da obra
  const elismar = await prisma.participante.upsert({
    where: { cpf: '09802372706' },
    update: { nome: 'Elismar Oliveira Guimarães' },
    create: {
      nome: 'Elismar Oliveira Guimarães',
      cpf: '09802372706',
    },
  });

  const miquelangelo = await prisma.participante.upsert({
    where: { cpf: '1383670703' }, // ajuste se o CPF real tiver mais dígitos
    update: { nome: 'Miquelangelo de Souza Dias' },
    create: {
      nome: 'Miquelangelo de Souza Dias',
      cpf: '1383670703',
    },
  });

  // Categorias básicas
  const categorias = ['Materiais', 'Mão de obra', 'Cartório', 'Empreitada', 'Transporte', 'Outros'];
  for (const nome of categorias) {
    await prisma.categoria.upsert({
      where: { nome },
      update: {},
      create: { nome },
    });
  }

  console.log('Seed concluído:');
  console.log('  Admin:', process.env.SEED_ADMIN_EMAIL || 'admin@obra.local');
  console.log('  Sócios:', elismar.nome, miquelangelo.nome);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
