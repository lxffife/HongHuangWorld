#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${HH_ENV_FILE:-$ROOT_DIR/Deployment/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing environment file: $ENV_FILE" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
: "${IDENTITY_DATABASE_URL:?IDENTITY_DATABASE_URL is required}"
: "${IDENTITY_INTERNAL_API_KEY:?IDENTITY_INTERNAL_API_KEY is required}"
cd "$ROOT_DIR/Backend"
exec go run ./cmd/identity
