import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{js,ts,jsx,tsx,mdx}'],
  theme: {
    extend: {
      colors: {
        border: '#e5e7eb',
        muted: '#6b7280',
        accent: '#111827',
      },
    },
  },
  plugins: [],
};
export default config;
