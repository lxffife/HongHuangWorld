#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"
echo "=== API ==="; systemctl --no-pager --full status honghuang-api || true
echo "=== WorldServer ==="; systemctl --no-pager --full status honghuang-world-server || true
echo "=== API readiness ==="; curl -i --max-time 5 http://127.0.0.1:8787/ready || true
if [[ -f "$HH_ENV_FILE" ]]; then load_env; echo "=== Containers ==="; compose ps; fi
