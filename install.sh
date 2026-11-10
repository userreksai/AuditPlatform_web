#!/usr/bin/env bash
# Standalone Vue production deployment: Nginx :9100 -> Go API :10001.
set -Eeuo pipefail
umask 027
trap 'printf "Frontend installation failed at line %s.\n" "$LINENO" >&2' ERR
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PORT=9100
BACKEND=http://127.0.0.1:10001
INSTALL_DEPS=1
START=1
DIST_ONLY=0
while (($#)); do
  case "$1" in
    --port) PORT="${2:?Missing frontend port}"; shift 2 ;;
    --backend) BACKEND="${2:?Missing backend origin}"; shift 2 ;;
    --no-deps) INSTALL_DEPS=0; shift ;;
    --no-start) START=0; shift ;;
    --dist-only) DIST_ONLY=1; shift ;;
    -h|--help)
      printf '%s\n' 'sudo bash install.sh [--port 9100] [--backend http://127.0.0.1:10001] [--dist-only] [--no-deps] [--no-start]' 'Installs Vue assets under /opt/aws-audit-web and configures /etc/nginx/conf.d/aws-audit-web.conf.' 'The Go backend must be installed separately. Existing backend config/database are not modified.'
      exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ $PORT =~ ^[0-9]{1,5}$ ]] && ((10#$PORT>=1 && 10#$PORT<=65535)) || { echo 'Frontend port must be 1..65535.' >&2; exit 2; }
PORT=$((10#$PORT))
[[ $(uname -s) == Linux ]] || { echo 'Linux is required.' >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo 'Run using sudo bash install.sh.' >&2; exit 1; }
command -v systemctl >/dev/null && [[ -d /run/systemd/system ]] || { echo 'A running systemd service manager is required.' >&2; exit 1; }

if ((INSTALL_DEPS)); then
  if command -v apt-get >/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx ca-certificates curl tar xz-utils python3 libatomic1 libstdc++6
  elif command -v dnf >/dev/null; then
    dnf install -y nginx ca-certificates curl tar xz python3 libatomic libstdc++
  elif command -v yum >/dev/null; then
    yum install -y nginx ca-certificates curl tar xz python3 libatomic libstdc++
  else
    echo 'Install nginx/curl/tar/xz/python3/CA certificates and libatomic/libstdc++ manually, then use --no-deps.' >&2
    exit 1
  fi
fi
for dependency in nginx curl tar python3 sha256sum install; do
  command -v "$dependency" >/dev/null || { echo "Missing dependency: $dependency" >&2; exit 1; }
done
CA_BUNDLE=""
for candidate in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do
  if [[ -f $candidate ]]; then CA_BUNDLE="$candidate"; break; fi
done
python3 "$SOURCE_DIR/deploy/render_nginx.py" --port "$PORT" --backend "$BACKEND" --ca-bundle "$CA_BUNDLE" --check

STAGE="$(mktemp -d /tmp/aws-audit-web-build.XXXXXXXX)"
cleanup() { [[ $STAGE == /tmp/aws-audit-web-build.* && -d $STAGE ]] && rm -rf -- "$STAGE"; }
trap cleanup EXIT
download() { curl --fail --location --retry 3 --connect-timeout 20 --proto '=https' --tlsv1.2 "$1" -o "$2"; }

if ((!DIST_ONLY)); then
  case "$(uname -m)" in
    x86_64) NODE_ARCH=x64 ;;
    aarch64|arm64) NODE_ARCH=arm64 ;;
    *) echo 'Source builds support Linux amd64 and arm64.' >&2; exit 1 ;;
  esac
  # Keep the build on Node 24 LTS; resolve its latest patch via official checksums.
  download 'https://nodejs.org/download/release/latest-v24.x/SHASUMS256.txt' "$STAGE/node-shasums"
  read -r NODE_SHA NODE_FILE < <(awk -v suffix="-linux-$NODE_ARCH.tar.xz" '$2 ~ /^node-v24\./ && substr($2,length($2)-length(suffix)+1)==suffix {print $1,$2; exit}' "$STAGE/node-shasums")
  [[ ${NODE_SHA:-} =~ ^[0-9a-f]{64}$ && ${NODE_FILE:-} == node-v24.*-linux-"$NODE_ARCH".tar.xz ]] || { echo 'Official Node 24 checksum entry missing.' >&2; exit 1; }
  download "https://nodejs.org/download/release/latest-v24.x/$NODE_FILE" "$STAGE/$NODE_FILE"
  printf '%s  %s\n' "$NODE_SHA" "$STAGE/$NODE_FILE" | sha256sum --check --status
  mkdir "$STAGE/node"
  tar -xJf "$STAGE/$NODE_FILE" -C "$STAGE/node" --strip-components=1
  export PATH="$STAGE/node/bin:$PATH" CI=true
  if ! NODE_OUTPUT="$(node --version 2>&1)"; then
    printf 'Downloaded Node cannot run:\n%s\nInstall libatomic/libstdc++ (Debian: libatomic1/libstdc++6), or deploy a prebuilt dist using --dist-only.\n' "$NODE_OUTPUT" >&2
    exit 1
  fi
  printf 'Node runtime verified: %s\n' "$NODE_OUTPUT"
  PNPM_SPEC="$(python3 - "$SOURCE_DIR/package.json" <<'PY'
import json, re, sys
spec=json.load(open(sys.argv[1])).get('packageManager','')
if not re.fullmatch(r'pnpm@\d+\.\d+\.\d+',spec): raise SystemExit('Expected pinned pnpm packageManager')
print(spec)
PY
)"
  npm install --prefix "$STAGE/package-manager" --no-audit --no-fund "$PNPM_SPEC"
  (
    cd "$SOURCE_DIR"
    "$STAGE/package-manager/node_modules/.bin/pnpm" install --frozen-lockfile
    VITE_API_BASE_URL='' "$STAGE/package-manager/node_modules/.bin/pnpm" run build
  )
fi
[[ -s $SOURCE_DIR/dist/index.html ]] || { echo 'dist/index.html missing. Build first or omit --dist-only.' >&2; exit 1; }

INSTALL_ROOT=/opt/aws-audit-web
CONF_PATH=/etc/nginx/conf.d/aws-audit-web.conf
RELEASE="$INSTALL_ROOT/releases/$(date -u +%Y%m%dT%H%M%SZ)-$$"
install -d -m 0755 "$INSTALL_ROOT" "$INSTALL_ROOT/releases" "$RELEASE" /etc/nginx/conf.d
cp -R "$SOURCE_DIR/dist/." "$RELEASE/"
chmod -R a+rX "$RELEASE"
RELEASE_ID="${RELEASE##*/}"
python3 "$SOURCE_DIR/deploy/render_nginx.py" --port "$PORT" --backend "$BACKEND" --ca-bundle "$CA_BUNDLE" --release-id "$RELEASE_ID" --output "$STAGE/frontend.conf"

# Publish only after assets have built; restore our prior config/link on failure.
HAD_CONF=0
LINK_CHANGED=0
SERVICE_ATTEMPTED=0
PREVIOUS="$(readlink "$INSTALL_ROOT/current" || true)"
if [[ -e $CONF_PATH || -L $CONF_PATH ]]; then
  cp -L -- "$CONF_PATH" "$STAGE/previous.conf"
  HAD_CONF=1
fi
rollback() {
  trap - ERR
  set +e
  if ((HAD_CONF)); then install -m 0644 "$STAGE/previous.conf" "$CONF_PATH"; else rm -f -- "$CONF_PATH"; fi
  if ((LINK_CHANGED)); then
    if [[ -n $PREVIOUS ]]; then
      ln -s "$PREVIOUS" "$INSTALL_ROOT/current.rollback.$$"
      mv -Tf "$INSTALL_ROOT/current.rollback.$$" "$INSTALL_ROOT/current"
    else
      rm -f -- "$INSTALL_ROOT/current"
    fi
  fi
  if ((SERVICE_ATTEMPTED)) && nginx -t; then systemctl reload nginx || true; fi
  echo 'Restored the previous frontend config/release; backend config and database were not modified.' >&2
  echo 'Check: sudo journalctl -u nginx -n 30 --no-pager; sudo tail -n 30 /var/log/nginx/error.log' >&2
  if command -v getenforce >/dev/null && [[ $(getenforce) == Enforcing ]]; then
    echo 'SELinux is enforcing: check static-file labels (httpd_sys_content_t), the frontend port label (http_port_t), and Nginx-to-backend network policy. Do not disable SELinux.' >&2
  fi
}
trap 'rollback; printf "Frontend publication failed at line %s.\n" "$LINENO" >&2; exit 1' ERR
install -m 0644 "$STAGE/frontend.conf" "$CONF_PATH"
nginx -t
ln -s "$RELEASE" "$INSTALL_ROOT/current.new.$$"
mv -Tf "$INSTALL_ROOT/current.new.$$" "$INSTALL_ROOT/current"
LINK_CHANGED=1
if ((START)); then
  SERVICE_ATTEMPTED=1
  systemctl enable nginx
  if systemctl is-active --quiet nginx; then systemctl reload nginx; else systemctl start nginx; fi
  systemctl is-active --quiet nginx
  READY=0
  for attempt in 1 2 3 4 5; do
    if [[ $(curl --fail --silent --max-time 3 "http://127.0.0.1:$PORT/__aws_audit_web_health" || true) == "aws-audit-web:$RELEASE_ID" ]] && curl --fail --silent --max-time 3 "http://127.0.0.1:$PORT/index.html" > /dev/null; then
      READY=1
      break
    fi
    sleep 1
  done
  if ((!READY)); then echo 'Nginx did not serve the new frontend release. Check port conflicts, file permissions and Nginx logs.' >&2; false; fi
fi
trap 'printf "Frontend installation failed at line %s.\n" "$LINENO" >&2' ERR
printf '\nFrontend installed.\nURL: http://SERVER_IP:%s\nBackend API: %s\nConfig: %s\n' "$PORT" "$BACKEND" "$CONF_PATH"
if ((!START)); then echo 'Nginx not started/reloaded (--no-start). Run: sudo nginx -t && sudo systemctl enable --now nginx && sudo systemctl reload nginx'; fi
if ! curl --fail --silent --show-error --max-time 5 "$BACKEND/api/health" >/dev/null; then
  echo 'Backend health check failed. Start the Go backend before using login/data collection.' >&2
fi
