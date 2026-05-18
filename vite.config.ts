import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

import { cloudflare } from "@cloudflare/vite-plugin";

export default defineConfig({
  plugins: [react(), tailwindcss(), cloudflare()],
  server: {
    proxy: {
      '/api/getaddress': {
        target: 'https://api.getaddress.io',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api\/getaddress/, ''),
      },
    },
  },
})