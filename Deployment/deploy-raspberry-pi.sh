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

# Bootstrap entrypoint. This file can be downloaded separately and run before
# the repository has been cloned.
REPO="https://github.com/liflife/HongHuangWorld.git"
BRANCH="${HH_BRANCH:-feature/p0-foundation}"
DEST="${HH_INSTALL_DIR:-$HOME/HongHuangWorld}"
PROXY_URL="${HH_PROXY_URL-http://192.168.124.16:17891}"

log() { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }
[[ $EUID -ne 0 ]] || die "请使用普通用户运行，不要 sudo 整个脚本"
command -v sudo >/dev/null 2>&1 || die "缺少 sudo"
command -v git >/dev/null 2>&1 || die "缺少 git，请先安装 git"
command -v curl >/dev/null 2>&1 || die "缺少 curl，请先安装 curl"
[[ "$(uname -m)" == aarch64 ]] || die "需要 64 位 ARM64 系统（aarch64）"

if [[ -n "$PROXY_URL" ]]; then
  export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL"
  export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
  log "Bootstrap 使用代理：$PROXY_URL"
fi

cleanup() {
  [[ -z "${ASKPASS:-}" ]] || rm -f "$ASKPASS"
  [[ -z "${ASKDIR:-}" ]] || rmdir "$ASKDIR" 2>/dev/null || true
}
trap cleanup EXIT

if [[ -d "$DEST/.git" ]]; then
  read -r -p "更新现有仓库到 origin/$BRANCH？[Y/n] " answer
  [[ "$answer" =~ ^[Nn]$ ]] && log "保留现有代码，继续部署" || {
    read -r -s -p "GitHub Token（Contents: Read）： " TOKEN; echo
    [[ -n "$TOKEN" ]] || die "GitHub Token 不能为空"
    ASKDIR="$(mktemp -d)"; ASKPASS="$ASKDIR/askpass"
    cat > "$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in *Username*) echo x-access-token;; *Password*) printf '%s\\n' "$HH_GITHUB_TOKEN";; *) exit 1;; esac
EOF
    chmod 700 "$ASKPASS"
    export HH_GITHUB_TOKEN="$TOKEN" GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0
    unset TOKEN
    git -C "$DEST" fetch origin "$BRANCH"
    git -C "$DEST" checkout "$BRANCH"
    git -C "$DEST" pull --ff-only origin "$BRANCH"
    unset HH_GITHUB_TOKEN GIT_ASKPASS GIT_TERMINAL_PROMPT
    cleanup; ASKPASS=; ASKDIR=
  }
else
  read -r -s -p "GitHub Token（Contents: Read）： " TOKEN; echo
  [[ -n "$TOKEN" ]] || die "GitHub Token 不能为空"
  ASKDIR="$(mktemp -d)"; ASKPASS="$ASKDIR/askpass"
  cat > "$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in *Username*) echo x-access-token;; *Password*) printf '%s\\n' "$HH_GITHUB_TOKEN";; *) exit 1;; esac
EOF
  chmod 700 "$ASKPASS"
  export HH_GITHUB_TOKEN="$TOKEN" GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0
  unset TOKEN
  mkdir -p "$(dirname "$DEST")"
  git clone --single-branch -b "$BRANCH" "$REPO" "$DEST"
  unset HH_GITHUB_TOKEN GIT_ASKPASS GIT_TERMINAL_PROMPT
  cleanup; ASKPASS=; ASKDIR=
fi

[[ -d "$DEST/Deployment/raspberry-pi" ]] || die "仓库缺少 Deployment/raspberry-pi 阶段脚本"
export HH_PROJECT_DIR="$DEST"
export HH_PROXY_URL="$PROXY_URL"
STAGES=(
  00-preflight.sh
  01-proxy.sh
  02-install-deps.sh
  04-configure.sh
  05-infra.sh
  06-migrate.sh
  07-build.sh
  08-install-services.sh
  09-status.sh
)
for stage in "${STAGES[@]}"; do
  log "========== 执行阶段：$stage =========="
  bash "$DEST/Deployment/raspberry-pi/$stage"
done
log "全部部署阶段完成"
