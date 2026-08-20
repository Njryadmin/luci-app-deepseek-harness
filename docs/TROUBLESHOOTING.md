# Troubleshooting

## Installation

### "failed to download bundle from any mirror"

- Check DNS: `nslookup github.com`
- Check HTTPS: `curl -I https://github.com`
- Check disk space: `df -h /tmp /opt`
- Check proxy: if you use `https_proxy`, ensure `curl` and `wget` both respect it
- Try manually: `wget https://github.com/Njryadmin/luci-app-deepseek-harness/releases/download/v1.0.0-alpha.1/dsh-bundle-musl-x86_64-0.1.0-rc.7.tar.xz`

### "SHA256 mismatch"

The bundle was downloaded partially or mirrored incompletely.

- Check `tmp/dsh-bundle-staging/` — stale files may be there
- Clear and retry: `rm -rf /tmp/dsh-bundle-staging && dsh-env setup`

### "architecture not supported"

- Run `uname -m` — must return `x86_64` or `aarch64`
- Set UCI explicitly: `uci set deepseek_harness.main.arch=x86_64`

### "libc must be musl"

You may be on a non-iStoreOS OpenWrt with glibc (rare). Build a glibc bundle by
triggering `bundle.yml` with a custom Docker base (`debian:bookworm-slim`).

## Runtime

### Service won't start

```sh
dsh-env status    # check installed + running flags
dsh-env logs      # tail /var/log/dsh.log
```

Common causes:

- **"node binary not executable"**: arch mismatch. Re-run with explicit `arch` UCI value.
- **"dsh binary missing"**: bundle corrupted. `dsh-env teardown && dsh-env setup`.
- **"EADDRINUSE :8123"**: another process bound the port. `netstat -tlnp | grep 8123`.

### "Runtime error: ... attempt to call field 'stform' (a nil value)"

This was a v0.3.1 bug; v1.0.0+ does not have this. If you see it, you may have
upgraded from v0.3.x without uninstalling. Run:

```sh
opkg remove --force-depends luci-app-deepseek_harness
opkg install luci-app-deepseek-harness_1.0.0-alpha.1_all.ipk
rm -f /tmp/luci-indexcache
```

### "ENOENT /opt/deepseek-harness/profile/default.json"

`dsh-apply-config.sh` didn't run. Run it manually:

```sh
dsh-env setup    # runs fetch + apply + restart
```

### High CPU / OOM

dsh monorepo is heavy. Verify:

```sh
free -h
top -bn1 | grep node
```

If RSS > 800 MB, consider:

- Reducing `max_tokens` (default 4096 → 1024)
- Switching model to `deepseek-chat` (cheaper than `deepseek-reasoner`)
- Adding swap: `dd if=/dev/zero of=/opt/swap bs=1M count=512 && chmod 600 /opt/swap && mkswap /opt/swap && swapon /opt/swap`

## Network

### LAN clients can't reach :8123

If `listen_host = 127.0.0.1`:

```sh
uci set deepseek_harness.main.listen_host='0.0.0.0'
uci set deepseek_harness.main.relay_enabled='0'   # not needed when binding 0.0.0.0
dsh-env restart
```

If `listen_host = 0.0.0.0` but LAN still fails:

```sh
# Check firewall
iptables -L INPUT -n | grep 8123
uci show firewall | grep 8123
# Add a rule (LuCI: Network → Firewall → Traffic Rules)
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-DSH'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest_port='8123'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall restart
```

### CORS errors in browser console

```sh
uci set deepseek_harness.main.cors_origins='https://your-domain.example'
uci commit deepseek_harness
dsh-env restart
```

## Logs

### Log file growing unbounded

dsh doesn't rotate logs. Add a cron:

```sh
cat > /etc/cron.daily/dsh-logrotate <<'EOF'
#!/bin/sh
[ -f /var/log/dsh.log ] || exit 0
mv /var/log/dsh.log /var/log/dsh.log.old
kill -HUP $(cat /var/run/dsh.pid 2>/dev/null) 2>/dev/null || true
EOF
chmod +x /etc/cron.daily/dsh-logrotate
```

### Want to see Node.js stack traces

```sh
uci set deepseek_harness.main.log_level=debug
dsh-env restart
dsh-env logs
```

## Recovery

### Total reset

```sh
dsh-env teardown     # removes /opt/deepseek-harness but keeps UCI
uci delete deepseek_harness.main
uci commit deepseek_harness
opkg remove luci-app-deepseek-harness
rm -rf /opt/deepseek-harness /var/log/dsh.log /var/run/dsh.pid
```

### Restore from v0.x.x (if migrating)

```sh
opkg remove luci-app-deepseek_harness
opkg install luci-app-deepseek-harness_1.0.0-alpha.1_all.ipk
# UCI section name is the same (deepseek_harness.main), so existing config
# values are preserved. Just re-run `dsh-env setup` to get the new bundle.
```

## Getting help

- Open an issue: <https://github.com/Njryadmin/luci-app-deepseek-harness/issues>
- Include `dsh-env status` output + relevant `dsh-env logs` lines
