# 云鉴 · AWS 账号审计平台前端

Vue 3、TypeScript、Vite 构建的中文 AWS IAM 审计工作台。后端仓库：[AuditPlatform_server](https://github.com/userreksai/AuditPlatform_server)。

## Linux 独立部署

前端使用 Nginx 在 **9100** 端口提供生产页面，并将同源 `/api` 请求代理到 Go 后端 **10001** 端口。先启动后端，再在 Linux 服务器执行：

```sh
git clone https://github.com/userreksai/AuditPlatform_web.git
cd AuditPlatform_web
sudo bash install.sh
```

安装完成后访问 `http://服务器IP:9100`。脚本安装所需依赖、使用校验过 SHA256 的官方 Node.js 24 LTS 构建前端、部署静态文件并配置 Nginx。发布文件保存在 `/opt/aws-audit-web/releases/`，`/opt/aws-audit-web/current` 指向当前版本，Nginx 配置为 `/etc/nginx/conf.d/aws-audit-web.conf`。

如果此前运行过 Vite 开发服务，请先停止该进程，释放 9100 端口，再执行生产部署。

```sh
# 后端在其他服务器，或需要自定义前端端口
sudo bash install.sh --backend http://192.0.2.10:10001 --port 9100

# 系统依赖已准备好时，跳过依赖安装
sudo bash install.sh --no-deps

# 只部署文件和生成配置，不启动或重载 Nginx
sudo bash install.sh --no-start

# 已准备好仓库根目录下的 dist/index.html，跳过 Node.js 和前端构建
sudo bash install.sh --dist-only
```

`--backend` 默认为 `http://127.0.0.1:10001`，支持 HTTP/HTTPS 域名、IPv4 或方括号形式的 IPv6 地址及可选端口；不要附加账号密码、路径、查询参数或片段。浏览器始终通过前端地址的 `/api` 访问后端，不需要开放跨域。使用 HTTPS 后端时，Nginx 会验证上游证书，请确保系统信任相应 CA。

```sh
sudo nginx -t
curl -fsS http://127.0.0.1:9100/api/health
```

后端健康检查应返回 `status: ok`。平台登录账号与密码、AWS Access Key 仍在**后端**配置文件中维护；前端部署脚本不保存这些凭证。生产公网访问建议在入口配置 HTTPS，并按 HTTPS 入口设置后端安全 Cookie。

脚本会运行 `nginx -t`，启动/重载后核对本次发布标识和首页是否可读；发布失败时恢复上一次前端配置和文件链接。`--no-start` 不执行启动和重载，稍后可运行 `sudo nginx -t && sudo systemctl enable --now nginx && sudo systemctl reload nginx`。

运行 SELinux 的服务器需由管理员核对静态目录的 `httpd_sys_content_t` 标签、9100 端口的服务类型以及 Nginx 访问后端的策略；脚本不关闭 SELinux，也不修改全局安全策略。若启动或访问失败，查看 `sudo journalctl -u nginx -n 30 --no-pager` 和 `/var/log/nginx/error.log`。同时确认服务器安全组允许访问前端端口。

## 本地开发

需要 Node.js 22.12+（或 24 LTS）和 pnpm 11.25.0。

```sh
corepack enable
corepack prepare pnpm@11.25.0 --activate
pnpm install --frozen-lockfile
pnpm dev
```

开发地址为 `http://127.0.0.1:9100`。开发服务器将 `/api` 转发到 `http://127.0.0.1:10001`。先启动 Go 后端，再使用服务端配置的账号密码登录。前端没有硬编码认证逻辑。

```sh
pnpm typecheck
pnpm build
```

开发服务使用的 9100 端口与默认 Nginx 生产端口相同，两者不要同时运行。`pnpm dev` 用于开发；生产部署使用上面的前端 `install.sh`。生成的 `dist/` 也可以交由 Go 服务端同源托管，后端 `install.sh` 保留此集成部署方式。

默认同源，不需要设置 API 地址。`VITE_API_BASE_URL` 仅供同源代理前缀使用；配套后端不支持直接跨域部署，生产环境由 Go 或同一反向代理托管页面与 API。

## 页面功能

- 登录、会话检查及退出；AWS 凭证始终保留在服务端。
- IAM 用户清单，搜索账号、用户名、策略、Access Key 或 IP；按账号、MFA、IP 条件和需求检查筛选。
- 全部 **21 个字段**（含 Secrets Manager 读取权限及其来源） 可通过“显示字段”选择，默认显示常用字段。CSV 导出始终包含全部字段，对可能执行的电子表格公式进行转义。
- 用户详情包含账号 → IAM 用户 → 直接 / 用户组策略 → IP 条件原文、来源策略、权限边界与原始 JSON。
- 审计备注支持负责人、需求检查状态、备注；由后端独立保存，后续获取不会覆盖。
- 账号状态、获取记录、最近完成和下次获取时间。自动任务由 Go 后端在北京时间每日 09:00 执行，浏览器关闭不影响任务。
- “立即全部获取”触发后端异步采集，并轮询任务状态；重复执行由服务端任务锁拒绝。

空数据、连接失败、部分获取失败及未知状态均有独立显示。账号失败时展示后端保留的最近有效快照，不能将旧快照误当成最新采集结果。

## 演示模式

仅在显式打开 `/?demo=1` 时使用本地示例数据。页面显示演示横幅，不能连接 AWS、运行采集或保存备注。真实模式从不自动回退到演示数据。演示策略中的 SecurityAudit 为节选，不用于真实权限评估。

## 判读范围

IP 状态是策略条件摘要，不能证明最终有效授权。详情保留 Effect、运算符（包括 IfExists / 集合运算符）、条件键、IP/CIDR 原值。范围可能是白名单候选、黑名单或局部授权条件，请结合原始语句判断。权限边界不授予权限；SCP、资源策略、会话策略和请求上下文尚未做有效权限模拟。

MFA 已启用表示已绑定设备，不代表所有请求都强制 MFA。控制台已启用表示有登录配置。凭证报告时间和数据完整性限制由后端 warnings 展示；空时间不等于确定未使用。Root 不是 IAM 用户，不计入清单。

界面时间统一使用 `Asia/Shanghai`，不受浏览器本地时区影响。使用系统字体，无外部字体网络依赖。
