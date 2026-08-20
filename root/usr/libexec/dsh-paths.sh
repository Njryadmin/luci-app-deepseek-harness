#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# dsh-paths.sh — 路径与环境变量(供其他 dsh-*.sh source 使用)
#
# 设计原则:
#   - 所有路径走 UCI(单一来源),不允许硬编码安装路径
#   - 所有常量都大写导出,避免子进程拿不到

DSH_LIBEXEC_DIR="${DSH_LIBEXEC_DIR:-/usr/libexec}"
DSH_BIN_DIR="${DSH_BIN_DIR:-/usr/bin}"

# UCI 读取(若 UCI 不可用则用默认)
if command -v uci >/dev/null 2>&1; then
	: "${DSH_INSTALL_PATH:="$(uci -q get deepseek_harness.main.install_path 2>/dev/null || echo /opt/deepseek-harness)"}"
	: "${DSH_BUNDLE_VERSION:="$(uci -q get deepseek_harness.main.bundle_version 2>/dev/null || echo 0.1.0-rc.7)"}"
	: "${DSH_LISTEN_PORT:="$(uci -q get deepseek_harness.main.listen_port 2>/dev/null || echo 8123)"}"
	: "${DSH_LISTEN_HOST:="$(uci -q get deepseek_harness.main.listen_host 2>/dev/null || echo 0.0.0.0)"}"
	: "${DSH_ARCH:="$(uci -q get deepseek_harness.main.arch 2>/dev/null || echo auto)"}"
else
	: "${DSH_INSTALL_PATH:=/opt/deepseek-harness}"
	: "${DSH_BUNDLE_VERSION:=0.1.0-rc.7}"
	: "${DSH_LISTEN_PORT:=8123}"
	: "${DSH_LISTEN_HOST:=0.0.0.0}"
	: "${DSH_ARCH:=auto}"
fi

# Bundle 来源(预编译产物在 GitHub Releases)
DSH_BUNDLE_BASE="${DSH_BUNDLE_BASE:-https://github.com/Njryadmin/luci-app-deepseek-harness/releases/download}"
DSH_BUNDLE_PREFIX="${DSH_BUNDLE_PREFIX:-dsh-bundle}"

# 路径常量
DSH_RUNTIME_DIR="$DSH_INSTALL_PATH"
DSH_NODE_DIR="$DSH_RUNTIME_DIR/node"
DSH_NODE_BIN="$DSH_NODE_DIR/bin/node"
DSH_DSH_DIR="$DSH_RUNTIME_DIR/dsh"
DSH_DSH_BIN="$DSH_DSH_DIR/node_modules/.bin/dsh"
DSH_PROFILE_DIR="$DSH_RUNTIME_DIR/profile"
DSH_PATCH_DIR="$DSH_RUNTIME_DIR/patches"
DSH_LOG_DIR="${DSH_LOG_DIR:-/var/log}"
DSH_LOG_FILE="${DSH_LOG_FILE:-$DSH_LOG_DIR/dsh.log}"
DSH_PIDFILE="${DSH_PIDFILE:-/var/run/dsh.pid}"
DSH_INSTALL_MARKER="$DSH_RUNTIME_DIR/.dsh-installed"

# 内部临时目录(解压用)
DSH_STAGING="${DSH_STAGING:-/tmp/dsh-bundle-staging}"

# 架构检测(支持 x86_64, aarch64)
detect_arch() {
	if [ "$DSH_ARCH" != "auto" ]; then
		echo "$DSH_ARCH"
		return 0
	fi
	case "$(uname -m)" in
		x86_64|amd64) echo "x86_64" ;;
		aarch64|arm64) echo "aarch64" ;;
		*) echo "unsupported:$(uname -m)" >&2; return 1 ;;
	esac
}

# libc 检测(我们只支持 musl,iStoreOS 默认)
detect_libc() {
	if ldd --version 2>&1 | grep -qi musl; then
		echo "musl"
	elif ldd --version 2>&1 | grep -qi glibc; then
		echo "glibc"
	else
		echo "unknown"
	fi
}

# 工具函数
log() { logger -t dsh "$@"; }
echo_log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { echo_log "ERROR: $*" >&2; exit 1; }
ok() { echo_log "OK: $*"; }

# 导出给调用方
export DSH_INSTALL_PATH DSH_BUNDLE_VERSION DSH_BUNDLE_BASE DSH_BUNDLE_PREFIX
export DSH_RUNTIME_DIR DSH_NODE_DIR DSH_NODE_BIN DSH_DSH_DIR DSH_DSH_BIN
export DSH_PROFILE_DIR DSH_PATCH_DIR DSH_LOG_DIR DSH_LOG_FILE DSH_PIDFILE
export DSH_INSTALL_MARKER DSH_STAGING
export DSH_LISTEN_PORT DSH_LISTEN_HOST DSH_ARCH
