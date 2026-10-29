#!/usr/bin/env bash
# TUXEDO Control Center 简体中文语言包 —— 卸载脚本
#
# 用法：sudo bash uninstall.sh
#
# 删除 app/ 目录并把备份的 app.asar 改回来，恢复成官方原版界面。
set -euo pipefail

RESOURCES="/opt/tuxedo-control-center/resources"
DO_RESTART=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "错误：$*" >&2; exit 1; }
info() { echo "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --resources) RESOURCES="${2:-}"; shift 2 ;;
        --no-restart) DO_RESTART=0; shift ;;
        -h|--help)
            echo "用法：sudo bash $0 [--resources DIR] [--no-restart]"
            exit 0 ;;
        *) die "未知参数：$1" ;;
    esac
done

ASAR="$RESOURCES/app.asar"
BACKUP="$RESOURCES/app.asar.tcczh-backup"
APP_DIR="$RESOURCES/app"

if [ "$RESOURCES" = "/opt/tuxedo-control-center/resources" ] && [ "$(id -u)" -ne 0 ]; then
    die "请用 sudo 运行：sudo bash $0"
fi

if [ ! -d "$APP_DIR" ]; then
    info "没有检测到已安装的中文界面，无需卸载。"
else
    [ -f "$BACKUP" ] || die "找到 $APP_DIR，但备份 $BACKUP 不存在，无法安全恢复。"
    rm -rf "$APP_DIR"
    mv -f "$BACKUP" "$ASAR"
    info "已删除中文界面并恢复官方 app.asar"
fi

# 把语言设置切回英文
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    CONF="$USER_HOME/.tcc/user.conf"
    if [ -f "$CONF" ]; then
        python3 - "$CONF" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}
if data.get("langId") == "zh-CN":
    data["langId"] = "en"
    with open(path, "w") as f:
        json.dump(data, f)
PY
        chown "$SUDO_USER" "$CONF" 2>/dev/null || true
    fi
fi

if [ "$DO_RESTART" -eq 1 ] && [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    pkill -u "$(id -u "$SUDO_USER")" -f '/opt/tuxedo-control-center/tuxedo-control-center' 2>/dev/null || true
    sleep 1
    if [ -n "${DISPLAY:-}" ] && command -v runuser >/dev/null; then
        runuser -u "$SUDO_USER" -- env DISPLAY="$DISPLAY" \
            ${XAUTHORITY:+XAUTHORITY="$XAUTHORITY"} \
            nohup /opt/tuxedo-control-center/tuxedo-control-center >/dev/null 2>&1 &
        info "已重新启动 TCC（英文界面）"
    else
        info "请手动重新打开 TCC"
    fi
fi

info "卸载完成，已恢复官方原版界面。"
