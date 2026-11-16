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
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
need_cmd go; need_cmd cmake
mkdir -p "$HH_PROJECT_DIR/bin"
(cd "$HH_PROJECT_DIR/Backend" && go mod download && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o "$HH_PROJECT_DIR/bin/honghuang-api" ./cmd/api)
cmake -S "$HH_PROJECT_DIR/GameServer/WorldServer" -B "$HH_PROJECT_DIR/build/world-server" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build "$HH_PROJECT_DIR/build/world-server" --parallel "${HH_BUILD_JOBS:-2}"
ctest --test-dir "$HH_PROJECT_DIR/build/world-server" --output-on-failure
install -m 755 "$HH_PROJECT_DIR/build/world-server/world_server" "$HH_PROJECT_DIR/bin/world_server"
log "Go API 与 WorldServer 构建、CTest 完成"
