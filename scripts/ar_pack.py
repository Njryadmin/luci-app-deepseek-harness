#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# scripts/ar_pack.py — 纯 Python ar 归档打包器
#
# 用途:替代 GNU tar -cf 生成 .ipk / .deb 兼容的 ar 归档。
# OpenWrt opkg / dpkg 都用 ar 格式解析 ipk/deb。
# Git Bash / Windows 上 ar 命令不一定可用,所以用 Python 实现。
#
# ar 格式:
#   全局头:!<arch>\n (8 字节)
#   每个成员: 60 字节头 + 数据
#     name[16] mtime[12] uid[6] gid[6] mode[8] size[10] fmag[2]
#   如果 size 为奇数,数据后填充 1 字节换行
#
# 用法:
#   python3 ar_pack.py <output> <member1> <member2> ...
# 例:
#   python3 ar_pack.py out.ipk debian-binary control.tar.gz data.tar.gz

import os
import sys


def ar_pack(members: list, out_path: str) -> None:
    """members: list of (name, bytes); out_path: output file path."""
    buf = bytearray(b"!<arch>\n")
    for name, data in members:
        if len(name) > 16:
            sys.exit(f"ar_pack: member name too long (>16): {name!r}")
        # ar 头:固定 60 字节,字段左对齐空格填充
        hdr = (
            f"{name:<16}"
            f"{0:<12}"
            f"{0:<6}"
            f"{0:<6}"
            f"{0o100644:<8}"
            f"{len(data):<10}"
            "\x60\x0a"
        ).encode("ascii")
        buf.extend(hdr)
        buf.extend(data)
        if len(data) % 2:
            buf.extend(b"\n")
    with open(out_path, "wb") as f:
        f.write(buf)


def main() -> int:
    if len(sys.argv) < 3:
        sys.exit("usage: ar_pack.py <output> <member1> <member2> ...")
    out_path = sys.argv[1]
    members = []
    for fn in sys.argv[2:]:
        if not os.path.isfile(fn):
            sys.exit(f"ar_pack: not a file: {fn}")
        with open(fn, "rb") as f:
            members.append((os.path.basename(fn), f.read()))
    ar_pack(members, out_path)
    print(f"OK: {out_path}")
    print(f"Size: {os.path.getsize(out_path)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
