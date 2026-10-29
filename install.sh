#!/usr/bin/env bash
# TUXEDO Control Center 简体中文语言包 —— 安装脚本
#
# 用法：
#   sudo bash install.sh                # 从本目录的 payload/ 安装
#   sudo bash install.sh --payload DIR  # 指定 payload 目录
#
# 原理：Electron 优先加载 resources/app.asar，其次才加载 resources/app 目录。
# 本脚本把 app.asar 解开成 app/ 目录，塞进中文界面后再把 app.asar 改名备份，
# 于是应用改从 app/ 加载。卸载时把备份改回来即可，原文件一个字节都不改。
set -euo pipefail

VERSION="3.1.2-zh1"
RESOURCES="/opt/tuxedo-control-center/resources"
PAYLOAD=""
DO_RESTART=1
DO_USERCONF=1
FORCE=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

die() { echo "错误：$*" >&2; exit 1; }
info() { echo "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --payload) PAYLOAD="${2:-}"; shift 2 ;;
        --resources) RESOURCES="${2:-}"; shift 2 ;;
        --no-restart) DO_RESTART=0; shift ;;
        --skip-user-config) DO_USERCONF=0; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage ;;
        *) die "未知参数：$1（--help 查看用法）" ;;
    esac
done

[ -n "$PAYLOAD" ] || PAYLOAD="$SCRIPT_DIR/payload"
PAYLOAD="$(cd "$PAYLOAD" 2>/dev/null && pwd)" || die "找不到 payload 目录"
[ -d "$PAYLOAD/zh-CN" ] || die "payload 不完整：缺少 zh-CN/"

ASAR="$RESOURCES/app.asar"
BACKUP="$RESOURCES/app.asar.tcczh-backup"
APP_DIR="$RESOURCES/app"

# 默认路径需要 root；--resources 指到别处时允许普通用户（用于测试/绿色安装）
if [ "$RESOURCES" = "/opt/tuxedo-control-center/resources" ] && [ "$(id -u)" -ne 0 ]; then
    die "请用 sudo 运行：sudo bash $0"
fi

command -v python3 >/dev/null || die "需要 python3"
[ -f "$SCRIPT_DIR/lib/asar_extract.py" ] || die "缺少 lib/asar_extract.py"
[ -f "$SCRIPT_DIR/lib/patch_bundles.py" ] || die "缺少 lib/patch_bundles.py"

# ---------- 已有安装则先恢复原始 asar，保证每次都是从官方文件重新打补丁 ----------
if [ ! -f "$ASAR" ]; then
    if [ -f "$BACKUP" ]; then
        info "检测到之前安装过汉化，先恢复原始 app.asar 再重新打补丁…"
        rm -rf "$APP_DIR"
        mv -f "$BACKUP" "$ASAR"
    else
        die "找不到 $ASAR —— TCC 未安装，或安装位置与预期不同"
    fi
fi

FREE_KB=$(df -Pk "$RESOURCES" | awk 'NR==2 {print $4}')
[ "$FREE_KB" -ge 150000 ] || die "磁盘空间不足（需要约 150 MB，当前可用 $((FREE_KB/1024)) MB）"

STAGING="$(mktemp -d /tmp/tcc-zh-cn.XXXXXX)"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

info "① 解开官方 app.asar（约 72 MB）…"
python3 "$SCRIPT_DIR/lib/asar_extract.py" "$ASAR" "$STAGING/app" \
    --unpacked-dir "$RESOURCES/app.asar.unpacked"

APP_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$STAGING/app/package.json" 2>/dev/null || echo unknown)"
info "   检测到 TCC 版本：$APP_VERSION"
case "$APP_VERSION" in
    3.1.*) ;;
    *)
        if [ "$FORCE" -ne 1 ]; then
            die "这个汉化包为 TCC 3.1.x 制作，当前版本 $APP_VERSION 未经验证。确认要装请加 --force"
        fi
        info "   警告：版本未经验证，继续（--force）"
        ;;
esac

info "② 写入中文界面并修改语言菜单…"
python3 "$SCRIPT_DIR/lib/patch_bundles.py" --app "$STAGING/app" --payload "$PAYLOAD"

info "③ 切换为目录加载模式…"
mv -f "$ASAR" "$BACKUP"
rm -rf "$APP_DIR"
mv "$STAGING/app" "$APP_DIR"
chmod -R u+rwX,go+rX "$APP_DIR"
trap - EXIT
rm -rf "$STAGING"
if [ "$(id -u)" -eq 0 ]; then
    chown -R root:root "$APP_DIR"
fi
info "   原文件已备份：$BACKUP"

# ---------- 把当前用户的界面语言设为中文 ----------
if [ "$DO_USERCONF" -eq 1 ] && [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    CONF="$USER_HOME/.tcc/user.conf"
    if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
        mkdir -p "$USER_HOME/.tcc"
        python3 - "$CONF" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}
data["langId"] = "zh-CN"
with open(path, "w") as f:
    json.dump(data, f)
PY
        chown -R "$SUDO_USER" "$USER_HOME/.tcc"
        info "④ 已把界面语言设为中文（$CONF）"
    fi
fi

# ---------- 重启 TCC，让新界面生效 ----------
restart_tcc() {
    local uid="$1"
    pkill -u "$uid" -f '/opt/tuxedo-control-center/tuxedo-control-center' 2>/dev/null || true
    sleep 1
    if [ -n "${DISPLAY:-}" ] && command -v runuser >/dev/null; then
        runuser -u "$(id -un "$uid")" -- env DISPLAY="$DISPLAY" \
            ${XAUTHORITY:+XAUTHORITY="$XAUTHORITY"} \
            nohup /opt/tuxedo-control-center/tuxedo-control-center >/dev/null 2>&1 &
        info "已重新启动 TCC"
        return 0
    fi
    return 1
}

if [ "$DO_RESTART" -eq 1 ] && [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    if ! restart_tcc "$(id -u "$SUDO_USER")"; then
        info "请手动退出并重新打开 TCC（系统托盘图标右键 → Exit，再点启动器）"
    fi
fi

info ""
info "安装完成：TCC 界面已切换为简体中文（$VERSION）"
info "语言按钮可在 English ⇄ 简体中文 之间切换。"
info "卸载：sudo bash \"$SCRIPT_DIR/uninstall.sh\""
