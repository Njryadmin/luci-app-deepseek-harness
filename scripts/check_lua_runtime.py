#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
check_lua_runtime.py — LuCI Lua runtime API 白名单检查

吸取 v0.3.1 教训: `luci.http.stform` 不存在,导致 runtime error。

策略:
  - 白名单所有合法 luci.http.* 方法
  - 黑名单已知的 luci.http.stform (LuCI 新版已移除)
  - 检查 controller / model 是否引用合法 API

用法:
  python3 check_lua_runtime.py <dir>
"""

import re
import sys
from pathlib import Path

# 合法 luci.http.* 方法白名单(基于 OpenWrt 24.10 LuCI)
LUCI_HTTP_ALLOWED = {
	"prepare_content", "status", "write", "writeln",
	"header", "redirect", "get_method", "method", "formvalue",
	"formvaluetable", "content", "contentlen",
	"args", "getenv", "setenv", "query", "urldecode",
	"urlencode", "json_encode", "json", "source",
}

# 已知不存在的 luci.http.* 方法(黑名单)
LUCI_HTTP_FORBIDDEN = {
	"stform",         # v0.3.1 踩坑: LuCI 新版已移除
	"formvalue_array",  # 未公开 API
	"formvaluemap",     # 未公开 API
}

LUCI_DH_ALLOWED = {
	"section", "named", "typed", "uci", "cursor", "set",
	"get", "commit", "foreach", "delete",
}

PATTERN_LUCI_HTTP = re.compile(r"luci\.http\.(\w+)")
PATTERN_LUCI_DH = re.compile(r"luci\.model\.uci\.(\w+)")

def check_file(path: Path) -> list:
	"""Return list of (line_no, api, reason) for violations."""
	violations = []
	try:
		text = path.read_text(encoding="utf-8", errors="replace")
	except Exception:
		return violations

	for m in PATTERN_LUCI_HTTP.finditer(text):
		api = m.group(1)
		line_no = text.count("\n", 0, m.start()) + 1
		if api in LUCI_HTTP_FORBIDDEN:
			violations.append((
				line_no, f"luci.http.{api}",
				"this API was removed in LuCI 23.05+ — use luci.http.formvalue instead",
			))
		elif api not in LUCI_HTTP_ALLOWED:
			violations.append((
				line_no, f"luci.http.{api}",
				"not in whitelist (OpenWrt 24.10 LuCI)",
			))

	for m in PATTERN_LUCI_DH.finditer(text):
		api = m.group(1)
		line_no = text.count("\n", 0, m.start()) + 1
		if api not in LUCI_DH_ALLOWED:
			violations.append((
				line_no, f"luci.model.uci.{api}",
				"not in whitelist",
			))

	return violations

def main() -> int:
	if len(sys.argv) < 2:
		print("usage: check_lua_runtime.py <dir>", file=sys.stderr)
		return 2

	p = Path(sys.argv[1])
	if not p.exists():
		print(f"FAIL: {p} does not exist", file=sys.stderr)
		return 1

	files = list(p.rglob("*.lua"))
	total_fail = 0
	for f in files:
		violations = check_file(f)
		for line_no, api, reason in violations:
			print(f"FAIL: {f}:{line_no}: {api}")
			print(f"      {reason}")
			total_fail += 1

	if total_fail > 0:
		print(f"\n{total_fail} violation(s) found")
		return 1
	print(f"OK: {len(files)} lua file(s) checked, no violations")
	return 0

if __name__ == "__main__":
	sys.exit(main())
