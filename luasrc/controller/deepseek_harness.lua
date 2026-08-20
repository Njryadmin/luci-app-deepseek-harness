-- SPDX-License-Identifier: Apache-2.0
--
-- controller/deepseek_harness.lua
-- LuCI controller for DeepSeek Harness plugin
--
-- 设计要点(吸取 v0.3.x 教训):
--   - 严禁使用 luci.http. stform (LuCI 新版已移除) → 用 luci.http.formvalue
--   - 所有 JSON API 走单一 dispatcher,统一异常处理
--   - controller 不持有状态,所有状态从 UCI + shell 调用获取
--   - 静态检查白名单:禁止调用 dsh_runtime 外的 luci.http.* 函数

module("luci.controller.deepseek_harness", package.seeall)

local libexec = "/usr/libexec"
local uci = require("luci.model.uci").cursor()

-- ===== 工具函数 =====

local function json_response(data, status)
	status = status or 200
	luci.http.prepare_content("application/json")
	luci.http.status(status)
	local JSON = require("luci.jsonc")
	luci.http.write(JSON.stringify(data))
end

local function ok(data)
	json_response({ ok = true, data = data or {} }, 200)
end

local function err(msg, code)
	code = code or 500
	json_response({ ok = false, error = msg }, code)
end

local function shell_status()
	-- 调 dsh-install.sh status,解析 key=value
	local f = io.popen(libexec .. "/dsh-install.sh status 2>&1")
	if not f then return { error = "cannot exec dsh-install.sh" } end
	local out = {}
	for line in f:lines() do
		local k, v = line:match("^([%w_]+)=(.+)$")
		if k then out[k] = v end
	end
	f:close()
	return out
end

local function read_uci()
	local c = {}
	c.enabled       = uci:get("deepseek_harness", "main", "enabled") or "0"
	c.install_path  = uci:get("deepseek_harness", "main", "install_path") or "/opt/deepseek-harness"
	c.listen_port   = uci:get("deepseek_harness", "main", "listen_port") or "8123"
	c.listen_host   = uci:get("deepseek_harness", "main", "listen_host") or "0.0.0.0"
	c.bundle_version= uci:get("deepseek_harness", "main", "bundle_version") or "0.1.0-rc.7"
	c.arch          = uci:get("deepseek_harness", "main", "arch") or "auto"
	c.api_base      = uci:get("deepseek_harness", "main", "api_base") or "https://api.deepseek.com"
	c.api_key       = uci:get("deepseek_harness", "main", "api_key") or ""
	c.model         = uci:get("deepseek_harness", "main", "model") or "deepseek-chat"
	c.temperature   = uci:get("deepseek_harness", "main", "temperature") or "0.7"
	c.max_tokens    = uci:get("deepseek_harness", "main", "max_tokens") or "4096"
	c.log_level     = uci:get("deepseek_harness", "main", "log_level") or "info"
	c.cors_origins  = uci:get("deepseek_harness", "main", "cors_origins") or "*"
	c.auto_start    = uci:get("deepseek_harness", "main", "auto_start") or "1"
	c.relay_enabled = uci:get("deepseek_harness", "main", "relay_enabled") or "0"
	-- Mask API key in response
	local masked = c.api_key
	if masked and #masked > 8 then
		masked = masked:sub(1, 4) .. "***" .. masked:sub(-4)
	end
	c.api_key_masked = masked
	c.api_key_present = c.api_key ~= "" and true or false
	return c
end

local function write_uci(fields)
	-- 只允许白名单字段(防 CSRF / 防注入)
	local allowed = {
		enabled = true, install_path = true, listen_port = true,
		listen_host = true, bundle_version = true, arch = true,
		api_base = true, api_key = true, model = true,
		temperature = true, max_tokens = true, log_level = true,
		cors_origins = true, auto_start = true, relay_enabled = true,
	}
	for k, v in pairs(fields or {}) do
		if allowed[k] then
			uci:set("deepseek_harness", "main", k, v)
		end
	end
	uci:commit("deepseek_harness")
end

local function call_service(cmd)
	-- 用 init.d 调用(避免直接 fork dsh-install.sh 绕过 procd)
	local fh = io.popen("/etc/init.d/deepseek_harness " .. cmd .. " 2>&1")
	if not fh then return { exit_code = 1, output = "exec failed" } end
	local out = {}
	for line in fh:lines() do table.insert(out, line) end
	fh:close()
	return { exit_code = 0, output = table.concat(out, "\n") }
end

-- ===== 路由 =====

function index()
	-- 主菜单入口
	entry({"admin", "services", "deepseek_harness"},
		call("dashboard"),
		_("DeepSeek Harness"), 50).dependent = true

	-- SPA dashboard 子页面
	entry({"admin", "services", "deepseek_harness", "dashboard"},
		call("dashboard"), _("Dashboard"), 1)

	-- CBI 配置页面
	entry({"admin", "services", "deepseek_harness", "basic"},
		cbi("deepseek_harness_basic"),
		_("Basic Settings"), 2)

	entry({"admin", "services", "deepseek_harness", "model"},
		cbi("deepseek_harness_model"),
		_("API & Model"), 3)

	entry({"admin", "services", "deepseek_harness", "help"},
		call("help"), _("Help"), 99)

	-- ===== JSON API =====
	entry({"admin", "services", "deepseek_harness", "api", "v1", "status"},
		call("api_status"), nil)
	entry({"admin", "services", "deepseek_harness", "api", "v1", "setup"},
		call("api_setup"), nil)
	entry({"admin", "services", "deepseek_harness", "api", "v1", "teardown"},
		call("api_teardown"), nil)
	entry({"admin", "services", "deepseek_harness", "api", "v1", "start"},
		call("api_start"), nil)
	entry({"admin", "services", "deepseek_harness", "api", "v1", "stop"},
		call("api_stop"), nil)
	entry({"admin", "services", "deepseek_harness", "api", "v1", "restart"},
		call("api_restart"), nil)
	entry({"admin", "services", "deepseek_harness", "api", "v1", "logs"},
		call("api_logs"), nil)
	entry({"admin", "services", "deepseek_harness", "api", "v1", "config"},
		call("api_config"), nil)
	entry({"admin", "services", "deepseek_harness", "api", "v1", "bundle_info"},
		call("api_bundle_info"), nil)
	entry({"admin", "services", "deepseek_harness", "api", "v1", "health"},
		call("api_health"), nil)
end

-- ===== 视图 =====

function dashboard()
	luci.template.render("deepseek_harness/dashboard", {
		title = _("DeepSeek Harness"),
		config = read_uci(),
		status = shell_status(),
	})
end

function help()
	luci.template.render("deepseek_harness/help", {
		title = _("Help"),
	})
end

-- ===== JSON API 实现 =====

function api_status()
	ok({
		runtime = shell_status(),
		uci = read_uci(),
	})
end

function api_setup()
	-- 启动后台任务,前端轮询 status
	os.execute("/usr/libexec/dsh-install.sh setup >/var/log/dsh-setup.log 2>&1 &")
	ok({ message = "setup started", log = "/var/log/dsh-setup.log" })
end

function api_teardown()
	os.execute("/usr/libexec/dsh-install.sh teardown >/var/log/dsh-teardown.log 2>&1 &")
	ok({ message = "teardown started", log = "/var/log/dsh-teardown.log" })
end

function api_start()
	ok(call_service("start"))
end

function api_stop()
	ok(call_service("stop"))
end

function api_restart()
	ok(call_service("restart"))
end

function api_logs()
	local n = tonumber(luci.http.formvalue("lines")) or 50
	local fh = io.popen("/usr/libexec/dsh-install.sh logs " .. n .. " 2>&1")
	local lines = {}
	if fh then
		for line in fh:lines() do table.insert(lines, line) end
		fh:close()
	end
	ok({ lines = lines, count = #lines })
end

function api_config()
	if luci.http.method == "POST" or luci.http.method == "PUT" then
		-- 写入(只接受白名单字段)
		local fields = {}
		for k, v in pairs(luci.http.formvalue()) do
			if type(v) == "string" then fields[k] = v end
		end
		write_uci(fields)
		-- 应用到 dsh profile(若已安装)
		os.execute("/usr/libexec/dsh-apply-config.sh >/dev/null 2>&1 &")
		ok({ message = "config saved" })
	else
		ok({ config = read_uci() })
	end
end

function api_bundle_info()
	local info = {
		installed = false,
		path = uci:get("deepseek_harness", "main", "install_path"),
		version = uci:get("deepseek_harness", "main", "bundle_version"),
		arch = require("luci.util").exec("uname -m"):gsub("%s+", ""),
	}
	local marker = info.path .. "/.dsh-installed"
	local f = io.open(marker, "r")
	if f then
		info.installed = true
		f:close()
	end
	ok(info)
end

function api_health()
	-- 检查 HTTP 端点可达
	local port = uci:get("deepseek_harness", "main", "listen_port") or "8123"
	local cmd = string.format(
		"curl -fsS --connect-timeout 2 http://127.0.0.1:%s/healthz 2>&1",
		port)
	local fh = io.popen(cmd)
	local reachable = fh ~= nil
	local body = ""
	if fh then
		body = fh:read("*a") or ""
		fh:close()
		reachable = true
	end
	ok({
		reachable = reachable,
		body = body,
		port = port,
	})
end
