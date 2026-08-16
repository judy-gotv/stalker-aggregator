# Stalker Aggregator / Stalker 聚合服务

[![Platform](https://img.shields.io/badge/平台-Linux-555555?style=flat-square)](https://github.com/judy-gotv/stalker-aggregator/releases)
[![x86_64](https://img.shields.io/badge/x86__64-AMD64-087ea4?style=flat-square)](https://github.com/judy-gotv/stalker-aggregator/releases)
[![aarch64](https://img.shields.io/badge/aarch64-ARM64-087ea4?style=flat-square)](https://github.com/judy-gotv/stalker-aggregator/releases)
[![armv7](https://img.shields.io/badge/armv7-ARMv7-087ea4?style=flat-square)](https://github.com/judy-gotv/stalker-aggregator/releases)
![License](https://img.shields.io/badge/许可-MIT-55a630?style=flat-square)
![Telegram](https://img.shields.io/badge/Telegram-GPT__858-229ED9?style=flat-square&logo=telegram&logoColor=white)

> **v0.0.3** · Linux Binary Release / Linux 二进制发布包

Aggregate authorized Stalker Portal subscriptions into one playlist with web administration, automatic source selection, redirect or media-proxy delivery, IPv4/IPv6, and systemd deployment.  
将合法持有的 Stalker Portal 订阅聚合为一个播放列表，支持网页后台、自动选源、302 重定向或媒体代理、IPv4/IPv6 和 systemd 部署。

| Web Admin / 网页后台 | Playlist / 播放列表 | Health / 健康检查 |
|---|---|---|
| `/admin/ui` | `/playlist.m3u8` | `/health` |

---

## Quick Start / 快速开始

### Remote Installer / GitHub 远程安装脚本

#### 快速安装 / Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/judy-gotv/stalker-aggregator/main/install.sh)
```

#### 或下载后执行 / Or Download and Run

```text
https://raw.githubusercontent.com/judy-gotv/stalker-aggregator/main/install.sh
```

```bash
curl -fsSL https://raw.githubusercontent.com/judy-gotv/stalker-aggregator/main/install.sh -o install.sh
bash install.sh
```

The remote script downloads the release installer and then the matching verified binary.  
远程脚本会下载发布安装器，再下载并校验匹配架构的二进制。

### Local Release Package / 本地发布包

Copy this directory to a Linux server and run:  
将此目录复制到 Linux 服务器后执行：

```bash
chmod +x install.sh
sudo ./install.sh
```

Choose `1) Online install / 在线安装` in the interactive menu. The installer then asks for the port, installation directory, media proxy mode, and administrator account/password before it downloads and deploys the service.  
交互菜单选择 `1) 在线安装 / Online install` 后，安装器会依次询问端口、安装路径、媒体代理模式及管理员账号密码，再下载并部署服务。

On first installation, a strong password is generated if one is not supplied. It is printed once in the final summary.  
首次安装时若未设置密码，安装器会自动生成强密码，并在最终摘要中显示一次。

---

## Included Files / 包含文件

| File / 文件 | Architecture / 架构 | Typical use / 常见设备 |
|---|---|---|
| `stalker-aggregator-amd64` | x86_64 / amd64 | VPS, PC, NAS |
| `stalker-aggregator-aarch64` | ARM64 / aarch64 | ARM server, Raspberry Pi 64-bit |
| `stalker-aggregator-armv7` | ARMv7 hard-float | 32-bit ARM router or SBC |
| `install.sh` | Installer / 安装器 | All supported Linux systems / 所有支持的 Linux 系统 |

The installer detects the current architecture and downloads the matching binary from GitHub Releases. It verifies SHA-256 before installation; a local binary is used only as a fallback.  
安装器会自动识别当前架构，并从 GitHub Releases 下载匹配的二进制；安装前校验 SHA-256，仅在下载失败时回退到本地二进制。

---

## Access / 访问地址

The service listens on IPv4 and IPv6 by default.  
服务默认同时监听 IPv4 与 IPv6。

```text
IPv4 / IPv4: http://<server-ip>:8080
IPv6 / IPv6: http://[<server-ipv6>]:8080
```

| Function / 功能 | URL |
|---|---|
| Web console / 网页后台 | `http://<server-ip>:8080/admin/ui` |
| M3U playlist / 播放列表 | `http://<server-ip>:8080/playlist.m3u8` |
| Health check / 健康检查 | `http://<server-ip>:8080/health` |

Use the admin username and password printed by the installer to access the web console.  
使用安装器最终显示的管理员账号和密码登录网页后台。

---

## Web Admin / 网页后台

- Add, validate, and delete Portal subscriptions / 添加、验证和删除 Portal 订阅
- Set a custom display name / 设置自定义订阅名称
- Configure Portal URL, MAC, and optional upstream credentials / 配置 Portal URL、MAC 和可选上游账号密码
- Show Portal subscription expiry date / 显示 Portal 返回的订阅到期日期
- Add or delete custom channel entries / 添加或删除自定义频道条目
- Choose `302 Redirect` or `Media Proxy` per entry / 为每条频道选择 `302 Redirect` 或 `Media Proxy`
- Restrict individual subscriptions to selected groups / 为每个订阅限制允许的分组

Leave the group selection empty to include all groups. Group selection requires the upstream Portal to return `genre_id`; otherwise all groups remain enabled.  
分组选择留空即显示全部分组。分组功能依赖上游 Portal 返回 `genre_id`；未返回时会维持全部分组。

---

## Scripted Install / 非交互安装

```bash
sudo ./install.sh \
  --port 8080 \
  --install-dir /opt/stalker-aggregator \
  --proxy-media false \
  --admin-user admin \
  --admin-password 'replace-with-a-strong-password'
```

The installer selects the latest GitHub Release by default. Use `--version v0.0.3` to select a specific release. It retrieves the matching asset's SHA-256 digest from the GitHub Release API before downloading.  
安装器默认选择最新 GitHub Release。使用 `--version v0.0.3` 可指定版本；下载前会从 GitHub Release API 读取对应资产的 SHA-256 digest。

---

## Operations / 运维

```bash
# View status / 查看状态
sudo systemctl status stalker-aggregator

# Restart service / 重启服务
sudo systemctl restart stalker-aggregator

# Follow logs / 查看实时日志
sudo journalctl -u stalker-aggregator -f
```

To change the port without reinstalling, run `sudo ./install.sh` and select `2) 在线更改端口 / Update running service port`. The installer asks for the new port, updates the configuration, and restarts the service automatically.  
要在不重新安装的情况下修改端口，运行 `sudo ./install.sh` 并选择 `2) 在线更改端口 / Update running service port`。安装器会询问新端口、更新配置并自动重启服务。

To upgrade safely, select `3) 在线升级服务 / Upgrade running service`. It downloads and verifies the latest matching binary, atomically replaces only the executable, and restarts the service. The environment file, SQLite database, subscriptions, and administrator credentials are preserved.  
要安全升级，请选择 `3) 在线升级服务 / Upgrade running service`。该功能会下载并校验最新匹配架构二进制，只原子替换可执行文件后重启服务；环境文件、SQLite 数据库、订阅和管理员凭据都会保留。

---

## Configuration / 配置

Runtime configuration file / 运行时配置文件：

```text
/etc/stalker-aggregator.env
```

```ini
STALKER_BIND=0.0.0.0:8080
STALKER_BIND_V6=[::]:8080
STALKER_PROXY_MEDIA=false
ADMIN_USERNAME=admin
ADMIN_PASSWORD=<your-password>
```

With `STALKER_PROXY_MEDIA=false`, playback uses HTTP 302 and consumes no service media bandwidth. Set it to `true` to stream media through this server.  
`STALKER_PROXY_MEDIA=false` 时播放使用 HTTP 302，不消耗服务端媒体带宽。设为 `true` 后会由本服务转发媒体流。

---

## Download Verification / 下载校验

The installer retrieves each release asset's `sha256` digest from the GitHub Release API, downloads the corresponding binary, and verifies it before installation. There are no version-specific checksums hard-coded in the script.  
安装器会从 GitHub Release API 读取每个发布资产的 `sha256` digest，下载对应二进制后再验证。脚本中不再固定任何版本的校验值。

---

## Notes / 注意事项

- Use only subscriptions and upstream services you are authorized to use. / 仅使用你有权使用的订阅和上游服务。
- Portal implementations differ; expiry and group information depend on compatible upstream fields. / 不同 Portal 实现存在差异，到期日与分组信息取决于上游返回的兼容字段。
- The SQLite database is at `<install-dir>/data/stalker.db`; back it up before major system changes. / SQLite 数据库位于 `<install-dir>/data/stalker.db`，系统重大变更前请备份。
