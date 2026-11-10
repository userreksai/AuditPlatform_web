#!/usr/bin/env bash
# Exercise the real publication/trap block with temporary files and service mocks.
set -Eeuo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$TEST_DIR/../install.sh"
TMP_PARENT="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
TASK_TMP="$(mktemp -d "$TMP_PARENT/aws-audit-web-test.XXXXXXXX")"
TASK_TMP="$(cd -- "$TASK_TMP" && pwd -P)"
cleanup() {
  case "$TASK_TMP" in
    "$TMP_PARENT"/aws-audit-web-test.*) [[ ! -d $TASK_TMP ]] || rm -rf -- "$TASK_TMP" ;;
    *) printf 'Unsafe cleanup target: %s\n' "$TASK_TMP" >&2; return 1 ;;
  esac
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

"${BASH:-bash}" "$INSTALLER" --help > "$TASK_TMP/help.out"
grep -q -- '--dist-only' "$TASK_TMP/help.out" || fail 'help omitted dist-only'
for port in 0 65536 abc -1 '1;echo injected'; do
  set +e
  "${BASH:-bash}" "$INSTALLER" --port "$port" > "$TASK_TMP/port.out" 2>&1
  status=$?
  set -e
  [[ $status == 2 ]] || fail "invalid port $port returned $status"
  grep -q 'Frontend port must be 1..65535' "$TASK_TMP/port.out" || fail 'invalid port missed validation'
done
printf 'PASS: help and invalid ports work without installation\n'

# Fail extraction closed: never accidentally source the full privileged installer.
awk '
  /^# Publish only after assets have built;/ { capture=1; starts++ }
  /^trap .*Frontend installation failed at line/ { if (capture) { ended=1; exit } }
  capture { print }
  END { if (starts != 1 || !ended) exit 1 }
' "$INSTALLER" > "$TASK_TMP/publish.sh" || fail 'publication block markers changed'

prepare_case() {
  CASE_ROOT="$TASK_TMP/$1"
  STAGE="$CASE_ROOT/stage"
  INSTALL_ROOT="$CASE_ROOT/install"
  CONF_PATH="$CASE_ROOT/frontend.conf"
  case "$CASE_ROOT" in "$TASK_TMP"/*) ;; *) fail 'case escaped temporary directory' ;; esac
  mkdir -p "$STAGE" "$INSTALL_ROOT"
  printf 'old-config\n' > "$CONF_PATH"
  printf 'new-config\n' > "$STAGE/frontend.conf"
  : > "$CASE_ROOT/services.log"
  : > "$CASE_ROOT/nginx.log"
  RELEASE="$INSTALL_ROOT/releases/new"
  RELEASE_ID=test-new-release
  PORT=9100
}

run_publication() (
  set -Eeuo pipefail
  install() {
    # The publication block only installs configuration files; copy them for real.
    [[ $# == 4 && $1 == -m && $2 == 0644 ]] || return 9
    case "$3" in "$CASE_ROOT"/*) ;; *) return 9 ;; esac
    case "$4" in "$CASE_ROOT"/*) ;; *) return 9 ;; esac
    cp -f -- "$3" "$4"
  }
  nginx() { printf '%s\n' "$*" >> "$CASE_ROOT/nginx.log"; return "$MOCK_NGINX_STATUS"; }
  systemctl() { printf '%s\n' "$*" >> "$CASE_ROOT/services.log"; }
  # Avoid platform-dependent symlink privileges on Windows; no service uses these paths.
  ln() { :; }
  mv() { :; }
  curl() { printf 'aws-audit-web:%s\n' "$MOCK_HEALTH_ID"; }
  sleep() { :; }
  source "$TASK_TMP/publish.sh"
)

prepare_case syntax-failure
START=1 MOCK_NGINX_STATUS=1 MOCK_HEALTH_ID=old
set +e
run_publication > "$CASE_ROOT/output" 2>&1
status=$?
set -e
[[ $status != 0 ]] || fail 'nginx syntax failure was accepted'
grep -q '^-t$' "$CASE_ROOT/nginx.log" || fail 'syntax failure did not reach nginx -t'
[[ $(cat "$CONF_PATH") == old-config ]] || fail 'syntax failure did not restore previous config'
[[ ! -s $CASE_ROOT/services.log ]] || fail 'syntax failure reached service activation'
printf 'PASS: nginx -t failure restores previous configuration\n'

prepare_case no-start
START=0 MOCK_NGINX_STATUS=0 MOCK_HEALTH_ID=old
set +e
run_publication > "$CASE_ROOT/output" 2>&1
status=$?
set -e
if [[ $status != 0 ]]; then cat "$CASE_ROOT/output" >&2; fail 'no-start publication failed'; fi
[[ $(cat "$CONF_PATH") == new-config ]] || fail 'no-start did not stage configuration'
[[ ! -s $CASE_ROOT/services.log ]] || fail 'no-start called systemctl'
printf 'PASS: --no-start stages configuration without service calls\n'

prepare_case stale-health
START=1 MOCK_NGINX_STATUS=0 MOCK_HEALTH_ID=old
set +e
run_publication > "$CASE_ROOT/output" 2>&1
status=$?
set -e
[[ $status != 0 ]] || fail 'old release health was accepted as ready'
[[ $(cat "$CONF_PATH") == old-config ]] || fail 'readiness failure did not restore previous config'
grep -q 'Nginx did not serve the new frontend release' "$CASE_ROOT/output" || fail 'readiness failure lacked diagnostic'
grep -q '^reload nginx$' "$CASE_ROOT/services.log" || fail 'rollback did not reload restored configuration'
printf 'PASS: stale release health triggers rollback\n'

prepare_case ready
START=1 MOCK_NGINX_STATUS=0 MOCK_HEALTH_ID=test-new-release
set +e
run_publication > "$CASE_ROOT/output" 2>&1
status=$?
set -e
if [[ $status != 0 ]]; then cat "$CASE_ROOT/output" >&2; fail 'matching health publication failed'; fi
[[ $(cat "$CONF_PATH") == new-config ]] || fail 'ready release was rolled back'
printf 'PASS: matching release health permits publication\n'
