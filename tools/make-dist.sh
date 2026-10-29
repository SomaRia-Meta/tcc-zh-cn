#!/usr/bin/env bash
# 生成发布产物：dist/tcc-zh-cn-<版本>.tar.gz 和 dist/tcc-zh-cn_<版本>_all.deb
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
NAME="tcc-zh-cn"
DIST="$ROOT/dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PKG_FILES=(install.sh uninstall.sh lib payload README.md LICENSE VERSION)
for f in "${PKG_FILES[@]}"; do
    [ -e "$ROOT/$f" ] || { echo "缺少 $f" >&2; exit 1; }
done

rm -rf "$DIST"
mkdir -p "$DIST"

# ---------- 1. 通用压缩包（任意发行版可用） ----------
STAGE="$WORK/$NAME-$VERSION"
mkdir -p "$STAGE"
for f in "${PKG_FILES[@]}"; do cp -a "$ROOT/$f" "$STAGE/"; done
chmod +x "$STAGE/install.sh" "$STAGE/uninstall.sh"
find "$STAGE" -name '__pycache__' -type d -prune -exec rm -rf {} +
tar -C "$WORK" -czf "$DIST/$NAME-$VERSION.tar.gz" "$NAME-$VERSION"
echo "已生成 dist/$NAME-$VERSION.tar.gz"

# ---------- 2. Debian / Ubuntu 安装包 ----------
DEB="$WORK/deb"
mkdir -p "$DEB/DEBIAN" "$DEB/usr/share/$NAME"
for f in "${PKG_FILES[@]}"; do cp -a "$ROOT/$f" "$DEB/usr/share/$NAME/"; done
chmod +x "$DEB/usr/share/$NAME/install.sh" "$DEB/usr/share/$NAME/uninstall.sh"
find "$DEB/usr/share/$NAME" -name '__pycache__' -type d -prune -exec rm -rf {} +
mkdir -p "$DEB/usr/share/doc/$NAME"
cp "$ROOT/README.md" "$DEB/usr/share/doc/$NAME/README.md"
cp "$ROOT/LICENSE" "$DEB/usr/share/doc/$NAME/copyright"

SIZE_KB=$(du -sk --exclude=DEBIAN "$DEB" | cut -f1)
cat > "$DEB/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Installed-Size: $SIZE_KB
Depends: python3, tuxedo-control-center (>= 3.1.0)
Maintainer: tcc-zh-cn maintainers <noreply@example.com>
Homepage: https://github.com/USER/tcc-zh-cn
Description: TUXEDO Control Center simplified Chinese UI (unofficial)
 Unofficial Chinese localization for TUXEDO Control Center. It unpacks
 the installed app.asar, adds a zh-CN web UI build and switches the app
 to directory loading mode. The original app.asar is kept as a backup
 and restored on removal.
 .
 This package is not affiliated with TUXEDO Computers GmbH.
EOF
sed -i "s|^Homepage: .*|Homepage: ${HOMEPAGE:-https://github.com/USER/tcc-zh-cn}|" "$DEB/DEBIAN/control"

cat > "$DEB/DEBIAN/prerm" <<'EOF'
#!/bin/sh
# TCC_ZH_SHARE / TCC_ZH_RESOURCES 仅用于测试时重定向路径
set -e
SHARE="${TCC_ZH_SHARE:-/usr/share/tcc-zh-cn}"
RES="${TCC_ZH_RESOURCES:-/opt/tuxedo-control-center/resources}"
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if [ -x "$SHARE/uninstall.sh" ]; then
        "$SHARE/uninstall.sh" --no-restart --resources "$RES" || true
    fi
fi
exit 0
EOF

cat > "$DEB/DEBIAN/postinst" <<'EOF'
#!/bin/sh
# TCC_ZH_SHARE / TCC_ZH_RESOURCES 仅用于测试时重定向路径
set -e
SHARE="${TCC_ZH_SHARE:-/usr/share/tcc-zh-cn}"
RES="${TCC_ZH_RESOURCES:-/opt/tuxedo-control-center/resources}"
"$SHARE/install.sh" --payload "$SHARE/payload" --no-restart --resources "$RES" >/dev/null
echo ""
echo "TCC 中文界面已安装。如果 TCC 正在运行，请先退出再重新打开才能看到中文。"
echo "卸载：sudo apt remove tcc-zh-cn"
EOF
chmod 755 "$DEB/DEBIAN/prerm" "$DEB/DEBIAN/postinst"

dpkg-deb --build --root-owner-group "$DEB" "$DIST/${NAME}_${VERSION}_all.deb" >/dev/null
echo "已生成 dist/${NAME}_${VERSION}_all.deb"

ls -lh "$DIST"
