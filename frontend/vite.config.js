import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import proxyHandler from '../api/proxy.mjs'

// Serves the same allow-listed proxy that Vercel runs in production, so
// `npm run dev` works without the Vercel CLI.
const devProxy = {
  name: 'newsedge-dev-proxy',
  configureServer(server) {
    server.middlewares.use('/api/proxy', (req, res) => proxyHandler(req, res))
  }
}

export default defineConfig({
  plugins: [react(), devProxy],
  server: {
    port: 5173
  },
  test: {
    environment: 'node'
  }
})
