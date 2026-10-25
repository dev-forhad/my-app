import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    // Local dev: proxy /api to the .NET API running on your machine, so the
    // browser only ever sees same-origin requests — exactly like production,
    // where CloudFront serves both the site and /api/* on one domain.
    proxy: {
      '/api': 'http://localhost:8080',
    },
  },
})
