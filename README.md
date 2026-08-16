# Stalker Aggregator Binary Release

这是 Stalker Portal 多订阅聚合服务的 Linux 二进制发布目录。服务将多个合法持有的 Portal 订阅汇总成播放列表，并支持 302 重定向或媒体代理模式。

## Included Files

| File | Linux architecture |
|---|---|
| `stalker-aggregator-amd64` | x86_64 / amd64 |
| `stalker-aggregator-aarch64` | ARM64 / aarch64 |
| `stalker-aggregator-armv7` | ARMv7 hard-float / armv7l |
| `install.sh` | Interactive installer |

The installer detects the current architecture automatically.

## Install

Copy the complete `dist` directory to the Linux server, then run:

```bash
cd dist
chmod +x install.sh
sudo ./install.sh
```

The interactive menu lets you set:

- Service port, default `8080`
- Installation directory, default `/opt/stalker-aggregator`
- Media proxy mode
- Web admin username and password
- Online port change for an installed service

Non-interactive example:

```bash
sudo ./install.sh \
  --port 8080 \
  --install-dir /opt/stalker-aggregator \
  --proxy-media false \
  --admin-user admin \
  --admin-password 'replace-with-a-strong-password'
```

On first install, when no password is specified, the installer creates an `admin` account with a random password. The install summary prints the username and password once. They are stored in `/etc/stalker-aggregator.env` with `0600` permissions.

## Access

The service listens on both stacks by default:

```text
IPv4: http://<server-ip>:<port>
IPv6: http://[<server-ipv6>]:<port>
```

| Function | Address |
|---|---|
| Web admin | `/admin/ui` |
| Playlist | `/playlist.m3u8` |
| Health | `/health` |

Open `http://<server-ip>:8080/admin/ui` and log in with the installer-created admin username and password.

## Web Admin

The web admin can:

- Add and validate Portal subscriptions using a display name, Portal URL, MAC, and optional upstream login/password
- Show subscription status and Portal account expiry date when provided by the upstream Portal
- Remove subscriptions
- Add or remove custom channel entries
- Choose redirect or media-proxy delivery per channel entry
- Restrict each subscription to selected upstream group IDs; leaving the selection empty includes all groups

Group selection depends on the upstream Portal exposing a `genre_id`. Portals without group IDs continue to include all channels by default.

## Operations

```bash
sudo systemctl status stalker-aggregator
sudo systemctl restart stalker-aggregator
sudo journalctl -u stalker-aggregator -f
```

To change the port without reinstalling, run the installer again, select `在线更改端口 / Update running service port`, enter the new port, and the service is restarted automatically.

## Configuration

Runtime configuration is in:

```text
/etc/stalker-aggregator.env
```

Important values:

```ini
STALKER_BIND=0.0.0.0:8080
STALKER_BIND_V6=[::]:8080
STALKER_PROXY_MEDIA=false
ADMIN_USERNAME=admin
ADMIN_PASSWORD=<generated-or-custom-password>
```

`STALKER_PROXY_MEDIA=false` uses short-lived upstream links and returns HTTP 302. Set it to `true` to stream media through this server. Proxy mode consumes server bandwidth and should be protected by suitable network limits.

## Notes

- Use only subscriptions and upstream services you are authorized to use.
- Portal implementations differ; account-expiry and group metadata are shown only when the upstream returns compatible fields.
- This release uses SQLite at `<install-dir>/data/stalker.db`. Back up this file before a major system change.
