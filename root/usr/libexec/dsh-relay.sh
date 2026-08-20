#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# dsh-relay.sh — LAN 可选中继(若 dsh 默认只监听 loopback,用 socat 转发)
#
# 用法:dsh-relay.sh start|stop
#
# 默认关闭;用户可在 UCI 设 relay_enabled=1 时开启

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/dsh-paths.sh"

ACTION="${1:-start}"
RELAY_PORT="${DSH_RELAY_PORT:-${DSH_LISTEN_PORT}}"

case "$ACTION" in
	start)
		# 检查 socat 是否可用
		command -v socat >/dev/null 2>&1 || {
			log "socat not installed (opkg install socat)"
			exit 1
		}
		# 转发 LAN :RELAY_PORT -> 127.0.0.1:DSH_LISTEN_PORT
		exec socat TCP-LISTEN:"$RELAY_PORT",fork,reuseaddr \
			TCP:127.0.0.1:"$DSH_LISTEN_PORT"
		;;
	stop)
		log "relay stop (no-op; procd handles)"
		;;
	*)
		echo "usage: $0 start|stop" >&2
		exit 2
		;;
esac
