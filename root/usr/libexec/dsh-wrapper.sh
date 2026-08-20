#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# dsh-wrapper.sh — 启动 / 停止 dsh runtime (被 procd 调用)
#
# 设计要点:
#   - 不 set -e(避免 silent exit,v0.2.2 教训)
#   - 用 exec 替换进程,让 procd 能通过 pidfile 跟踪
#   - 把 stdout/stderr 重定向到日志文件 + logd
#   - 调用方(procd)负责 stdin 隔离;这里不要再 exec </dev/null

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/dsh-paths.sh"

ACTION="${1:-start}"

ensure_log_dir() {
	[ -d "$DSH_LOG_DIR" ] || mkdir -p "$DSH_LOG_DIR"
	touch "$DSH_LOG_FILE" 2>/dev/null || true
}

start() {
	ensure_log_dir

	# 必备检查
	[ -x "$DSH_NODE_BIN" ] || {
		log "node binary missing at $DSH_NODE_BIN — run setup first"
		exit 1
	}
	[ -f "$DSH_DSH_BIN" ] || {
		log "dsh binary missing at $DSH_DSH_BIN — bundle corrupted"
		exit 1
	}

	# 写 PID(在 exec 之前)
	# procd 用 pidfile 跟踪;但 dsh 是 node 子进程,我们跟踪的是 node 主进程
	echo $$ > "$DSH_PIDFILE"

	log "starting dsh (pid=$$) on $DSH_LISTEN_HOST:$DSH_LISTEN_PORT"

	# 加载环境(由 init.d 写入 /tmp/dsh-runtime.env)
	if [ -f /tmp/dsh-runtime.env ]; then
		set -a
		. /tmp/dsh-runtime.env
		set +a
	fi

	# exec 替换进程,让 procd 拿到正确的 pid
	# 这里故意不 exec </dev/null(procd 进程树内会触发 silent exit)
	exec "$DSH_NODE_BIN" \
		"$DSH_DSH_DIR/node_modules/@deepseek-ai/dsh/dist/cli.js" \
		web \
		--host "$DSH_LISTEN_HOST" \
		--port "$DSH_LISTEN_PORT" \
		>> "$DSH_LOG_FILE" 2>&1
}

stop() {
	# 由 init.d 的 stop_service 通过 pidfile 发 SIGTERM
	# wrapper 不在这里做 stop 逻辑(避免和 procd 重叠)
	log "wrapper received stop signal"
	exit 0
}

case "$ACTION" in
	start) start ;;
	stop)  stop ;;
	*) log "unknown action: $ACTION"; exit 2 ;;
esac
