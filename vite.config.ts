import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 开发服务（pnpm dev / systemd aws-audit-web）经 nginx 以 http://prodsafety.ops.tw:10111/audit/ 访问；
// 生产构建（install.sh）仍以根路径 / 部署。
export default defineConfig(({ command }) => ({
  plugins: [vue()],
  base: command === 'serve' ? '/audit/' : '/',
  server: {
    host: '127.0.0.1',
    port: 9100,
    strictPort: true,
    // Vite 6+ 默认拒绝非 localhost 的 Host 头，需放行经 nginx 转发来的域名
    allowedHosts: ['prodsafety.ops.tw'],
    // 浏览器通过 nginx 的 10111 端口建立 HMR WebSocket
    hmr: { clientPort: 10111 },
    proxy: {
      // 前端请求 /audit/api/* -> 审计后端 /api/*
      // 必须保留浏览器原始 Host（changeOrigin: false），后端用 Origin 与 Host 比对做同源校验
      '/audit/api': {
        target: 'http://127.0.0.1:10001',
        changeOrigin: false,
        rewrite: (p) => p.replace(/^\/audit/, ''),
      },
    },
  },
  build: { sourcemap: false },
}))
