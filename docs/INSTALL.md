# Installation Guide

## 1. Prerequisites

### Hardware

| | Minimum | Recommended |
|---|---|---|
| Architecture | x86_64 or aarch64 | x86_64 |
| RAM | 1 GB | 2 GB |
| Disk | 500 MB free in `/opt` | 1 GB |

### Software

- **iStoreOS 24.10.8** or any OpenWrt 24.10.x with `procd` and `LuCI`
- `curl` (for bundle download)
- `xz-utils` (for `.tar.xz` extraction)
- `python3-light` (pulled as dependency automatically)

## 2. Install the .ipk

### Option A: LuCI web UI

1. Download `luci-app-deepseek-harness_1.0.0-alpha.1_all.ipk` from
   [Releases](https://github.com/Njryadmin/luci-app-deepseek-harness/releases/tag/v1.0.0-alpha.1).
2. **System → Software → Upload package** → select `.ipk` → **Install**.
3. Wait for installation (deps: `python3-light`, `xz`, `curl`, `tar`, etc.).
4. After install, the menu appears at **Services → DeepSeek Harness**.

### Option B: SSH

```sh
cd /tmp
wget https://github.com/Njryadmin/luci-app-deepseek-harness/releases/download/v1.0.0-alpha.1/luci-app-deepseek-harness_1.0.0-alpha.1_all.ipk
opkg install luci-app-deepseek-harness_1.0.0-alpha.1_all.ipk
```

## 3. Install the dsh runtime bundle

This step downloads ~200 MB of precompiled dsh + Node.js from GitHub Releases
into `/opt/deepseek-harness/`. Takes 2-5 minutes depending on network.

### Option A: LuCI UI

1. **Services → DeepSeek Harness → Install** tab
2. Click **Install / Update**
3. Wait for the log to show "setup complete"

### Option B: SSH

```sh
dsh-env setup
```

## 4. Configure

### Set your API key

```sh
uci set deepseek_harness.main.api_key='sk-...'
uci commit deepseek_harness
dsh-env reload     # or: /etc/init.d/deepseek_harness restart
```

Or use the **Config** tab in LuCI.

### Enable autostart

```sh
dsh-env enable
```

The default UCI config has `enabled=1` and `auto_start=1`, so this is usually already done.

## 5. Start

```sh
dsh-env start
```

Or via LuCI **Status** tab → **Start**.

## 6. Verify

```sh
dsh-env status
```

Expected output:

```
runtime_installed=1
install_path=/opt/deepseek-harness
node_present=1
dsh_present=1
pidfile=/var/run/dsh.pid
running=1 pid=12345
bundle_version=0.1.0-rc.7
arch=x86_64
libc=musl
node_version=v22.23.0
log_size_bytes=1234
```

Open in browser:

```
http://<router-ip>:8123
```

(If `listen_host=127.0.0.1`, use `http://127.0.0.1:8123` from router SSH, or enable `relay_enabled=1`.)

## 7. Update

When a new version is released:

```sh
dsh-env setup     # redownloads the bundle
dsh-env restart   # picks up new binary
```

Or via LuCI: **Install** tab → **Install / Update**.
