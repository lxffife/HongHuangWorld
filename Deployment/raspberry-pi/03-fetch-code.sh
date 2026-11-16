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
cleanup() { [[ -z "${ASKPASS:-}" ]] || rm -f "$ASKPASS"; [[ -z "${ASKDIR:-}" ]] || rmdir "$ASKDIR" 2>/dev/null || true; }
trap cleanup EXIT
read -r -s -p "GitHub Token（仅需仓库 Contents: Read）： " TOKEN; echo
[[ -n "$TOKEN" ]] || die "GitHub Token 不能为空"
ASKDIR="$(mktemp -d)"; ASKPASS="$ASKDIR/askpass"
cat > "$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in *Username*) echo x-access-token;; *Password*) printf '%s\n' "$HH_GITHUB_TOKEN";; *) exit 1;; esac
EOF
chmod 700 "$ASKPASS"
export HH_GITHUB_TOKEN="$TOKEN" GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0
unset TOKEN
if [[ -d "$HH_PROJECT_DIR/.git" ]]; then
  log "更新仓库：$HH_BRANCH"
  git -C "$HH_PROJECT_DIR" fetch origin "$HH_BRANCH"
  git -C "$HH_PROJECT_DIR" checkout "$HH_BRANCH"
  git -C "$HH_PROJECT_DIR" pull --ff-only origin "$HH_BRANCH"
else
  mkdir -p "$(dirname "$HH_PROJECT_DIR")"
  log "克隆仓库：$HH_BRANCH"
  git clone --single-branch -b "$HH_BRANCH" "$HH_REPO" "$HH_PROJECT_DIR"
fi
unset HH_GITHUB_TOKEN GIT_ASKPASS GIT_TERMINAL_PROMPT
log "代码获取完成：$HH_PROJECT_DIR"
