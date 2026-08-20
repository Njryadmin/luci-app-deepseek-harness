# SPDX-License-Identifier: Apache-2.0
#
# LuCI app for DeepSeek Harness
# Repo: https://github.com/Njryadmin/luci-app-deepseek-harness
#
# This Makefile follows the upstream layout (10000ge10000/luci-app-openclaw)
# but is rewritten for deepseek-harness (NOT OpenClaw).
#
# Differences vs. v0.x.x:
#   - 包名改用连字符 (luci-app-deepseek-harness),符合 OpenWrt 官方包惯例
#   - 单一 UCI 段 main,合并了旧版的 main + model + meta
#   - DEPENDS 增加 python3-light (dsh 子包依赖) + xz (bundle 解压)
#   - 增加 PKG_RELEASE,便于发多版本

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for DeepSeek Harness
LUCI_PKGARCH:=all
PKG_NAME:=luci-app-deepseek-harness
PKG_VERSION:=1.0.0
PKG_RELEASE:=alpha.1

PKG_MAINTAINER:=Njryadmin <njryadmin@users.noreply.github.com>
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

# Project URLs
PKG_SOURCE_URL:=https://github.com/Njryadmin/luci-app-deepseek-harness
PKG_SOURCE_PROTO:=git
PKG_SOURCE_DATE:=2026-08-20
PKG_SOURCE_VERSION:=v$(PKG_VERSION)-$(PKG_RELEASE)
PKG_MIRROR_HASH:=skip

# Build deps (none — pure LuCI)
# Runtime deps: 详见下方的 PACKAGES +=
include $(INCLUDE_DIR)/package.mk

define Package/luci-app-deepseek-harness/config
	config PACKAGE_luci-app-deepseek-harness_ENABLE_LUAJIT
		bool "Enable LuCI LuaJIT backend (recommended)"
		depends on PACKAGE_luci-app-deepseek-harness
		default y
		help
		  Use LuaJIT for the controller layer. Provides 2-3x faster JSON
		  serialization and lower memory pressure for the dashboard.
endef

# 关键 DEPENDS:对齐 Njryadmin fork 但额外增加 dsh 实际需要
#   python3-light : dsh 大量子包 + patches 走 python 运行时
#   xz           : 解压 dsh-bundle-{arch}.tar.xz
#   coreutils-stat / -sha256sum : 校验 bundle 完整性
#   ca-bundle    : HTTPS 校验 GitHub Releases
#   luci-base, lua : LuCI runtime
define Package/luci-app-deepseek-harness
	CATEGORY:=LuCI
	SECTION:=luci
	TITLE:=$(LUCI_TITLE)
	DEPENDS:= \
		+luci-base \
		+lua \
		+curl \
		+wget \
		+ca-bundle \
		+tar \
		+xz \
		+xz-utils \
		+coreutils-stat \
		+coreutils-sha256sum \
		+coreutils-nohup \
		+python3-light \
		+!PACKAGE_luci-app-deepseek-harness_ENABLE_LUAJIT:luci \
		+PACKAGE_luci-app-deepseek-harness_ENABLE_LUAJIT:luci-lua-runtime
	EXTRA_DEPENDS:= \
		+@PACKAGE_luci-app-deepseek-harness_ENABLE_LUAJIT[?luci-lua-runtime]
	PACKAGES:=$(PKG_NAME)
endef

define Package/luci-app-deepseek-harness/description
	LuCI front-end for DeepSeek Harness (https://github.com/deepseek-ai/deepseek-harness).
	Installs a precompiled dsh runtime bundle (Node.js 22.23.0 musl +
	@deepseek-ai/dsh 0.1.0-rc.7) into /opt/deepseek-harness/ and runs it
	as a procd-managed service.

	NOT designed for OpenClaw (which has its own LuCI plugin).
	Targets iStoreOS 24.10.8 (OpenWrt 24.10.x) on x86_64 and aarch64.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-deepseek-harness/install
	# 1. LuCI Lua files
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci
	cp -r $(PKG_BUILD_DIR)/luasrc/* $(1)/usr/lib/lua/luci/
	# 2. Runtime scripts (libexec) + manual management
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/libexec/*.sh $(1)/usr/libexec/
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/* $(1)/usr/bin/
	# 3. procd init script
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/etc/init.d/* $(1)/etc/init.d/
	# 4. uci-defaults (first-boot setup)
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/etc/uci-defaults/* $(1)/etc/uci-defaults/
	# 5. Default UCI config
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/etc/config/* $(1)/etc/config/
endef

define Package/luci-app-deepseek-harness/postinst
	#!/bin/sh
	[ -n "$${IPKG_INSTROOT}" ] || {
		# Run uci-defaults once
		if [ -x /etc/uci-defaults/99-deepseek-harness ]; then
			/etc/uci-defaults/99-deepseek-harness && \
				rm -f /etc/uci-defaults/99-deepseek-harness
		fi
		# Register init script
		/etc/init.d/deepseek_harness enable >/dev/null 2>&1 || true
	}
	exit 0
endef

define Package/luci-app-deepseek-harness/prerm
	#!/bin/sh
	[ -n "$${IPKG_INSTROOT}" ] || {
		# Stop service if running (ignore errors)
		/etc/init.d/deepseek_harness stop >/dev/null 2>&1 || true
		/etc/init.d/deepseek_harness disable >/dev/null 2>&1 || true
	}
	exit 0
endef

define Package/luci-app-deepseek-harness/postrm
	#!/bin/sh
	[ -n "$${IPKG_INSTROOT}" ] || {
		# Clean UCI config only if user explicitly removed the package
		# (we leave /opt/deepseek-harness/ in place — that's user data,
		# the user might want to keep the dsh install even after removing
		# the LuCI app). Add a manual flag file if you want full purge.
		rm -f /tmp/luci-indexcache 2>/dev/null || true
	}
	exit 0
endef

$(eval $(call BuildPackage,luci-app-deepseek-harness))
