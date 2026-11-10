# 独立前端部署验证

2026-11-10，本地验证记录：

- Vue TypeScript 检查及 Vite 生产构建通过，构建强制使用同源 API。
- `python -m unittest discover -s tests -p test_deploy.py`：14 项通过，覆盖默认 9100 → 10001、保留 `/api` 和 Host 端口、SPA 回退、IPv6、URL/路径注入拒绝、端口范围、HTTPS 上游校验与 SNI、同端口循环代理拒绝、本次发布健康标识。
- `bash tests/test_install.sh`：5 组通过，覆盖帮助/参数错误、Nginx 检查失败恢复旧配置、`--no-start` 不调用服务命令、旧发布健康标识导致回滚、正确发布标识允许继续。
- `install.sh` Bash 语法检查通过。
- 使用官方 Nginx 1.30.6 Windows 程序执行 `nginx -t`，生成的生产代理配置检查通过。未为此启动监听服务。

脚本测试使用临时文件和命令模拟，不执行特权安装。真实 Linux systemd、SELinux、系统包安装和生产符号链接切换尚需在目标服务器验证；本记录不表示已经在用户服务器完成部署。安装脚本会在目标机执行 `nginx -t` 并核对新发布标识及首页，失败时恢复本脚本管理的配置和前端文件链接。
