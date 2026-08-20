# luci-app-deepseek-harness

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Target](https://img.shields.io/badge/target-iStoreOS%2024.10.8-blue)](https://github.com/istoreos/istoreos)
[![Arch](https://img.shields.io/badge/arch-x86__64%20%2F%20aarch64-lightgrey)]()
[![Version](https://img.shields.io/badge/version-1.0.0--alpha.1-orange)]()

LuCI front-end for [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness),
an AI agent framework by DeepSeek. Designed for **iStoreOS 24.10.8** (OpenWrt 24.10.x).

> **This is NOT a plugin for OpenClaw.** It is purpose-built for deepseek-harness.
> If you want OpenClaw, see [`10000ge10000/luci-app-openclaw`](https://github.com/10000ge10000/luci-app-openclaw).

---

## What this does

Downloads a precompiled **dsh runtime bundle** from GitHub Releases and runs it as a
procd-managed HTTP service on your router. The bundle contains:

- A self-contained **Node.js 22.23.0 musl** binary
- `@deepseek-ai/dsh@0.1.0-rc.7` (DeepSeek's AI agent framework)
- Default profile + initial patch bundles

The LuCI dashboard provides 6 tabs:

| Tab | Purpose |
|---|---|
| **Status** | Runtime state, process info, listen address, log size |
| **Install** | One-click install / update / validate |
| **Config** | Edit UCI config (path, port, API key, model) |
| **API** | JSON API endpoints + health check |
| **Logs** | Tail `/var/log/dsh.log` |
| **About** | Version + links |

A CLI mirror is available via `dsh-env`:

```sh
dsh-env setup      # install/update bundle
dsh-env status     # show state
dsh-env logs       # tail logs
dsh-env config     # print UCI config
```

---

## Requirements

| | Minimum | Recommended |
|---|---|---|
| iStoreOS / OpenWrt | 24.10.x (iStoreOS 24.10.8 verified) | latest |
| Architecture | x86_64 or aarch64 | x86_64 |
| libc | musl | musl |
| RAM | 1 GB | 2 GB |
| Disk | 500 MB free in `/opt` | 1 GB |
| `python3-light` | required | required |

---

## Installation

### Via LuCI web UI

1. Download the latest `.ipk` from [Releases](https://github.com/Njryadmin/luci-app-deepseek-harness/releases).
2. LuCI → **System → Software → Upload package** → select the `.ipk` → **Install**.
3. Wait for the install to complete (it pulls `python3-light`, `xz`, `curl`, etc. as deps).
4. Navigate to **Services → DeepSeek Harness**.
5. **Install** tab → **Install / Update** → wait ~2-5 minutes for bundle download.

### Via SSH

```sh
cd /tmp
wget https://github.com/Njryadmin/luci-app-deepseek-harness/releases/download/v1.0.0-alpha.1/luci-app-deepseek-harness_1.0.0-alpha.1_all.ipk
opkg install luci-app-deepseek-harness_1.0.0-alpha.1_all.ipk
dsh-env setup
/etc/init.d/deepseek_harness enable
/etc/init.d/deepseek_harness start
```

---

## Architecture

See [docs/ARCH.md](docs/ARCH.md) for the full architecture overview.

High-level:

```
┌──────────────┐    JSON API     ┌─────────────────┐
│ LuCI SPA UI  │ ───────────────►│ LuCI controller │
└──────────────┘                 └────────┬────────�
                                            │ fork+exec
                                            ▼
                                 ┌────────────────────┐
                                 │ /usr/libexec/      │
                                 │ dsh-install.sh     │
                                 └────────┬───────────┘
                                          │ curl/wget
                                          ▼
                            ┌─────────────────────────┐
                            │ GitHub Releases         │
                            │ dsh-bundle-musl-*.tar.xz│
                            └────────┬────────────────┘
                                     │ extract
                                     ▼
                       ┌──────────────────────────┐
                       │ /opt/deepseek-harness/    │
                       │   node/  (Node.js musl)  │
                       │   dsh/   (@deepseek-ai)  │
                       │   profile/default.json   │
                       └──────────────────────────┘
                                     ▲
                                     │ procd
                                 ┌───┴──────────┐
                                 │ dsh-wrapper  │
                                 │   exec node  │
                                 └──────────────┘
```

---

## Why "precompiled bundle" instead of `npm install`?

The naive approach (download Node.js, `npm install @deepseek-ai/dsh`, run it) breaks on
musl routers because:

1. dsh is a **monorepo** with 60+ sub-packages, many requiring native compilation
2. **landlock** and **node-pty** bindings fail to compile on Alpine/musl
3. dsh launches a daemon that **re-downloads patch bundles** from GitHub after first run
4. Total install time on a router is **30+ minutes** with no resume support

By precompiling the entire runtime in an Alpine container (CI), we ship a single
`tar.xz` that the router just **extracts and runs**. Install time drops to ~2 minutes
and the failure modes are limited to network/cert/SHA256 — all recoverable.

---

## Compatibility

| Component | Pinned version |
|---|---|
| OpenWrt / iStoreOS | 24.10.x |
| Node.js (in bundle) | 22.23.0 musl |
| @deepseek-ai/dsh | 0.1.0-rc.7 |
| Python | 3.x (light) |
| BusBox | 1.36.1+ |

---

## Development

```sh
# Static checks
./scripts/verify-build.sh

# Local .ipk build
./scripts/build_ipk.sh 1.0.0 alpha.1

# Build dsh runtime bundle (in Alpine container)
# See .github/workflows/bundle.yml
```

---

## License

Apache-2.0. See [LICENSE](LICENSE).

---

## Links

- [deepseek-harness (upstream)](https://github.com/deepseek-ai/deepseek-harness)
- [@deepseek-ai/dsh (npm)](https://www.npmjs.com/package/@deepseek-ai/dsh)
- [iStoreOS](https://github.com/istoreos/istoreos)
- [OpenWrt](https://openwrt.org/)
- [luci-app-openclaw (layout inspiration, different project)](https://github.com/10000ge10000/luci-app-openclaw)
