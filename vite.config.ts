import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  return {
    plugins: [react(), tailwindcss()],
    server: {
      proxy: {
        '/api/getaddress': {
          target: 'https://api.getaddress.io',
          changeOrigin: true,
          rewrite: (path) =>
            path.replace(/^\/api\/getaddress/, '') + `?api-key=${env.GETADDRESS_API_KEY}`,
        },
      },
    },
  }
})
