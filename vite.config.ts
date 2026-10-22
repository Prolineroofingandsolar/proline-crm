import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const key = env.GETADDRESS_API_KEY
  return {
    plugins: [react(), tailwindcss()],
    server: {
      strictPort: true,
      proxy: {
        // Paperclip (local AI agent server) has no CORS headers, so dev goes through here.
        '/paperclip': {
          target: env.PAPERCLIP_URL || 'http://localhost:3100',
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/paperclip/, ''),
        },
        '/api/getaddress': {
          target: 'https://api.getaddress.io',
          changeOrigin: true,
          rewrite: (path) => {
            const clean = path.replace(/^\/api\/getaddress/, '')
            return `${clean}?api-key=${key}`
          },
        },
      },
    },
    clearScreen: false,
  }
})
