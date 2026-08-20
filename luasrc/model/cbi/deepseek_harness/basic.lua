-- SPDX-License-Identifier: Apache-2.0
-- CBI: basic settings (install path / port / enabled)

local m, s, o

m = Map("deepseek_harness", translate("DeepSeek Harness — Basic Settings"),
	translate("Configure install location, port, and enable/disable the service."))

m:section(SimpleSection).template = "deepseek_harness/header"

s = m:section(NamedSection, "main", "deepseek_harness")

o = s:option(Flag, "enabled", translate("Enable service"))
	o.default = "0"
	o.rmempty = false
	o.description = translate("When disabled, the dsh runtime is not started on boot or via /init.d.")

o = s:option(Value, "install_path", translate("Install path"))
	o.default = "/opt/deepseek-harness"
	o.rmempty = false
	o.description = translate("Where the precompiled dsh runtime bundle will be extracted.")
	o:depends("enabled", "1")

o = s:option(Value, "listen_host", translate("Listen host"))
	o.default = "0.0.0.0"
	o:value("0.0.0.0", translate("All interfaces"))
	o:value("127.0.0.1", translate("Loopback only (use relay for LAN)"))
	o:depends("enabled", "1")

o = s:option(Value, "listen_port", translate("Listen port"))
	o.default = "8123"
	o.datatype = "port"
	o:depends("enabled", "1")

o = s:option(Value, "bundle_version", translate("Bundle version"))
	o.default = "0.1.0-rc.7"
	o.readonly = true
	o.description = translate("Pinned deepseek-harness npm version. Update via GitHub Releases.")

o = s:option(ListValue, "arch", translate("Architecture"))
	o.default = "auto"
	o:value("auto", translate("Auto-detect"))
	o:value("x86_64", translate("x86_64"))
	o:value("aarch64", translate("aarch64"))

o = s:option(Flag, "auto_start", translate("Start on boot"))
	o.default = "1"

o = s:option(Flag, "relay_enabled", translate("Enable LAN relay (socat)"))
	o.default = "0"
	o.description = translate("If dsh only binds to loopback, socat will forward LAN traffic.")

return m
