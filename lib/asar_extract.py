#!/usr/bin/env python3
"""从 Electron app.asar 归档中解出全部文件（纯标准库实现，不依赖 node/npm）。

用法:
    python3 asar_extract.py <app.asar> <目标目录> [--unpacked-dir <app.asar.unpacked>]

asar 的格式（Electron / @electron/asar v2-v3）大致是：
    [uint32 = 4][uint32 头长度][uint32 json 长度][uint32 预留]
    [JSON 目录树][按 4 字节对齐][文件内容拼接]

这里不依赖那几个长度字段的精确语义，而是：
1) 在前 64 字节里找到以 {"files" 开头的 JSON；
2) 用括号计数（跳过字符串）找到 JSON 结尾；
3) 从 JSON 结尾按 4 字节对齐推测数据区起点，并用 package.json 的实际内容校验，
   失败则依次尝试几种对齐方式。
"""

import json
import os
import shutil
import struct
import sys


class AsarError(Exception):
    pass


def find_json(data: bytes) -> int:
    # 标准位置是 16，但不同版本可能不同，直接找 {"files"
    idx = data.find(b'{"files"')
    if idx < 0:
        raise AsarError("找不到 asar 头（不是有效的 app.asar？）")
    if idx > 64:
        raise AsarError("asar 头位置异常: %d" % idx)
    return idx


def scan_json_end(data: bytes, start: int) -> int:
    depth = 0
    in_str = False
    esc = False
    for i in range(start, len(data)):
        c = data[i]
        if in_str:
            if esc:
                esc = False
            elif c == 0x5C:  # backslash
                esc = True
            elif c == 0x22:  # quote
                in_str = False
            continue
        if c == 0x22:
            in_str = True
        elif c == 0x7B:  # {
            depth += 1
        elif c == 0x7D:  # }
            depth -= 1
            if depth == 0:
                return i + 1
    raise AsarError("asar 头 JSON 不完整")


def load_header(f, data_head: bytes):
    idx = find_json(data_head)
    # 头部 JSON 可能超过 64 字节，重新按需读取
    f.seek(idx)
    data = f.read()
    end = scan_json_end(data, 0)
    header = json.loads(data[:end].decode("utf-8"))
    return header, idx, end


def walk(node, prefix=""):
    for name, value in node.get("files", {}).items():
        path = prefix + "/" + name
        if "files" in value:
            yield from walk(value, path)
        else:
            yield path, value


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__.strip())
        return 2
    asar_path = sys.argv[1]
    dest = sys.argv[2]
    unpacked_dir = None
    if "--unpacked-dir" in sys.argv:
        unpacked_dir = sys.argv[sys.argv.index("--unpacked-dir") + 1]

    with open(asar_path, "rb") as f:
        head = f.read(4096)
        header, json_start, json_end = load_header(f, head)
        files = list(walk(header))

        # 找 package.json 作为数据区起点的校验样本
        probe = next((v for p, v in files if p == "/package.json" and "offset" in v), None)
        if probe is None:
            raise AsarError("asar 里没有 /package.json，无法校验数据区")

        candidates = []
        base = json_start + json_end
        for pad in range(0, 9):
            candidates.append(base + pad)
        data_start = None
        for cand in candidates:
            try:
                f.seek(cand + int(probe["offset"]))
                blob = f.read(int(probe["size"]))
                json.loads(blob.decode("utf-8"))
                data_start = cand
                break
            except Exception:
                continue
        if data_start is None:
            raise AsarError("无法确定 asar 数据区起始位置")

        if os.path.isdir(dest):
            shutil.rmtree(dest)
        os.makedirs(dest)

        count = 0
        for path, meta in files:
            target = dest + path
            if "link" in meta:
                os.makedirs(os.path.dirname(target), exist_ok=True)
                if os.path.lexists(target):
                    os.remove(target)
                os.symlink(meta["link"], target)
                continue
            if meta.get("unpacked"):
                # 这些文件在 app.asar.unpacked/ 里，最后统一拷贝
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            f.seek(data_start + int(meta["offset"]))
            blob = f.read(int(meta["size"]))
            with open(target, "wb") as out:
                out.write(blob)
            if meta.get("executable"):
                os.chmod(target, 0o755)
            count += 1

        if unpacked_dir and os.path.isdir(unpacked_dir):
            for root, _dirs, names in os.walk(unpacked_dir):
                rel = os.path.relpath(root, unpacked_dir)
                for name in names:
                    src = os.path.join(root, name)
                    out_dir = dest if rel == "." else os.path.join(dest, rel)
                    os.makedirs(out_dir, exist_ok=True)
                    shutil.copy2(src, os.path.join(out_dir, name))

    print("已解开 %d 个文件 -> %s" % (count, dest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
