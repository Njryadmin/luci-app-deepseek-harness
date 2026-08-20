# Architecture

## Goals

1. **One-click install** for non-technical users.
2. **Precompiled bundle** so we never invoke `npm install` on the router (which fails on musl).
3. **Recoverable failure modes** — every network/disk operation has a fallback or clear error.
4. **Boring tech** — plain POSIX shell, plain Lua, vanilla JS. No frameworks to debug.

## Component map

```
                       ┌──────────────────────────────────────┐
                       │           BROWSER (any)              │
                       └──────────────────┬───────────────────┘
                                          │ HTTP :8123
                                          │ /cgi-bin/luci/admin/services/deepseek_harness
                                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        LuCI FRAMEWORK                                │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  luasrc/controller/deepseek_harness.lua                        │ │
│  │    entry() routes → view functions + JSON API handlers        │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  luasrc/model/cbi/deepseek_harness/{basic,model}.lua           │ │
│  │    CBI form bindings → UCI                                     │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  luasrc/view/deepseek_harness/{dashboard,help}.htm             │ │
│  │    SPA dashboard + help page                                   │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                          │
                                          │ fork+exec
                                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  SHELL HELPERS (root/usr/libexec/)                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ dsh-paths.sh│  │dsh-fetch-   │  │ dsh-install │  │ dsh-wrapper │ │
│  │  (env)      │  │runtime.sh   │  │   .sh       │  │   .sh       │ │
│  │             │  │ (curl+SHA)  │  │ (setup/     │  │  (procd)    │ │
│  │             │  │             │  │ teardown/   │  │             │ │
│  │             │  │             │  │ status/logs)│  │             │ │
│  └─────────────�  └──────┬──────┘  └─────────────┘  └──────┬──────┘ │
│                          │                                 │         │
│                          ▼                                 │         │
│               ┌────────────────────┐                       │         │
│               │ GitHub Releases /  │                       │         │
│               │ npmmirror.com      │                       │         │
│               │ dsh-bundle-musl-   │                       │         │
│               │ {arch}-{ver}.tar.xz│                       │         │
│               └─────────┬──────────┘                       │         │
└─────────────────────────┼───────────────────────────────────┼─────────┘
                          │                                   │
                          ▼                                   │
               ┌──────────────────────┐                       │
               │ /opt/deepseek-harness/                       │
               │   node/   (Node.js 22.23.0 musl)             │
               │   dsh/    (@deepseek-ai/dsh 0.1.0-rc.7)      │
               │   profile/default.json                      │
               │   patches/  (pre-downloaded, optional)       │
               │   .dsh-installed (marker file)               │
               └──────────────────────┘                       │
                          ▲                                   │
                          │ exec                              │
                          │ (procd pidfile tracks)            │
                          └───────────────────────────────────┘
```

## Data flow

### Install (first time)

```
User clicks "Install / Update"
  → JS POST /api/v1/setup
    → Lua controller: os.execute("/usr/libexec/dsh-install.sh setup &")
      → dsh-install.sh setup
        1. . dsh-paths.sh (load env)
        2. dsh-fetch-runtime.sh
           - detect_arch() → x86_64
           - detect_libc()  → musl
           - compute bundle URL: github.com/.../dsh-bundle-musl-x86_64-0.1.0-rc.7.tar.xz
           - curl with fallback to npmmirror
           - sha256sum verify
           - extract to /tmp/dsh-bundle-staging/extracted/dsh-runtime-x86_64/
           - validate structure (node/, dsh/package.json, profile/default.json)
           - mv to /opt/deepseek-harness/
           - touch .dsh-installed
        3. dsh-apply-config.sh
           - read UCI
           - write profile/default.json
        4. /etc/init.d/deepseek_harness restart (if enabled=1)
      → JS polls /api/v1/status every 3s
        → shell_status() shows runtime_installed=1, running=1
```

### Runtime

```
procd → start_service() in /etc/init.d/deepseek_harness
  → write /tmp/dsh-runtime.env (API key + listen port + bundle version)
  → procd_open_instance()
    → procd_set_param command=/usr/libexec/dsh-wrapper.sh start
    → procd_set_param respawn=3600 5 5
    → procd_set_param pidfile=/var/run/dsh.pid
  → procd_close_instance()
    → fork+exec dsh-wrapper.sh start
      → . dsh-paths.sh
      → . /tmp/dsh-runtime.env (API key etc.)
      → exec $DSH_NODE_BIN dsh-cli.js web --host --port
        → Node.js 22.23.0 musl
        → dsh opens HTTP server on :8123
        → dsh starts downloading patch bundles on first request
        → logs → /var/log/dsh.log
```

### Update

```
User clicks "Install / Update" (with newer version in GitHub Releases)
  → dsh-fetch-runtime.sh redownloads + verifies
  → /etc/init.d/deepseek_harness stop (graceful)
  → rm -rf /opt/deepseek-harness
  → extract new bundle
  → touch .dsh-installed
  → /etc/init.d/deepseek_harness start
  → /etc/init.d/deepseek_harness status (verify)
```

## File responsibilities

| File | Job |
|---|---|
| `Makefile` | OpenWrt package definition |
| `root/etc/config/deepseek_harness` | Default UCI values |
| `root/etc/init.d/deepseek_harness` | procd service + extra commands (setup/status/teardown/logs) |
| `root/etc/uci-defaults/99-deepseek-harness` | First-boot setup |
| `root/usr/libexec/dsh-paths.sh` | Env vars + path constants + arch detection |
| `root/usr/libexec/dsh-fetch-runtime.sh` | Download + SHA256 verify + extract bundle |
| `root/usr/libexec/dsh-install.sh` | User-facing CLI (setup/teardown/status/logs) |
| `root/usr/libexec/dsh-apply-config.sh` | UCI → dsh profile/default.json |
| `root/usr/libexec/dsh-validate.sh` | 6-check runtime validator |
| `root/usr/libexec/dsh-wrapper.sh` | procd exec wrapper (starts dsh) |
| `root/usr/libexec/dsh-relay.sh` | Optional socat LAN relay |
| `root/usr/bin/dsh-env` | SSH-facing CLI |
| `luasrc/controller/deepseek_harness.lua` | 6 entry routes + 10 JSON API |
| `luasrc/model/cbi/deepseek_harness/basic.lua` | CBI: enable/path/port/version/arch |
| `luasrc/model/cbi/deepseek_harness/model.lua` | CBI: api_base/key/model/temperature/log |
| `luasrc/view/deepseek_harness/dashboard.htm` | SPA (6 tabs) |
| `luasrc/view/deepseek_harness/help.htm` | Help page |
| `.github/workflows/build.yml` | CI: build .ipk + GitHub Release |
| `.github/workflows/bundle.yml` | CI: build dsh runtime bundle in Alpine |
| `scripts/build_ipk.sh` | Local .ipk build |
| `scripts/verify-build.sh` | 5 static checks |
| `scripts/check_posix.py` | POSIX hard-rule checker |
| `scripts/check_lua_runtime.py` | LuCI API whitelist checker |

## Why this layout?

- **Single UCI section `main`** — no field drift between CBI forms and runtime
- **Shell helpers in `/usr/libexec/`** — standard OpenWrt location for internal binaries
- **`dsh-env` in `/usr/bin/`** — user-facing CLI, available in PATH
- **`init.d/99`** — late start so `network` is up (dsh binds a port)
- **`stop=01`** — early stop so dsh releases the port before network goes down
- **`respawn 3600 5 5`** — only restart on hard failures (5 within 1 hour), not on user stop
