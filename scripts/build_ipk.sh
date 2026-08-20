#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# scripts/build_ipk.sh — 本地构建 .ipk (开发用)
#
# 用法:
#   ./scripts/build_ipk.sh [version] [release]
#   默认 version=1.0.0 release=alpha.1
#
# 输出:dist/luci-app-deepseek-harness_<version>-<release>_all.ipk
#
# .ipk 实际是 tar+gzip 压缩的 tar 归档(不是 ar!)
# 结构(参考 OpenWrt 官方 scripts/ipkg-build):
#   .ipk (gzip)
#     ├─ ./debian-binary   ("2.0\n")
#     ├─ ./control.tar.gz  (gzip)
#     │    ├─ ./control
#     │    └─ ./conffiles
#     └─ ./data.tar.gz     (gzip)
#          ├─ ./usr/...
#          ├─ ./etc/...
#          └─ ...

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-1.0.0}"
RELEASE="${2:-alpha.1}"
PKG_NAME="luci-app-deepseek-harness"

# 1. 检查必备工具
for cmd in tar find gzip; do
	command -v "$cmd" >/dev/null 2>&1 || {
		echo "missing required tool: $cmd" >&2
		exit 1
	}
done

# 2. 准备构建目录
STAGING="/tmp/dsh-build-staging"
if [ -d "$STAGING" ]; then
	find "$STAGING" -mindepth 1 -delete 2>/dev/null || true
fi
mkdir -p "$STAGING"
mkdir -p "$STAGING/CONTROL"
mkdir -p "$STAGING/data/usr/lib/lua/luci"
mkdir -p "$STAGING/data/usr/libexec"
mkdir -p "$STAGING/data/usr/bin"
mkdir -p "$STAGING/data/etc/init.d"
mkdir -p "$STAGING/data/etc/uci-defaults"
mkdir -p "$STAGING/data/etc/config"

# 3. 复制文件
cp -r "$ROOT/luasrc/."   "$STAGING/data/usr/lib/lua/luci/"
cp -r "$ROOT/root/usr/libexec/." "$STAGING/data/usr/libexec/"
cp -r "$ROOT/root/usr/bin/." "$STAGING/data/usr/bin/"
cp    "$ROOT/root/etc/init.d/"*        "$STAGING/data/etc/init.d/"
cp    "$ROOT/root/etc/uci-defaults/"* "$STAGING/data/etc/uci-defaults/"
cp    "$ROOT/root/etc/config/"*       "$STAGING/data/etc/config/"

# 4. 修正权限
find "$STAGING/data" -type f -name '*.sh' -exec chmod 755 {} +
find "$STAGING/data" -type f -name 'dsh-env' -exec chmod 755 {} +
find "$STAGING/data/etc/init.d" -type f -exec chmod 755 {} +
find "$STAGING/data/etc/uci-defaults" -type f -exec chmod 755 {} +

# 5. 写 CONTROL 字段
cat > "$STAGING/CONTROL/control" <<EOF
Package: $PKG_NAME
Version: ${VERSION}-${RELEASE}
Depends: luci-base, lua, curl, wget, ca-bundle, tar, xz, xz-utils, coreutils-stat, coreutils-sha256sum, coreutils-nohup, python3-light
License: Apache-2.0
Section: luci
Architecture: all
Installed-Size: $(du -sb "$STAGING/data" | awk '{print int($1/1024)}')
Description: LuCI front-end for DeepSeek Harness (precompiled bundle approach)
EOF

cat > "$STAGING/CONTROL/conffiles" <<'EOF'
/etc/config/deepseek_harness
EOF

# 6. 打包 (OpenWrt 标准:tar+gzip,不是 ar!)
# 关键:control.tar.gz 和 data.tar.gz 内部 entry 都带 ./ 前缀
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/${PKG_NAME}_${VERSION}-${RELEASE}_all.ipk"

# 6a. control.tar.gz:在 CONTROL 目录里 tar -cf - . | gzip
( cd "$STAGING/CONTROL" && tar --format=gnu --numeric-owner --sort=name \
	-cf - --mtime='@0' . | gzip -n > "$STAGING/control.tar.gz" )

# 6b. data.tar.gz:在 data 目录里 tar -cf - . | gzip
( cd "$STAGING/data" && tar --format=gnu --numeric-owner --sort=name \
	-cf - --mtime='@0' . | gzip -n > "$STAGING/data.tar.gz" )

# 6c. debian-binary
printf "2.0\n" > "$STAGING/debian-binary"

# 6d. 整体:tar -cf - ./debian-binary ./control.tar.gz ./data.tar.gz | gzip > out.ipk
( cd "$STAGING" && tar --format=gnu --numeric-owner --sort=name \
	-cf - --mtime='@0' \
	./debian-binary ./control.tar.gz ./data.tar.gz \
	| gzip -n > "$OUT" )

# 清理
find "$STAGING" -mindepth 1 -delete 2>/dev/null || true

echo "OK: $OUT"
echo "Size: $(stat -c %s "$OUT" 2>/dev/null || stat -f %z "$OUT") bytes"
