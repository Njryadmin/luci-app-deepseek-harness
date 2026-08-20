#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# scripts/ar_pack.py — 纯 Python ar 归档打包器
#
# 用途:替代 GNU tar -cf 生成 .ipk / .deb 兼容的 ar 归档。
# OpenWrt opkg 通过 libarchive 解析 ar 格式,要求:
#   - magic: !<arch>\n
#   - name 字段以 '/' 分隔 (GNU ar 标准)
#   - 所有数字字段 (mtime/uid/gid/mode/size) 右对齐空格填充
#   - fmag: `\x60\x0a` (backtick + LF)
# Git Bash / Windows 上 ar 命令不一定可用,所以用 Python 实现。
#
# ar 格式 (60 字节头):
#   name[16]   mtime[12]   uid[6]   gid[6]   mode[8]   size[10]   fmag[2]
# 字段类型:
#   name:     字符 + '/' 终止 + 空格填充
#   mtime/uid/gid/size: 十进制整数,右对齐空格
#   mode:     八进制整数,右对齐空格
#   fmag:     常量 "`\n"
# 数据后如果 size 是奇数,补 1 字节 LF
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
        if len(name) > 15:
            sys.exit(f"ar_pack: member name too long (>15): {name!r}")
        # ar 头:固定 60 字节,字段右对齐空格填充(GNU ar 标准)
        # 数字字段用 > 右对齐空格
        hdr = (
            f"{name + '/':<16}"          # name + '/' 分隔,左对齐空格
            f"{0:>12}"                    # mtime,右对齐
            f"{0:>6}"                     # uid
            f"{0:>6}"                     # gid
            f"{0o100644:>8}"              # mode (octal)
            f"{len(data):>10}"            # size,右对齐
            "\x60\x0a"                    # fmag = backtick + LF
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
