#!/usr/bin/env python3
"""把中文界面补丁写进已解开的 TCC 应用目录。

做四件事：
1. 复制 payload/zh-CN/ 到 dist/tuxedo-control-center/ng-app/browser/zh-CN/
2. 复制 lang.zh-CN.xlf（托盘等主进程文案用）到 browser/en-US/assets/locale/
3. 给 en / de / en-US 三个原有界面的 languagesMenuArray 追加“简体中文”一项
   （并把中文排在英语之后，这样左下角语言按钮是 English ⇄ 简体中文）
4. 后台的 availableLanguages 里加入 zh-CN

任何一步找不到预期内容都会直接报错退出，调用方应在改动 /opt 之前运行。
"""

import argparse
import glob
import os
import re
import shutil
import sys

ZH_ENTRY = '{id:"zh-CN",label:"简体中文",img:"%s"}'
BROWSER = "dist/tuxedo-control-center/ng-app/browser"


def fail(msg):
    print("错误：" + msg, file=sys.stderr)
    sys.exit(1)


def patch_language_menu(app_dir, locales):
    for loc in locales:
        files = glob.glob(os.path.join(app_dir, BROWSER, loc, "main-*.js"))
        if len(files) != 1:
            fail("在 browser/%s 下找到 %d 个 main-*.js（应为 1 个）" % (loc, len(files)))
        path = files[0]
        with open(path, encoding="utf-8") as f:
            src = f.read()

        m = re.search(r"languagesMenuArray=\[(.*?)\];", src, re.S)
        if not m:
            fail("browser/%s 里找不到 languagesMenuArray" % loc)
        array = m.group(1)
        if '"zh-CN"' in array or "'zh-CN'" in array:
            print("  %s: 已有中文项，跳过" % loc)
            continue
        if 'id:"en"' not in array:
            fail("browser/%s 的 languagesMenuArray 结构不符合预期" % loc)

        icon = "icon_language.svg"
        if not os.path.exists(os.path.join(app_dir, BROWSER, loc, "assets", "images", icon)):
            icon = "english.svg"
        entry = ZH_ENTRY % icon
        # 插在英文项后面，保证“切换语言”按钮是 English <-> 简体中文
        end_en = array.index("}", array.index('id:"en"')) + 1
        new_array = array[:end_en] + "," + entry + array[end_en:]
        src = src[: m.start(1)] + new_array + src[m.end(1):]
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
        print("  %s: 已追加简体中文" % loc)


def patch_available_languages(app_dir):
    path = os.path.join(app_dir, "dist/tuxedo-control-center/e-app/e-app/backendAPIs/initMain.js")
    if not os.path.exists(path):
        fail("找不到 initMain.js")
    with open(path, encoding="utf-8") as f:
        src = f.read()
    m = re.search(r"availableLanguages = \[([^\]]*)\]", src)
    if not m:
        fail("initMain.js 里找不到 availableLanguages")
    if "zh-CN" in m.group(1):
        print("  initMain: 已有 zh-CN，跳过")
    else:
        src = src[: m.start(1)] + m.group(1).rstrip() + ", 'zh-CN'" + src[m.end(1):]
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
        print("  initMain: 已加入 zh-CN")


TRAY_LABELS = [
    ("Activate profile temporarily", "临时激活配置"),
    ("Aquaris control", "Aquaris 控制"),
    ("Profiles", "配置"),
    ("Tray autostart", "托盘自启动"),
    ("Power save blocker", "阻止节能"),
    ("Fn-Lock", "Fn 锁定"),
    ("Graphics", "显卡"),
    ("Select dGPU", "选择独显"),
    ("Apply on-demand mode", "应用按需模式"),
    ("Select iGPU", "选择核显"),
    ("Exit", "退出"),
]


def patch_tray_labels(app_dir):
    """托盘右键菜单的文案在上游是硬编码的，这里直接替换编译后的字符串。"""
    path = os.path.join(app_dir, "dist/tuxedo-control-center/e-app/e-app/TccTray.js")
    if not os.path.exists(path):
        print("  警告：找不到 TccTray.js，跳过托盘菜单汉化", file=sys.stderr)
        return
    with open(path, encoding="utf-8") as f:
        src = f.read()
    changed = 0
    for en, zh in TRAY_LABELS:
        needle = "label: '%s'" % en
        done = "label: '%s'" % zh
        if needle in src:
            src = src.replace(needle, done)
            changed += 1
        elif done not in src:
            print("  警告：托盘菜单里找不到 %r（版本可能不同）" % en, file=sys.stderr)
    if changed:
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
        print("  托盘菜单：已汉化 %d 项" % changed)
    else:
        print("  托盘菜单：已是中文，跳过")


def install_payload(app_dir, payload_dir):
    src = os.path.join(payload_dir, "zh-CN")
    dst = os.path.join(app_dir, BROWSER, "zh-CN")
    if not os.path.isdir(src):
        fail("payload 里缺少 zh-CN 目录: " + src)
    if not os.path.exists(os.path.join(src, "index.html")):
        fail("payload/zh-CN/index.html 不存在，payload 不完整")
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    print("  已安装中文界面 -> browser/zh-CN")

    xlf = os.path.join(payload_dir, "lang.zh-CN.xlf")
    if not os.path.exists(xlf):
        fail("payload 里缺少 lang.zh-CN.xlf")
    for loc in ("en-US", "zh-CN"):
        target_dir = os.path.join(app_dir, BROWSER, loc, "assets", "locale")
        os.makedirs(target_dir, exist_ok=True)
        shutil.copy2(xlf, os.path.join(target_dir, "lang.zh-CN.xlf"))
    print("  已安装托盘语言文件 lang.zh-CN.xlf")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True, help="解开的 TCC 应用目录")
    ap.add_argument("--payload", required=True, help="payload 目录（含 zh-CN/ 和 lang.zh-CN.xlf）")
    args = ap.parse_args()

    app_dir = os.path.abspath(args.app)
    if not os.path.exists(os.path.join(app_dir, BROWSER)):
        fail("这不是 TCC 应用目录（缺少 %s）" % BROWSER)

    print("写入中文界面…")
    install_payload(app_dir, os.path.abspath(args.payload))
    print("修改语言菜单…")
    patch_language_menu(app_dir, ["en", "de", "en-US"])
    print("修改语言列表…")
    patch_available_languages(app_dir)
    print("汉化托盘菜单…")
    patch_tray_labels(app_dir)


if __name__ == "__main__":
    main()
