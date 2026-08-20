#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# scripts/verify-build.sh — 5 重静态检查
#
# 检查项:
#   1. POSIX shellcheck(如果 shellcheck 可用)
#   2. Python check_posix (硬规则: set -e + exec </dev/null 等)
#   3. Python check_lua_runtime (luci.http.* API 白名单)
#   4. 文件结构完整性 (init.d / uci-defaults / config)
#   5. .ipk 可重建 (本地试构建)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 把 POSIX 路径转 Windows 路径(Git Bash + Python 跨平台兼容)
to_win() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -w "$1"
	else
		echo "$1"
	fi
}
SCRIPT_DIR_WIN="$(to_win "$SCRIPT_DIR")"

fail=0

run_check() {
	num="$1"; total="$2"; name="$3"; shift 3
	printf "[%d/%d] %s ... " "$num" "$total" "$name"
	if "$@"; then
		printf "OK\n"
	else
		printf "FAIL\n"
		fail=$((fail + 1))
	fi
}

# 1. shellcheck (optional)
if command -v shellcheck >/dev/null 2>&1; then
	run_check 1 5 "shellcheck" \
		sh -c "shellcheck --rcfile '$ROOT/.shellcheckrc' \
			'$ROOT/root/usr/libexec/'*.sh \
			'$ROOT/root/etc/init.d/'* \
			'$ROOT/root/etc/uci-defaults/'*"
else
	printf "[1/5] shellcheck ... SKIP (not installed)\n"
fi

# 2. POSIX hard rules (用相对路径,跨平台)
run_check 2 5 "POSIX hard rules" \
	sh -c "cd '$SCRIPT_DIR_WIN' && python3 check_posix.py \
		'../root/usr/libexec' \
		'../root/etc/init.d' \
		'../root/etc/uci-defaults'"

# 3. Lua runtime API whitelist
run_check 3 5 "Lua runtime API whitelist" \
	sh -c "cd '$SCRIPT_DIR_WIN' && python3 check_lua_runtime.py '../luasrc'"

# 4. File structure
run_check 4 5 "File structure" \
	sh -c "[ -f '$ROOT/Makefile' ] && \
		[ -f '$ROOT/luasrc/controller/deepseek_harness.lua' ] && \
		[ -f '$ROOT/luasrc/view/deepseek_harness/dashboard.htm' ] && \
		[ -f '$ROOT/luasrc/model/cbi/deepseek_harness/basic.lua' ] && \
		[ -f '$ROOT/luasrc/model/cbi/deepseek_harness/model.lua' ] && \
		[ -x '$ROOT/root/etc/init.d/deepseek_harness' ]"

# 5. ipk buildable
run_check 5 5 "ipk buildable" \
	sh -c "sh '$SCRIPT_DIR/build_ipk.sh' 1.0.0 alpha.1"

if [ "$fail" -gt 0 ]; then
	echo
	echo "FAILED: $fail check(s) failed"
	exit 1
fi
echo
echo "All checks passed."
