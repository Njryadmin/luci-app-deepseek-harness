#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# dsh-validate.sh — 校验 dsh runtime 完整性
#
# 检查项:
#   1. install marker 存在
#   2. node 二进制可执行
#   3. dsh package.json 存在
#   4. dsh 主入口存在
#   5. profile/default.json 可读

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/dsh-paths.sh"

fail=0
check() {
	if eval "$2"; then
		printf "  [OK]   %s\n" "$1"
	else
		printf "  [FAIL] %s\n" "$1"
		fail=$((fail + 1))
	fi
}

echo_log "validating dsh runtime at $DSH_RUNTIME_DIR"

check "install marker present" "[ -f '$DSH_INSTALL_MARKER' ]"
check "node binary executable" "[ -x '$DSH_NODE_BIN' ]"
check "dsh package.json present" "[ -f '$DSH_DSH_DIR/package.json' ]"
check "dsh cli entry present" "[ -f '$DSH_DSH_DIR/node_modules/@deepseek-ai/dsh/dist/cli.js' ]"
check "profile/default.json present" "[ -f '$DSH_PROFILE_DIR/default.json' ]"
check "patch dir present" "[ -d '$DSH_PATCH_DIR' ]"

if [ "$fail" -gt 0 ]; then
	echo_log "validation FAILED: $fail check(s) failed"
	exit 1
fi

# 实际跑一下 node --version
ver="$("$DSH_NODE_BIN" --version 2>&1 || echo failed)"
echo_log "Node.js version: $ver"

ok "validation passed"
