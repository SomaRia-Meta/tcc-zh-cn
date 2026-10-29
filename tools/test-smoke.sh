#!/usr/bin/env bash
# 冒烟测试：把本机已安装的 app.asar 复制到临时“假根目录”，
# 跑一遍 install.sh / uninstall.sh，检查中文界面是否写入、原文件是否还原。
# 不需要 root，也不会改动系统里的 /opt。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="${1:-/opt/tuxedo-control-center/resources}"

[ -f "$RES/app.asar" ] || {
    echo "跳过：$RES/app.asar 不存在（先安装 tuxedo-control-center，或把路径作为参数传入）"
    exit 0
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/resources"
cp "$RES/app.asar" "$TMP/resources/app.asar"
[ -d "$RES/app.asar.unpacked" ] && cp -a "$RES/app.asar.unpacked" "$TMP/resources/"

echo "== 安装到假根目录 =="
bash "$ROOT/install.sh" --resources "$TMP/resources" --no-restart --skip-user-config

[ -f "$TMP/resources/app/dist/tuxedo-control-center/ng-app/browser/zh-CN/index.html" ] \
    || { echo "失败：中文界面没有写入"; exit 1; }
grep -q 'zh-CN' "$TMP/resources/app/dist/tuxedo-control-center/ng-app/browser/en/main-"*.js \
    || { echo "失败：英文界面里没有加入中文语言项"; exit 1; }
grep -q "zh-CN" "$TMP/resources/app/dist/tuxedo-control-center/e-app/e-app/backendAPIs/initMain.js" \
    || { echo "失败：initMain 没有加入 zh-CN"; exit 1; }
grep -q "临时激活配置" "$TMP/resources/app/dist/tuxedo-control-center/e-app/e-app/TccTray.js" \
    || { echo "失败：托盘菜单没有汉化"; exit 1; }
echo "OK：中文界面已写入"

echo "== 卸载 =="
bash "$ROOT/uninstall.sh" --resources "$TMP/resources" --no-restart
[ -f "$TMP/resources/app.asar" ] || { echo "失败：app.asar 没有还原"; exit 1; }
[ ! -d "$TMP/resources/app" ] || { echo "失败：app/ 目录没有删除"; exit 1; }
cmp -s "$RES/app.asar" "$TMP/resources/app.asar" || { echo "失败：还原的 app.asar 与原始文件不一致"; exit 1; }
echo "OK：已完整还原"

echo "冒烟测试通过 ✅"
