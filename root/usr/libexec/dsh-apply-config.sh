#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# dsh-apply-config.sh — 把 UCI 配置写入 dsh 的 profile.json
#
# 设计:
#   - 读取 UCI → 写到 $DSH_PROFILE_DIR/default.json(dsh 期望的格式)
#   - 幂等,可重复执行
#   - 不重启服务(由 setup_dsh 决定是否 restart)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/dsh-paths.sh"

# 必备检查
[ -d "$DSH_RUNTIME_DIR" ] || {
	echo_log "runtime not installed at $DSH_RUNTIME_DIR"
	exit 1
}

mkdir -p "$DSH_PROFILE_DIR"

# 从 UCI 读(默认兜底)
enabled="$(uci -q get deepseek_harness.main.enabled || echo 0)"
api_base="$(uci -q get deepseek_harness.main.api_base || echo https://api.deepseek.com)"
api_key="$(uci -q get deepseek_harness.main.api_key || echo '')"
model="$(uci -q get deepseek_harness.main.model || echo deepseek-chat)"
temperature="$(uci -q get deepseek_harness.main.temperature || echo 0.7)"
max_tokens="$(uci -q get deepseek_harness.main.max_tokens || echo 4096)"
log_level="$(uci -q get deepseek_harness.main.log_level || echo info)"
cors_origins="$(uci -q get deepseek_harness.main.cors_origins || echo '*')"

# 写 dsh 期望的 JSON 结构(用 here-doc 避免引号转义)
cat > "$DSH_PROFILE_DIR/default.json" <<EOF
{
  "version": 1,
  "provider": {
    "name": "deepseek",
    "apiBase": "${api_base}",
    "apiKey": "${api_key}",
    "model": "${model}",
    "temperature": ${temperature},
    "maxTokens": ${max_tokens}
  },
  "server": {
    "host": "${DSH_LISTEN_HOST}",
    "port": ${DSH_LISTEN_PORT},
    "corsOrigins": "${cors_origins}"
  },
  "logging": {
    "level": "${log_level}",
    "file": "${DSH_LOG_FILE}"
  },
  "router": {
    "enabled": $([ "$enabled" = "1" ] && echo true || echo false)
  }
}
EOF

chmod 0600 "$DSH_PROFILE_DIR/default.json"
ok "applied UCI to $DSH_PROFILE_DIR/default.json"
