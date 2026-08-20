#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# dsh-fetch-runtime.sh — 从 GitHub Releases 拉取预编译 dsh runtime bundle
#
# 设计要点:
#   - 完全替代旧的 npm install 路线(monorepo 60+ 子包在 musl 上会全挂)
#   - 多镜像回退:GitHub → npmmirror → 自托管
#   - SHA256 校验,失败立即退出
#   - 调用方负责 stdin 隔离(v0.2.2 教训)
#
# 用法:dsh-fetch-runtime.sh [verify-only]
#   verify-only:只校验已下载的 bundle,不解压

set -eu  # 这里可以 set -e,因为不在 procd 进程树内

# 引用公共路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/dsh-paths.sh"

ARCH="$(detect_arch)"
[ "$ARCH" != "unsupported"* ] || die "architecture not supported: $ARCH"

LIBC="$(detect_libc)"
[ "$LIBC" = "musl" ] || die "libc must be musl (got: $LIBC). iStoreOS 24.10.8 ships musl by default."

# Bundle 名 + SHA256 文件
BUNDLE_NAME="${DSH_BUNDLE_PREFIX}-${LIBC}-${ARCH}-${DSH_BUNDLE_VERSION}.tar.xz"
SHA_NAME="${BUNDLE_NAME}.sha256"
echo_log "target bundle: $BUNDLE_NAME"

# 多镜像回退(优先级从左到右)
MIRRORS="
${DSH_BUNDLE_BASE}/v${DSH_BUNDLE_VERSION}
https://npmmirror.com/mirrors/luci-app-deepseek-harness/${DSH_BUNDLE_VERSION}
"

download_with_fallback() {
	local filename="$1" target="$2"
	for url_base in $MIRRORS; do
		local url="${url_base}/${filename}"
		echo_log "trying $url"
		# curl 优先,wget 回退
		if command -v curl >/dev/null 2>&1; then
			if curl -fsSL --connect-timeout 15 --max-time 600 \
				-o "$target" "$url"; then
				return 0
			fi
		elif command -v wget >/dev/null 2>&1; then
			if wget -q --timeout=600 -O "$target" "$url"; then
				return 0
			fi
		else
			die "neither curl nor wget found"
		fi
		echo_log "mirror failed, trying next..."
	done
	return 1
}

# 1. 准备 staging 目录
mkdir -p "$DSH_STAGING"
BUNDLE_PATH="$DSH_STAGING/$BUNDLE_NAME"
SHA_PATH="$DSH_STAGING/$SHA_NAME"

# 2. 拉 SHA256 文件
if ! download_with_fallback "$SHA_NAME" "$SHA_PATH"; then
	die "failed to download SHA256 from any mirror"
fi

EXPECTED_SHA="$(awk '{print $1}' "$SHA_PATH" | head -1)"
[ -n "$EXPECTED_SHA" ] || die "SHA256 file empty or malformed"

# 3. 拉 bundle
if [ ! -f "$BUNDLE_PATH" ]; then
	if ! download_with_fallback "$BUNDLE_NAME" "$BUNDLE_PATH"; then
		rm -f "$SHA_PATH"
		die "failed to download bundle from any mirror"
	fi
fi

# 4. 校验 SHA256
echo_log "verifying SHA256..."
ACTUAL_SHA="$(sha256sum "$BUNDLE_PATH" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
	rm -f "$BUNDLE_PATH" "$SHA_PATH"
	die "SHA256 mismatch (expected=$EXPECTED_SHA, got=$ACTUAL_SHA)"
fi
ok "SHA256 verified"

# 5. verify-only 模式直接退出
if [ "${1:-}" = "verify-only" ]; then
	echo_log "verify-only: bundle at $BUNDLE_PATH is valid"
	exit 0
fi

# 6. 解压到临时目录(不直接解压到目标,先验证结构)
EXTRACT_DIR="$DSH_STAGING/extracted"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
echo_log "extracting..."
tar -xJf "$BUNDLE_PATH" -C "$EXTRACT_DIR" || die "extract failed"

# 7. 校验 bundle 内部结构
EXPECTED_TOP="dsh-runtime-${ARCH}"
if [ ! -d "$EXTRACT_DIR/$EXPECTED_TOP" ]; then
	echo_log "bundle top dir not found (expected: $EXPECTED_TOP)"
	echo_log "actual contents:"
	ls -la "$EXTRACT_DIR" >&2
	rm -rf "$EXTRACT_DIR" "$BUNDLE_PATH" "$SHA_PATH"
	die "bundle structure invalid"
fi

# 关键文件必须存在
for f in node/bin/node dsh/package.json dsh/profile/default.json; do
	if [ ! -e "$EXTRACT_DIR/$EXPECTED_TOP/$f" ]; then
		echo_log "missing required bundle file: $f"
		rm -rf "$EXTRACT_DIR" "$BUNDLE_PATH" "$SHA_PATH"
		die "bundle incomplete"
	fi
done

ok "bundle extracted and validated"

# 8. 移到目标位置(原子操作:rename)
#    必须先停止服务,否则 in-use 文件 rename 会失败
if [ -x /etc/init.d/deepseek_harness ]; then
	/etc/init.d/deepseek_harness stop >/dev/null 2>&1 || true
fi

# 删除旧版本(若有)
rm -rf "$DSH_RUNTIME_DIR"

# 确保父目录存在
PARENT_DIR="$(dirname "$DSH_RUNTIME_DIR")"
mkdir -p "$PARENT_DIR"

# rename 到目标
mv "$EXTRACT_DIR/$EXPECTED_TOP" "$DSH_RUNTIME_DIR" \
	|| die "failed to move bundle to $DSH_RUNTIME_DIR"

# 写 marker
touch "$DSH_INSTALL_MARKER"

# 清理 staging
rm -rf "$EXTRACT_DIR"
rm -f "$BUNDLE_PATH" "$SHA_PATH"

ok "dsh runtime installed at $DSH_RUNTIME_DIR"
ok "Node.js binary: $DSH_NODE_BIN"

# 9. 验证 Node 二进制可执行
if ! "$DSH_NODE_BIN" --version >/dev/null 2>&1; then
	die "Node binary present but not executable (architecture mismatch?)"
fi
ok "Node.js $($DSH_NODE_BIN --version)"

exit 0
