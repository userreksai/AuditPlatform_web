import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: { port: 9100, proxy: { '/api': 'http://127.0.0.1:10001' } },
  build: { sourcemap: false },
})
