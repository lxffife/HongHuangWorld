#!/bin/sh
# Re-launch with Bash when invoked as: sh script.sh
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "[ERROR] 本脚本需要 Bash，请先安装 bash。" >&2
  exit 1
fi
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"
echo "=== Identity ==="; systemctl --no-pager --full status honghuang-identity || true
echo "=== Identity readiness ==="; curl -i --max-time 5 http://127.0.0.1:8789/ready || true
echo "=== Chat ==="; systemctl --no-pager --full status honghuang-chat || true
echo "=== Chat readiness ==="; curl -i --max-time 5 http://127.0.0.1:8788/ready || true
echo "=== API ==="; systemctl --no-pager --full status honghuang-api || true
echo "=== Qingyun WorldServer ==="; systemctl --no-pager --full status honghuang-world-server || true
echo "=== Fengdu Underworld WorldServer ==="; systemctl --no-pager --full status honghuang-underworld-server || true
echo "=== API readiness ==="; curl -i --max-time 5 http://127.0.0.1:8787/ready || true
if [[ -f "$HH_ENV_FILE" ]]; then load_env; echo "=== Containers ==="; compose ps; fi
