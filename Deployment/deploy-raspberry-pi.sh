#!/usr/bin/env bash
set -Eeuo pipefail
# Raspberry Pi ARM64 deployment for HongHuangWorld P0.
REPO="https://github.com/liflife/HongHuangWorld.git"
BRANCH="feature/p0-foundation"
DEST="\${HH_INSTALL_DIR:-$HOME/HongHuangWorld}"
ENV_FILE=/etc/honghuang-world.env
GO_VERSION=1.24.0
[[ "$(uname -m)" == aarch64 ]] || { echo "需要 64 位 ARM64 系统 (aarch64)"; exit 1; }
[[ $EUID -ne 0 ]] || { echo "请用普通用户运行，不要 sudo 整个脚本"; exit 1; }
command -v sudo >/dev/null
command -v apt-get >/dev/null

sudo apt-get update
sudo apt-get install -y ca-certificates curl git build-essential cmake pkg-config libenet-dev libcurl4-openssl-dev nlohmann-json3-dev postgresql-client openssl
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  sudo apt-get install -y docker.io docker-compose-v2
fi
sudo systemctl enable --now docker
if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
"\${DOCKER[@]}" compose version >/dev/null

if ! command -v go >/dev/null || [[ "$(go version | awk '{print $3}')" != "go$GO_VERSION" ]]; then
  tmp="$(mktemp -d)"
  curl -fL --retry 3 "https://go.dev/dl/go\${GO_VERSION}.linux-arm64.tar.gz" -o "$tmp/go.tgz"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$tmp/go.tgz"
  rm -rf "$tmp"
fi
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
grep -q '/usr/local/go/bin' "$HOME/.profile" 2>/dev/null || echo 'export PATH=/usr/local/go/bin:$HOME/go/bin:$PATH' >> "$HOME/.profile"

cleanup() { [[ -z "\${ASKPASS:-}" ]] || rm -f "$ASKPASS"; [[ -z "\${ASKDIR:-}" ]] || rmdir "$ASKDIR" 2>/dev/null || true; }
trap cleanup EXIT
if [[ -d "$DEST/.git" ]]; then
  read -r -p "更新现有仓库到 origin/$BRANCH？[Y/n] " ans
  if [[ ! "$ans" =~ ^[Nn]$ ]]; then
    read -r -s -p "GitHub Token（Contents: Read）：" TOKEN; echo
    [[ -n "$TOKEN" ]] || exit 1
    ASKDIR="$(mktemp -d)"; ASKPASS="$ASKDIR/askpass"
    cat > "$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in *Username*) echo x-access-token;; *Password*) printf '%s\n' "$HH_TOKEN";; *) exit 1;; esac
EOF
    chmod 700 "$ASKPASS"; export HH_TOKEN="$TOKEN" GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0; unset TOKEN
    git -C "$DEST" fetch origin "$BRANCH"
    git -C "$DEST" checkout "$BRANCH"
    git -C "$DEST" pull --ff-only origin "$BRANCH"
    unset HH_TOKEN GIT_ASKPASS GIT_TERMINAL_PROMPT; cleanup; ASKPASS=; ASKDIR=
  fi
else
  mkdir -p "$(dirname "$DEST")"
  read -r -s -p "GitHub Token（Contents: Read）：" TOKEN; echo
  [[ -n "$TOKEN" ]] || exit 1
  ASKDIR="$(mktemp -d)"; ASKPASS="$ASKDIR/askpass"
  cat > "$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in *Username*) echo x-access-token;; *Password*) printf '%s\n' "$HH_TOKEN";; *) exit 1;; esac
EOF
  chmod 700 "$ASKPASS"; export HH_TOKEN="$TOKEN" GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0; unset TOKEN
  git clone --single-branch -b "$BRANCH" "$REPO" "$DEST"
  unset HH_TOKEN GIT_ASKPASS GIT_TERMINAL_PROMPT; cleanup; ASKPASS=; ASKDIR=
fi
cd "$DEST"

if [[ ! -f "$ENV_FILE" ]]; then
  DBPASS="$(openssl rand -hex 24)"
  REDISPASS="$(openssl rand -hex 24)"
  APIKEY="$(openssl rand -hex 32)"
  HOST="\${HH_ADVERTISE_HOST:-$(hostname -I | awk '{print $1}')}"
  [[ -n "$HOST" ]] || { echo "无法识别树莓派 IP，请设置 HH_ADVERTISE_HOST"; exit 1; }
  sudo install -m 600 /dev/null "$ENV_FILE"
  sudo tee "$ENV_FILE" >/dev/null <<EOF
POSTGRES_DB=honghuang
POSTGRES_USER=honghuang
POSTGRES_PASSWORD=$DBPASS
POSTGRES_PORT=5432
REDIS_PASSWORD=$REDISPASS
REDIS_PORT=6379
NATS_PORT=4222
NATS_MONITOR_PORT=8222
HTTP_ADDR=:8787
DATABASE_URL=postgres://honghuang:$DBPASS@127.0.0.1:5432/honghuang?sslmode=disable
REDIS_URL=redis://:$REDISPASS@127.0.0.1:6379/0
NATS_URL=nats://127.0.0.1:4222
WORLD_SERVER_API_KEY=$APIKEY
BACKEND_URL=http://127.0.0.1:8787
WORLD_SERVER_NODE_KEY=honghuang-pi-node-01
WORLD_SERVER_BIND=0.0.0.0
WORLD_SERVER_ADVERTISE_HOST=$HOST
WORLD_SERVER_UDP_PORT=7777
WORLD_SERVER_REGION=home
WORLD_ID=qingyun_human
WORLD_SERVER_INSTANCE_KEY=qingyun-pi-qingyun-01
WORLD_SERVER_CAPACITY=30
EOF
  sudo chmod 600 "$ENV_FILE"
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
[[ -n "\${POSTGRES_PASSWORD:-}" && -n "\${WORLD_SERVER_API_KEY:-}" && -n "\${WORLD_SERVER_ADVERTISE_HOST:-}" ]] || { echo "$ENV_FILE 配置不完整"; exit 1; }

COMPOSE=("\${DOCKER[@]}" compose --env-file "$ENV_FILE" -f "$DEST/Deployment/docker-compose.yml")
"\${COMPOSE[@]}" up -d
for n in $(seq 1 60); do
  "\${COMPOSE[@]}" exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1 && break
  [[ $n -lt 60 ]] || { echo "PostgreSQL 等待超时"; exit 1; }
  sleep 2
done

# Migration ledger: prevents duplicate application on subsequent deployments.
"\${COMPOSE[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE TABLE IF NOT EXISTS schema_migrations(version VARCHAR(16) PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());"
count="$("\${COMPOSE[@]}" exec -T postgres psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'SELECT count(*) FROM schema_migrations;')"
has="$("\${COMPOSE[@]}" exec -T postgres psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT to_regclass('public.accounts') IS NOT NULL;")"
if [[ "$count" == 0 && "$has" == t ]]; then echo "数据库已有 accounts 但无迁移账本，拒绝重复迁移"; exit 1; fi
for f in "$DEST"/Database/migrations/*.up.sql; do
  v="$(basename "$f" | cut -d_ -f1)"
  done_already="$("\${COMPOSE[@]}" exec -T postgres psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version='$v');")"
  [[ "$done_already" == t ]] && continue
  echo "Apply migration $v"
  "\${COMPOSE[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$f"
  "\${COMPOSE[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "INSERT INTO schema_migrations(version) VALUES ('$v');"
done

mkdir -p "$DEST/bin"
(cd "$DEST/Backend" && go mod download && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o "$DEST/bin/honghuang-api" ./cmd/api)
cmake -S "$DEST/GameServer/WorldServer" -B "$DEST/build/world-server" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build "$DEST/build/world-server" --parallel 2
ctest --test-dir "$DEST/build/world-server" --output-on-failure
install -m 755 "$DEST/build/world-server/world_server" "$DEST/bin/world_server"

USER_NAME="$USER"
sudo install -d -o "$USER_NAME" -g "$USER_NAME" /var/log/honghuang
sudo tee /etc/systemd/system/honghuang-api.service >/dev/null <<EOF
[Unit]
Description=HongHuangWorld Go API
After=network-online.target docker.service
Wants=network-online.target
[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$DEST
EnvironmentFile=$ENV_FILE
ExecStart=$DEST/bin/honghuang-api
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
sudo tee /etc/systemd/system/honghuang-world-server.service >/dev/null <<EOF
[Unit]
Description=HongHuangWorld C++ World Server
After=network-online.target docker.service honghuang-api.service
Requires=honghuang-api.service
[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$DEST
EnvironmentFile=$ENV_FILE
ExecStart=$DEST/bin/world_server
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable honghuang-api honghuang-world-server
sudo systemctl restart honghuang-api
for n in $(seq 1 30); do curl -fsS http://127.0.0.1:8787/ready >/dev/null && break; [[ $n -lt 30 ]] || { echo "API 未就绪，查看 journalctl"; exit 1; }; sleep 2; done
sudo systemctl restart honghuang-world-server
echo
echo "部署完成。API: http://$WORLD_SERVER_ADVERTISE_HOST:8787"
echo "WorldServer UDP: $WORLD_SERVER_ADVERTISE_HOST:7777"
echo "日志: sudo journalctl -u honghuang-api -f"
echo "日志: sudo journalctl -u honghuang-world-server -f"
