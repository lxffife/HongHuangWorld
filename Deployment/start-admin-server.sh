#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/Deployment/.env"
if [[ ! -f "$ENV_FILE" ]]; then echo "Missing Deployment/.env. Copy .env.example to .env first." >&2; exit 1; fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
if [[ -z "${ADMIN_BOOTSTRAP_USERNAME:-}" || -z "${ADMIN_BOOTSTRAP_PASSWORD:-}" ]]; then
  echo "ADMIN_BOOTSTRAP_USERNAME and ADMIN_BOOTSTRAP_PASSWORD are required for first startup." >&2
  exit 1
fi
cd "$ROOT_DIR/Backend"
exec go run ./cmd/admin
