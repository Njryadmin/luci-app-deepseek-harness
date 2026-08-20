-- SPDX-License-Identifier: Apache-2.0
-- CBI: API & model settings

local m, s, o

m = Map("deepseek_harness", translate("DeepSeek Harness — API & Model"),
	translate("Configure the DeepSeek API key and model parameters."))

m:section(SimpleSection).template = "deepseek_harness/header"

s = m:section(NamedSection, "main", "deepseek_harness")

o = s:option(Value, "api_base", translate("API base URL"))
	o.default = "https://api.deepseek.com"
	o.description = translate("DeepSeek API endpoint. Default: https://api.deepseek.com")

o = s:option(Value, "api_key", translate("API key"))
	o.default = ""
	o.password = true
	o.description = translate("Your DeepSeek API key. Stored in /etc/config/deepseek_harness with chmod 0600.")

o = s:option(Value, "model", translate("Model"))
	o.default = "deepseek-chat"
	o:value("deepseek-chat", translate("deepseek-chat (general)"))
	o:value("deepseek-coder", translate("deepseek-coder (legacy)"))
	o:value("deepseek-reasoner", translate("deepseek-reasoner (R1)"))

o = s:option(Value, "temperature", translate("Temperature"))
	o.default = "0.7"
	o.datatype = "range(0,2)"
	o.description = translate("Sampling temperature 0.0–2.0. Default 0.7.")

o = s:option(Value, "max_tokens", translate("Max tokens"))
	o.default = "4096"
	o.datatype = "range(64,32768)"
	o.description = translate("Maximum tokens per response.")

o = s:option(ListValue, "log_level", translate("Log level"))
	o.default = "info"
	o:value("debug")
	o:value("info")
	o:value("warn")
	o:value("error")

o = s:option(Value, "cors_origins", translate("CORS origins"))
	o.default = "*"
	o.description = translate("Comma-separated origins, or '*' for any. Production: use specific domain.")

return m
