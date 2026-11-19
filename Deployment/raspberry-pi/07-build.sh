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
need_cmd go; need_cmd cmake; need_cmd pkg-config

# AdminWeb is a static frontend: rebuild only on first deployment or when
# frontend source/dependency/build configuration is newer than dist/index.html.
ADMIN_WEB_DIR="$HH_PROJECT_DIR/AdminWeb"
ADMIN_DIST="$ADMIN_WEB_DIR/dist/index.html"
ADMIN_NEEDS_BUILD=0
if [ ! -f "$ADMIN_DIST" ]; then
  ADMIN_NEEDS_BUILD=1
elif find "$ADMIN_WEB_DIR/src" "$ADMIN_WEB_DIR/public" -type f -newer "$ADMIN_DIST" -print -quit 2>/dev/null | grep -q .; then
  ADMIN_NEEDS_BUILD=1
elif [ "$ADMIN_WEB_DIR/package.json" -nt "$ADMIN_DIST" ] || [ "$ADMIN_WEB_DIR/package-lock.json" -nt "$ADMIN_DIST" ] || [ "$ADMIN_WEB_DIR/vite.config.ts" -nt "$ADMIN_DIST" ] || [ "$ADMIN_WEB_DIR/vite.config.js" -nt "$ADMIN_DIST" ]; then
  ADMIN_NEEDS_BUILD=1
fi
if [ "$ADMIN_NEEDS_BUILD" -eq 1 ]; then
  need_cmd npm
  cd "$ADMIN_WEB_DIR"
  if [ ! -d node_modules ] || { [ -f package-lock.json ] && [ -f node_modules/.package-lock.json ] && [ package-lock.json -nt node_modules/.package-lock.json ]; }; then
    if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
  fi
  npm run build
  cd "$HH_PROJECT_DIR"
  log "AdminWeb 前端已更新并完成构建"
else
  log "AdminWeb 前端源码未变化，跳过 npm 构建"
fi
if ! pkg-config --exists sqlite3; then
  echo "[ERROR] 缺少 SQLite3 开发文件（头文件/库）。请先执行：" >&2
  echo "  sudo apt-get update && sudo apt-get install -y libsqlite3-dev" >&2
  echo "安装后重新运行：bash Deployment/raspberry-pi/07-build.sh" >&2
  exit 1
fi
mkdir -p "$HH_PROJECT_DIR/bin"
(cd "$HH_PROJECT_DIR/Backend" && go mod tidy && go mod download && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o "$HH_PROJECT_DIR/bin/honghuang-api" ./cmd/api && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o "$HH_PROJECT_DIR/bin/honghuang-identity" ./cmd/identity && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o "$HH_PROJECT_DIR/bin/honghuang-admin" ./cmd/admin && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o "$HH_PROJECT_DIR/bin/honghuang-chat" ./cmd/chat)
cmake -S "$HH_PROJECT_DIR/GameServer/WorldServer" -B "$HH_PROJECT_DIR/build/world-server" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build "$HH_PROJECT_DIR/build/world-server" --parallel "${HH_BUILD_JOBS:-2}"
ctest --test-dir "$HH_PROJECT_DIR/build/world-server" --output-on-failure
install -m 755 "$HH_PROJECT_DIR/build/world-server/world_server" "$HH_PROJECT_DIR/bin/world_server"
log "Go API、Identity、Admin、Chat 与 WorldServer 构建、CTest 完成"
