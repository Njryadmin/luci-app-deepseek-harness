#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# dsh-install.sh — install / uninstall / status / logs (one-file CLI)
#
# 用法:
#   dsh-install.sh setup       # 拉 bundle + 解压 + 校验 + 写 marker
#   dsh-install.sh teardown    # 卸载 dsh runtime(保留 UCI 配置)
#   dsh-install.sh status      # 打印安装/运行状态(JSON-ish)
#   dsh-install.sh logs [N]    # tail 最近 N 行日志(默认 50)
#   dsh-install.sh purge       # 卸载 runtime + 清理 UCI(危险)
#
# 命名历史:
#   v0.2.4 之前叫 install.sh → 撞 BusyBox `install` builtin → 改名为 setup
#   v1.0.0 沿用 setup_dsh / teardown_dsh(v0.2.4 经验)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/dsh-paths.sh"

CMD="${1:-help}"

case "$CMD" in
	setup)
		echo_log "=== dsh setup ==="
		# 1. 拉 + 解压 + 校验(由 fetch-runtime 完成)
		"$SCRIPT_DIR/dsh-fetch-runtime.sh" \
			|| die "fetch-runtime failed"
		# 2. 写 UCI 配置到 dsh profile
		"$SCRIPT_DIR/dsh-apply-config.sh" \
			|| die "apply-config failed"
		# 3. 重启服务(若启用)
		if [ "$(uci -q get deepseek_harness.main.enabled 2>/dev/null || echo 0)" = "1" ]; then
			if [ -x /etc/init.d/deepseek_harness ]; then
				/etc/init.d/deepseek_harness restart || true
			fi
		fi
		ok "setup complete"
		;;

	teardown)
		echo_log "=== dsh teardown ==="
		# 先停服务
		if [ -x /etc/init.d/deepseek_harness ]; then
			/etc/init.d/deepseek_harness stop >/dev/null 2>&1 || true
		fi
		# 杀残留进程
		if [ -f "$DSH_PIDFILE" ]; then
			pid="$(cat "$DSH_PIDFILE" 2>/dev/null || true)"
			if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
				kill -TERM "$pid" 2>/dev/null || true
				sleep 1
				kill -KILL "$pid" 2>/dev/null || true
			fi
			rm -f "$DSH_PIDFILE"
		fi
		# 删 runtime(保留 UCI 配置)
		if [ -d "$DSH_RUNTIME_DIR" ]; then
			rm -rf "$DSH_RUNTIME_DIR"
			ok "removed runtime at $DSH_RUNTIME_DIR"
		else
			echo_log "runtime dir not present, skipping"
		fi
		# 清 marker
		rm -f "$DSH_INSTALL_MARKER"
		ok "teardown complete (UCI config preserved)"
		;;

	purge)
		echo_log "=== dsh purge (DANGEROUS) ==="
		echo_log "this removes runtime + UCI config + log file"
		"$0" teardown
		uci delete deepseek_harness.main >/dev/null 2>&1 || true
		uci commit deepseek_harness
		rm -f "$DSH_LOG_FILE"
		ok "purge complete"
		;;

	status)
		# 打印多行状态(Lua controller 解析)
		printf 'runtime_installed=%s\n' \
			"$([ -f "$DSH_INSTALL_MARKER" ] && echo 1 || echo 0)"
		printf 'install_path=%s\n' "$DSH_RUNTIME_DIR"
		printf 'node_present=%s\n' \
			"$([ -x "$DSH_NODE_BIN" ] && echo 1 || echo 0)"
		printf 'dsh_present=%s\n' \
			"$([ -f "$DSH_DSH_BIN" ] && echo 1 || echo 0)"
		printf 'pidfile=%s\n' "$DSH_PIDFILE"
		if [ -f "$DSH_PIDFILE" ]; then
			pid="$(cat "$DSH_PIDFILE" 2>/dev/null || echo unknown)"
			if kill -0 "$pid" 2>/dev/null; then
				printf 'running=1 pid=%s\n' "$pid"
			else
				printf 'running=0 stale_pidfile=%s\n' "$pid"
			fi
		else
			printf 'running=0\n'
		fi
		printf 'bundle_version=%s\n' "$DSH_BUNDLE_VERSION"
		printf 'arch=%s\n' "$(detect_arch)"
		printf 'libc=%s\n' "$(detect_libc)"
		if [ -x "$DSH_NODE_BIN" ]; then
			printf 'node_version=%s\n' "$("$DSH_NODE_BIN" --version 2>/dev/null || echo unknown)"
		else
			printf 'node_version=\n'
		fi
		if [ -f "$DSH_LOG_FILE" ]; then
			printf 'log_size_bytes=%s\n' \
				"$(stat -c '%s' "$DSH_LOG_FILE" 2>/dev/null || echo 0)"
		else
			printf 'log_size_bytes=0\n'
		fi
		;;

	logs)
		n="${2:-50}"
		if [ -f "$DSH_LOG_FILE" ]; then
			tail -n "$n" "$DSH_LOG_FILE"
		else
			echo "(log file not present at $DSH_LOG_FILE)"
		fi
		;;

	help|--help|-h|"")
		cat <<EOF
Usage: dsh-install.sh <command>
  setup      Install dsh runtime (download bundle + extract + verify)
  teardown   Remove dsh runtime (keep UCI config)
  purge      Teardown + remove UCI config (DANGEROUS)
  status     Print current state (parseable key=value)
  logs [N]   Show last N log lines (default 50)
EOF
		exit 1
		;;

	*)
		echo "unknown command: $CMD" >&2
		exit 2
		;;
esac
