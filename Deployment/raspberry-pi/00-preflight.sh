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
[[ "$(uname -m)" == aarch64 ]] || die "需要 64 位 ARM64 系统（aarch64），当前：$(uname -m)"
[[ "$(getconf LONG_BIT)" == 64 ]] || die "当前系统不是 64 位"
[[ $EUID -ne 0 ]] || die "请使用普通用户运行，不要 sudo 整个脚本"
need_cmd sudo; need_cmd apt-get; need_cmd git; need_cmd curl
sudo -v
log "系统检查通过：$(. /etc/os-release; echo "$PRETTY_NAME") / $(uname -m)"
log "项目目录：$HH_PROJECT_DIR"
