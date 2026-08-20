# Changelog

All notable changes to **luci-app-deepseek-harness** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0-alpha.1] — 2026-08-20

### 🚨 Major: rewrite from scratch

The previous project `luci-app-deepseek_harness` (v0.1.0–v0.3.3) has been archived
to `archive-v0.3.3-final`. This is a complete rewrite addressing fundamental
architectural mistakes:

| Before (v0.3.3) | After (v1.0.0-alpha) |
|---|---|
| Live `npm install @deepseek-ai/dsh` (fails on musl) | Precompiled `dsh-bundle-musl-{arch}.tar.xz` |
| UCI fields split across `main` / `model` / `meta` (drifted) | Single `main` section |
| npm registry + GitHub Releases fallback (unstable) | GitHub Releases primary + npmmirror mirror |
| `install` command name (BusyBox builtin collision) | `setup_dsh` / `teardown_dsh` (v0.2.4 fix preserved) |
| `set -e` + `exec </dev/null` (silent exit in procd) | `set -e` only in non-procd scripts |
| `luci.http.stform` (removed in LuCI 23.05+) | `luci.http.formvalue` + whitelist check |
| UI styles bleed from LuCI globals | `.dsh-*` scoped + `all: revert` reset |
| `python3-light` not in DEPENDS | `python3-light` required |

### Added

- `dsh-fetch-runtime.sh`: multi-mirror fallback + SHA256 verify
- `dsh-install.sh setup|teardown|status|logs|purge`: unified CLI
- `dsh-apply-config.sh`: UCI → dsh `profile/default.json`
- `dsh-validate.sh`: 6-check runtime integrity validator
- `dsh-wrapper.sh`: procd-compatible exec wrapper
- `dsh-env` CLI: `setup|status|logs|config|shell|start|stop|restart`
- JSON API: `/api/v1/{status,setup,teardown,start,stop,restart,logs,config,bundle_info,health}`
- 6-tab SPA dashboard (Status/Install/Config/API/Logs/About)
- Dark mode via `prefers-color-scheme`
- GitHub Actions: `build.yml` (ipk) + `bundle.yml` (dsh runtime)
- `scripts/check_posix.py`: POSIX hard-rule checker
- `scripts/check_lua_runtime.py`: LuCI API whitelist checker
- `scripts/verify-build.sh`: 5-check pre-release gate

### Changed

- Package name: `luci-app-deepseek_harness` → `luci-app-deepseek-harness` (hyphen)
- Single `main` UCI section with 15 fields (was: 3 sections, 25 fields)
- `set -e` only in `dsh-fetch-runtime.sh` (not in procd-managed scripts)
- Procd `respawn 3600 5 5` (threshold=1h, retries=5, delay=5s)
- PID file at `/var/run/dsh.pid` (was: scattered)

### Fixed (from v0.x.x lessons)

- SIGTTIN hang when invoked from SSH (v0.2.1) → `setsid + </dev/null` in caller, not in wrapper
- `set -e` + `exec </dev/null` silent exit (v0.2.2) → strict separation
- `_dsh_fix_opt` return 1 + set -e (v0.2.3) → `_dsh_fix_opt || true`
- BusyBox `install` builtin collision (v0.2.4) → `setup_dsh` naming preserved
- `luci.http.stform` runtime error (v0.3.1) → whitelist + static check
- LuCI global CSS bleeding into UI (v0.3.3) → `all: revert` + `box-sizing` reset

### Removed

- `main` + `model` + `meta` UCI sections (consolidated into `main`)
- 13 obsolete shell scripts (`fetch-node`, `node-musl-builder`, `apply-config`, etc.)
- Old SPA `dashboard` + `settings` + `about` views (replaced by single SPA)
- `dist/build_run.sh` (replaced by GitHub Releases workflow)
- `compat-matrix.md` (consolidated into README)

### Notes

- The previous `luci-app-deepseek_harness` repository stays online at
  `archive-v0.3.3-final` tag. Issues should be filed here on the new repo.
- `bundle.yml` is opt-in via `workflow_dispatch` until we verify the dsh install path
  on a real iStoreOS device.

---

## [0.3.3] and earlier — ARCHIVED

See [`archive/luci-app-deepseek_harness_v0.3.3-archive/CHANGELOG.md`](../archive/luci-app-deepseek_harness_v0.3.3-archive/CHANGELOG.md)
for the v0.1.0–v0.3.3 history (12 versions, 5 hotfixes).
