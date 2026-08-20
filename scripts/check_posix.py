#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
check_posix.py — POSIX shell 硬规则检查

检查项(吸取 v0.2.x 教训):
  1. 严禁 `set -e` + `exec </dev/null` 在同一脚本块内(silent exit)
  2. 严禁命令名 install/uninstall (BusyBox builtin 冲突)
  3. 严禁在 procd service 进程内 `set -e`(DEBUG 模式下 silent exit)
  4. 严禁 function 名与 BusyBox builtin 同名
  5. 严禁 `local foo=$(cmd)`,要用 `local foo; foo=$(cmd)`

用法:
  python3 check_posix.py <dir1> [dir2] ...
"""

import os
import re
import sys
from pathlib import Path

# 不允许的 BusyBox builtin 函数名
BUILTIN_BLACKLIST = {
	"install", "uninstall", "mount", "umount", "reboot",
	"poweroff", "halt", "ifconfig", "route", "init",
}

# 不允许的 POSIX 反模式
PATTERNS = [
	{
		"name": "set -e + exec </dev/null",
		"regex": re.compile(
			r"set\s+-[a-z]*e.*\n.*exec\s+<\s*/dev/null|"
			r"exec\s+<\s*/dev/null.*\n.*set\s+-[a-z]*e",
			re.MULTILINE,
		),
		"reason": "在 procd 进程树内会触发 silent exit",
	},
	{
		"name": "function name collides with BusyBox builtin",
		"regex": re.compile(
			r"^\s*(?:function\s+)?(" + "|".join(BUILTIN_BLACKLIST) + r")\s*\(\)",
			re.MULTILINE,
		),
		"reason": "会与 BusyBox builtin 冲突,调用会被 builtin 抢走",
	},
	{
		"name": "local var=$(cmd) anti-pattern",
		"regex": re.compile(r"^\s*local\s+\w+\s*=\s*\$\(", re.MULTILINE),
		"reason": "应改为两行: local var; var=$(cmd) (避免子进程失败时 var 保持旧值)",
	},
	{
		"name": "set -e in /etc/init.d/ script",
		"regex": re.compile(r"^\s*set\s+-[a-z]*e", re.MULTILINE),
		"reason": "procd DEBUG 模式下 set -e 会导致 silent exit",
		"path_filter": "init.d",
	},
]

def check_file(path: Path) -> list:
	"""Return list of (line_no, rule_name, reason) for violations."""
	violations = []
	try:
		text = path.read_text(encoding="utf-8", errors="replace")
	except Exception:
		return violations

	is_initd = "init.d" in str(path)

	for pat in PATTERNS:
		if pat.get("path_filter") == "init.d" and not is_initd:
			continue
		if pat.get("path_filter") != "init.d" and is_initd:
			# skip non-initd-specific rules for initd (but init.d-specific still applies)
			pass
		for m in pat["regex"].finditer(text):
			line_no = text.count("\n", 0, m.start()) + 1
			violations.append((line_no, pat["name"], pat["reason"]))
	return violations

def main() -> int:
	if len(sys.argv) < 2:
		print("usage: check_posix.py <dir>...", file=sys.stderr)
		return 2

	total_fail = 0
	for arg in sys.argv[1:]:
		p = Path(arg)
		if not p.exists():
			print(f"FAIL: {p} does not exist", file=sys.stderr)
			total_fail += 1
			continue
		if p.is_file():
			files = [p]
		else:
			files = list(p.rglob("*.sh")) + list(p.rglob("99-*"))
		for f in files:
			violations = check_file(f)
			for line_no, rule, reason in violations:
				print(f"FAIL: {f}:{line_no}: {rule}")
				print(f"      {reason}")
				total_fail += 1

	if total_fail > 0:
		print(f"\n{total_fail} violation(s) found")
		return 1
	print("OK: no POSIX violations")
	return 0

if __name__ == "__main__":
	sys.exit(main())
