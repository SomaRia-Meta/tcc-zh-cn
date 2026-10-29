#!/usr/bin/env bash
# 从上游源码重新生成 payload/zh-CN（可复现的构建流程）
#
# 用法：
#   ./tools/build-zh-bundle.sh                 # 克隆上游 v3.1.1 并构建
#   ./tools/build-zh-bundle.sh --src-dir DIR   # 复用已有源码目录（需已 npm ci）
#   ./tools/build-zh-bundle.sh --tag v3.1.1 --out payload
#
# 需要：node >= 20、npm、网络（首次克隆和 npm ci）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="v3.1.1"
SRC_DIR=""
OUT="$ROOT/payload"
UPSTREAM="https://github.com/tuxedocomputers/tuxedo-control-center.git"

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="$2"; shift 2 ;;
        --src-dir) SRC_DIR="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 1 ;;
    esac
done

TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

if [ -z "$SRC_DIR" ]; then
    TMP="$(mktemp -d)"
    echo "① 克隆上游 $TAG …"
    git clone --depth 1 --branch "$TAG" "$UPSTREAM" "$TMP/src"
    SRC_DIR="$TMP/src"
    echo "② 安装依赖（npm ci，会比较慢）…"
    (cd "$SRC_DIR" && ELECTRON_SKIP_BINARY_DOWNLOAD=1 npm ci --ignore-scripts --no-audit --no-fund)
fi

command -v npx >/dev/null || { echo "需要 node/npm" >&2; exit 1; }
[ -f "$ROOT/i18n/lang.zh-CN.xlf" ] || { echo "缺少 i18n/lang.zh-CN.xlf" >&2; exit 1; }

echo "③ 注入 zh-CN 语言文件与配置…"
cp "$ROOT/i18n/lang.zh-CN.xlf" "$SRC_DIR/src/ng-app/assets/locale/lang.zh-CN.xlf"
python3 - "$SRC_DIR" <<'PY'
import json, re, sys
src = sys.argv[1]

# angular.json: 注册 zh-CN locale
p = src + "/angular.json"
d = json.load(open(p))
locales = d["projects"]["tuxedo-control-center"]["i18n"]["locales"]
if "zh-CN" not in locales:
    locales["zh-CN"] = {
        "translation": "src/ng-app/assets/locale/lang.zh-CN.xlf",
        "baseHref": "",
    }
    json.dump(d, open(p, "w"), indent=2)
    print("  angular.json: 已加入 zh-CN")
else:
    print("  angular.json: 已存在 zh-CN")

# 语言菜单：英文后面插入中文
p = src + "/src/ng-app/app/utils.service.ts"
s = open(p).read()
if "zh-CN" not in s:
    s = s.replace(
        "        { id: 'en', label: 'English', img: 'english.svg' },\n",
        "        { id: 'en', label: 'English', img: 'english.svg' },\n"
        "        { id: 'zh-CN', label: '简体中文', img: 'icon_language.svg' },\n",
        1,
    )
    open(p, "w").write(s)
    print("  utils.service.ts: 已加入简体中文")
else:
    print("  utils.service.ts: 已存在简体中文")

# 注册 Angular 中文 locale 数据（DecimalPipe 等需要）
p = src + "/src/ng-app/app/app.module.ts"
s = open(p).read()
if "locales/zh-Hans" not in s:
    s = s.replace(
        "import localeDeExtra from '@angular/common/locales/extra/de';",
        "import localeDeExtra from '@angular/common/locales/extra/de';\n"
        "import localeZh from '@angular/common/locales/zh-Hans';\n"
        "import localeZhExtra from '@angular/common/locales/extra/zh-Hans';",
        1,
    )
    s = s.replace(
        "registerLocaleData(localeDe, 'de', localeDeExtra);",
        "registerLocaleData(localeDe, 'de', localeDeExtra);\n"
        "registerLocaleData(localeZh, 'zh-CN', localeZhExtra);",
        1,
    )
    open(p, "w").write(s)
    print("  app.module.ts: 已注册 zh-Hans locale 数据")

# 后台语言白名单
p = src + "/src/e-app/backendAPIs/initMain.ts"
s = open(p).read()
if "'zh-CN'" not in s:
    s = s.replace(
        "const availableLanguages: string[] = ['en', 'de'];",
        "const availableLanguages: string[] = ['en', 'de', 'zh-CN'];",
        1,
    )
    open(p, "w").write(s)
    print("  initMain.ts: 已加入 zh-CN")
else:
    print("  initMain.ts: 已存在 zh-CN")
PY

echo "④ 编译 Angular（production + localize，约 1 分钟）…"
cp "$SRC_DIR/CHANGELOG.md" "$SRC_DIR/src/ng-app/assets/" 2>/dev/null || true
(cd "$SRC_DIR" && npx ng build --configuration production --aot true --optimization true)

BUILT="$SRC_DIR/dist/tuxedo-control-center/ng-app/browser/zh-CN"
[ -d "$BUILT" ] || { echo "构建失败：找不到 $BUILT" >&2; exit 1; }

echo "⑤ 写入 payload …"
rm -rf "$OUT/zh-CN"
mkdir -p "$OUT"
cp -a "$BUILT" "$OUT/zh-CN"
cp "$ROOT/i18n/lang.zh-CN.xlf" "$OUT/lang.zh-CN.xlf"
du -sh "$OUT/zh-CN"
echo "完成。可以用 make dist 打包。"
