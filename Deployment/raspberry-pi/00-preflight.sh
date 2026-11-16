#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"
[[ "$(uname -m)" == aarch64 ]] || die "需要 64 位 ARM64 系统（aarch64），当前：$(uname -m)"
[[ "$(getconf LONG_BIT)" == 64 ]] || die "当前系统不是 64 位"
[[ $EUID -ne 0 ]] || die "请使用普通用户运行，不要 sudo 整个脚本"
need_cmd sudo; need_cmd apt-get; need_cmd git; need_cmd curl
sudo -v
log "系统检查通过：$(. /etc/os-release; echo "$PRETTY_NAME") / $(uname -m)"
log "项目目录：$HH_PROJECT_DIR"
