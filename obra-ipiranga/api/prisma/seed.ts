import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  const email =
    process.env.SEED_ADMIN_EMAIL ||
    process.env.ADMIN_EMAIL ||
    'admin@obraipiranga.com';
  const plainPassword =
    process.env.SEED_ADMIN_PASSWORD ||
    process.env.ADMIN_PASSWORD ||
    'Admin@123TroqueEmProducao';

  const password = await bcrypt.hash(plainPassword, 10);

  await prisma.user.upsert({
    where: { email },
    update: {},
    create: {
      email,
      password,
      name: 'Administrador',
      role: 'ADMIN',
    },
  });

  const elismar = await prisma.participante.upsert({
    where: { cpf: '09802372706' },
    update: { nome: 'Elismar Oliveira Guimarães' },
    create: {
      nome: 'Elismar Oliveira Guimarães',
      cpf: '09802372706',
    },
  });

  const miquelangelo = await prisma.participante.upsert({
    where: { cpf: '1383670703' },
    update: { nome: 'Miquelangelo de Souza Dias' },
    create: {
      nome: 'Miquelangelo de Souza Dias',
      cpf: '1383670703',
    },
  });

  const categorias = ['Materiais', 'Mão de obra', 'Cartório', 'Empreitada', 'Transporte', 'Outros'];
  for (const nome of categorias) {
    await prisma.categoria.upsert({
      where: { nome },
      update: {},
      create: { nome },
    });
  }

  console.log('Seed concluído:');
  console.log('  Admin email:', email);
  console.log('  Sócios:', elismar.nome, '|', miquelangelo.nome);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
