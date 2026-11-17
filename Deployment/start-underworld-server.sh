#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/Deployment/.env"
if [[ ! -f "$ENV_FILE" ]]; then echo "Missing Deployment/.env" >&2; exit 1; fi

# Load the shared backend URL and secret, then isolate this server's identity.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${BACKEND_URL:?Missing BACKEND_URL in Deployment/.env}"
: "${WORLD_SERVER_API_KEY:?Missing WORLD_SERVER_API_KEY in Deployment/.env}"
: "${WORLD_SERVER_ADVERTISE_HOST:?Missing WORLD_SERVER_ADVERTISE_HOST in Deployment/.env}"

export WORLD_SERVER_NODE_KEY="honghuang-underworld-node-01"
export WORLD_ID="underworld_fengdu"
export WORLD_SERVER_INSTANCE_KEY="fengdu-local-1"
export WORLD_SERVER_UDP_PORT="7778"
export WORLD_SERVER_BIND="0.0.0.0"
export WORLD_SERVER_CAPACITY="100"
export WORLD_SERVER_OUTBOX_PATH="${ROOT_DIR}/data/worldserver-underworld-outbox.sqlite3"

BIN="${ROOT_DIR}/build/world-server/world_server"
if [[ ! -x "$BIN" ]]; then echo "WorldServer binary not found: $BIN. Build it first." >&2; exit 1; fi

echo "[HongHuang] Starting Fengdu Underworld WorldServer: ${WORLD_SERVER_ADVERTISE_HOST}:7778"
echo "[HongHuang] Qingyun WorldServer on UDP 7777 remains untouched."
exec "$BIN"