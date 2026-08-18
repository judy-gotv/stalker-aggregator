#!/usr/bin/env bash
set -euo pipefail

PORT=8080
INSTALL_DIR=/opt/stalker-aggregator
PROXY_MEDIA=false
ADMIN_USERNAME=
ADMIN_PASSWORD=
SERVICE_NAME=stalker-aggregator
RELEASE_REPOSITORY=judy-gotv/stalker-aggregator
RELEASE_TAG=latest
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INTERACTIVE=true

if [ -t 1 ]; then
  BOLD='\033[1m'; CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'
else
  BOLD=''; CYAN=''; GREEN=''; YELLOW=''; RED=''; RESET=''
fi

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [--port PORT] [--install-dir PATH] [--proxy-media true|false] [--admin-user USER] [--admin-password PASSWORD] [--version TAG]

交互安装：直接执行 sudo ./install.sh
Interactive install: run sudo ./install.sh without options.
EOF
}

valid_port() { case "$1" in *[!0-9]*|'') return 1;; esac; [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

download_binary() {
  local asset="stalker-aggregator-$ARCH" api_url metadata_url expected actual tag url
  if [ "$RELEASE_TAG" = latest ]; then
    api_url="https://api.github.com/repos/$RELEASE_REPOSITORY/releases/latest"
  else
    api_url="https://api.github.com/repos/$RELEASE_REPOSITORY/releases/tags/$RELEASE_TAG"
  fi
  metadata_url=$(mktemp)
  if ! curl --fail --location --retry 3 --silent --show-error "$api_url" -o "$metadata_url"; then
    rm -f "$metadata_url"; return 1
  fi
  tag=$(sed -n 's/^[[:space:]]*"tag_name": "\([^"]*\)".*/\1/p' "$metadata_url" | head -n 1)
  expected=$(sed -n "/\"name\": \"$asset\"/,/\"browser_download_url\"/s/.*\"digest\": \"sha256:\([0-9a-f]*\)\".*/\1/p" "$metadata_url" | head -n 1)
  rm -f "$metadata_url"
  if [ -z "$tag" ] || [ -z "$expected" ]; then
    echo "Release 缺少目标资产或 SHA-256 digest / Release asset or SHA-256 digest is missing" >&2
    return 1
  fi
  url="https://github.com/$RELEASE_REPOSITORY/releases/download/$tag/$asset"
  DOWNLOADED_BINARY=$(mktemp)
  printf '下载版本 %s / Downloading %s for %s...\n' "$tag" "$asset" "$ARCH"
  if ! curl --fail --location --retry 3 --silent --show-error "$url" -o "$DOWNLOADED_BINARY"; then
    rm -f "$DOWNLOADED_BINARY"; DOWNLOADED_BINARY=; return 1
  fi
  actual=$(sha256sum "$DOWNLOADED_BINARY" | awk '{print $1}')
  if [ "$actual" != "$expected" ]; then
    rm -f "$DOWNLOADED_BINARY"; DOWNLOADED_BINARY=
    echo "二进制校验失败 / Download checksum verification failed" >&2; return 1
  fi
  chmod 0755 "$DOWNLOADED_BINARY"
  return 0
}

set_admin_credentials() {
  local username password
  read -r -p '管理账户 / Admin username [admin]: ' username
  username=${username:-admin}
  case "$username" in *[!A-Za-z0-9_.-]*|'') printf '%b\n' "${RED}账户只能使用字母、数字、点、下划线或连字符 / Invalid username.${RESET}"; sleep 1; return;; esac
  read -r -p '管理密码（输入可见）/ Admin password (visible, blank = auto): ' password
  if [ -n "$password" ] && [ "${#password}" -lt 12 ]; then
    printf '%b\n' "${RED}密码至少 12 个字符 / Password must be at least 12 characters.${RESET}"; sleep 1; return
  fi
  ADMIN_USERNAME=$username
  ADMIN_PASSWORD=$password
}

update_running_port() {
  local env_file=/etc/stalker-aggregator.env current_port value
  if [ "$(id -u)" -ne 0 ]; then printf '%b\n' "${RED}请以 root 运行 / Run as root.${RESET}"; return; fi
  if [ ! -f "$env_file" ] || ! systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
    printf '%b\n' "${RED}未找到已安装服务 / Installed service not found.${RESET}"; return
  fi
  current_port=$(sed -n 's/^STALKER_BIND=0.0.0.0:\([0-9][0-9]*\)$/\1/p' "$env_file" | head -n 1)
  current_port=${current_port:-$PORT}
  read -r -p "新服务端口 / New port [$current_port]: " value
  value=${value:-$current_port}
  if ! valid_port "$value"; then
    printf '%b\n' "${RED}端口无效 / Invalid port.${RESET}"; return
  fi
  PORT=$value
  sed -i -e "s|^STALKER_BIND=.*|STALKER_BIND=0.0.0.0:$PORT|" -e "s|^STALKER_BIND_V6=.*|STALKER_BIND_V6=[::]:$PORT|" "$env_file"
  grep -q '^STALKER_BIND_V6=' "$env_file" || printf 'STALKER_BIND_V6=[::]:%s\n' "$PORT" >> "$env_file"
  systemctl restart "$SERVICE_NAME"
  printf '%b\n' "${GREEN}端口已更新并生效 / Port updated and service restarted: $PORT${RESET}"
}

prompt_install_options() {
  local value
  read -r -p "服务端口 / Service port [$PORT]: " value
  value=${value:-$PORT}
  if ! valid_port "$value"; then
    printf '%b\n' "${RED}端口无效 / Invalid port.${RESET}"
    return 1
  fi
  PORT=$value

  read -r -p "安装路径 / Install path [$INSTALL_DIR]: " value
  value=${value:-$INSTALL_DIR}
  case "$value" in
    /*) INSTALL_DIR=${value%/} ;;
    *) printf '%b\n' "${RED}请使用绝对路径 / Use an absolute path.${RESET}"; return 1 ;;
  esac

  read -r -p "代理媒体流量？/ Proxy media traffic? [y/N]: " value
  case "${value:-n}" in
    y|Y|yes|YES) PROXY_MEDIA=true ;;
    n|N|no|NO) PROXY_MEDIA=false ;;
    *) printf '%b\n' "${RED}请输入 y 或 n / Please enter y or n.${RESET}"; return 1 ;;
  esac

  set_admin_credentials
  [ -n "$ADMIN_USERNAME" ] || return 1
}

upgrade_running_service() {
  local current_dir staged_binary
  if [ "$(id -u)" -ne 0 ]; then printf '%b\n' "${RED}请以 root 运行 / Run as root.${RESET}"; return; fi
  current_dir=$(systemctl show --property=WorkingDirectory --value "$SERVICE_NAME" 2>/dev/null || true)
  if [ -z "$current_dir" ] || [ ! -x "$current_dir/stalker-aggregator" ]; then
    printf '%b\n' "${RED}未找到已安装服务 / Installed service not found.${RESET}"; return
  fi
  DOWNLOADED_BINARY=
  if ! download_binary; then
    printf '%b\n' "${RED}升级下载或校验失败 / Upgrade download or verification failed.${RESET}"; return
  fi
  staged_binary="$current_dir/.stalker-aggregator.new"
  install -o root -g root -m 0755 "$DOWNLOADED_BINARY" "$staged_binary"
  mv -f "$staged_binary" "$current_dir/stalker-aggregator"
  rm -f "$DOWNLOADED_BINARY"
  systemctl restart "$SERVICE_NAME"
  printf '%b\n' "${GREEN}升级完成 / Upgrade complete: $RELEASE_TAG${RESET}"
  printf '%b\n' "${YELLOW}订阅、数据库和配置未被修改 / Subscriptions, database, and configuration were preserved.${RESET}"
}

uninstall_service() {
  local env_file=/etc/stalker-aggregator.env unit_file="/etc/systemd/system/$SERVICE_NAME.service"
  local current_dir= remove_dir=false confirm=
  if [ "$(id -u)" -ne 0 ]; then
    printf '%b\n' "${RED}请以 root 运行 / Run as root.${RESET}"
    return
  fi
  current_dir=$(systemctl show --property=WorkingDirectory --value "$SERVICE_NAME" 2>/dev/null || true)
  if [ -z "$current_dir" ] && [ -f "$unit_file" ]; then
    current_dir=$(sed -n 's/^WorkingDirectory=//p' "$unit_file" | head -n 1)
  fi
  if [ -z "$current_dir" ] && [ ! -f "$env_file" ] && [ ! -f "$unit_file" ]; then
    printf '%b\n' "${RED}未找到已安装服务 / Installed service not found.${RESET}"
    return
  fi
  printf '%b\n' "${RED}${BOLD}警告：卸载会永久删除服务、配置、数据库和全部订阅数据。${RESET}"
  printf '%b\n' "${RED}${BOLD}Warning: uninstall permanently removes the service, configuration, database, and all subscriptions.${RESET}"
  [ -n "$current_dir" ] && printf '安装路径 / Install path: %s\n' "$current_dir"
  read -r -p '确认完全卸载？/ Confirm complete uninstall [y/N]: ' confirm
  case "$confirm" in y|Y|yes|YES) ;; *) printf '%b\n' "${YELLOW}已取消卸载 / Uninstall cancelled.${RESET}"; return ;; esac

  systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f -- "$unit_file" "$env_file"
  if [ -n "$current_dir" ] && [ "$current_dir" != "/" ]; then
    if [ "$current_dir" = "/opt/stalker-aggregator" ]; then
      remove_dir=true
    elif [ -f "$current_dir/.stalker-aggregator-install" ] && grep -q '^REMOVE_INSTALL_DIR=true$' "$current_dir/.stalker-aggregator-install"; then
      remove_dir=true
    fi
    if [ "$remove_dir" = true ]; then
      rm -rf -- "$current_dir"
    else
      rm -f -- "$current_dir/stalker-aggregator" "$current_dir/.stalker-aggregator.new" "$current_dir/.stalker-aggregator-install"
      rm -f -- "$current_dir/data/stalker.db" "$current_dir/data/stalker.db-shm" "$current_dir/data/stalker.db-wal"
      rmdir -- "$current_dir/data" 2>/dev/null || true
      rmdir -- "$current_dir" 2>/dev/null || true
    fi
  fi
  id -u stalker >/dev/null 2>&1 && userdel stalker >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
  printf '%b\n' "${GREEN}${BOLD}卸载完成，服务及其数据已清除 / Uninstall complete; service and data removed.${RESET}"
}

print_summary() {
  printf '%b\n' "${CYAN}${BOLD}========================================${RESET}"
  printf '%b\n' "${GREEN}${BOLD}安装完成 / Installation complete${RESET}"
  printf '%b\n' "${CYAN}${BOLD}========================================${RESET}"
  printf '架构 / Architecture     : %s\n' "$ARCH"
  printf '安装路径 / Install path  : %s\n' "$INSTALL_DIR"
  printf 'IPv4 监听 / IPv4 bind    : http://0.0.0.0:%s\n' "$PORT"
  printf 'IPv6 监听 / IPv6 bind    : http://[::]:%s\n' "$PORT"
  printf '媒体代理 / Media proxy   : %s\n' "$PROXY_MEDIA"
  printf '管理账户 / Admin username : %s\n' "$(sed -n 's/^ADMIN_USERNAME=//p' /etc/stalker-aggregator.env)"
  printf '管理密码 / Admin password : %s\n' "$(sed -n 's/^ADMIN_PASSWORD=//p' /etc/stalker-aggregator.env)"
  printf '认证方式 / Authentication : HTTP Basic 或 Bearer Token / HTTP Basic or Bearer Token\n'
  printf '配置文件 / Config file   : /etc/stalker-aggregator.env\n'
  printf '播放列表 / Playlist      : http://<server-ip>:%s/playlist.m3u8\n' "$PORT"
  printf '健康检查 / Health        : http://<server-ip>:%s/health\n' "$PORT"
  printf '网页后台 / Web console    : http://<server-ip>:%s/admin/ui\n' "$PORT"
  printf '服务状态 / Status        : systemctl status %s\n' "$SERVICE_NAME"
  printf '服务日志 / Logs          : journalctl -u %s -f\n' "$SERVICE_NAME"
  printf '%b\n' "${YELLOW}管理员密钥保存在配置文件中，不会显示在终端。${RESET}"
}

show_menu() {
  clear 2>/dev/null || true
  printf '%b\n' "${CYAN}${BOLD}========================================${RESET}"
  printf '%b\n' "${CYAN}${BOLD}   Stalker 聚合服务安装程序 / Installer   ${RESET}"
  printf '%b\n' "${CYAN}${BOLD}========================================${RESET}"
  printf '  系统架构 / Architecture : %s\n' "$ARCH"
  printf '  服务端口 / Port          : %s\n' "$PORT"
  printf '  安装路径 / Install path  : %s\n' "$INSTALL_DIR"
  printf '  媒体代理 / Media proxy   : %s\n\n' "$PROXY_MEDIA"
  printf '%b\n' "  ${GREEN}1${RESET}) 在线安装 / Online install"
  printf '%b\n' "  ${GREEN}2${RESET}) 在线更改端口 / Update running service port"
  printf '%b\n' "  ${GREEN}3${RESET}) 在线升级服务 / Upgrade running service"
  printf '%b\n' "  ${RED}4${RESET}) 在线卸载 / Online uninstall"
  printf '%b\n' "  ${GREEN}0${RESET}) 退出 / Exit"
}

configure_interactively() {
  while true; do
    show_menu
    read -r -p '请选择 / Select [0-4]: ' choice
    case "$choice" in
      1) prompt_install_options && break; read -r -p '按 Enter 返回菜单 / Press Enter to return: ' _ ;;
      2) update_running_port; read -r -p '按 Enter 返回菜单 / Press Enter to return: ' _ ;;
      3) upgrade_running_service; read -r -p '按 Enter 返回菜单 / Press Enter to return: ' _ ;;
      4) uninstall_service; read -r -p '按 Enter 返回菜单 / Press Enter to return: ' _ ;;
      0) exit 0 ;;
      *) printf '%b\n' "${RED}选项无效 / Invalid selection.${RESET}"; sleep 1 ;;
    esac
  done
}

while [ "$#" -gt 0 ]; do
  INTERACTIVE=false
  case "$1" in
    --port) PORT=${2:?missing value for --port}; shift 2 ;;
    --install-dir) INSTALL_DIR=${2:?missing value for --install-dir}; shift 2 ;;
    --proxy-media) PROXY_MEDIA=${2:?missing value for --proxy-media}; shift 2 ;;
    --admin-user) ADMIN_USERNAME=${2:?missing value for --admin-user}; shift 2 ;;
    --admin-password) ADMIN_PASSWORD=${2:?missing value for --admin-password}; shift 2 ;;
    --version) RELEASE_TAG=${2:?missing value for --version}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  armv7l|armv7) ARCH=armv7 ;;
  *) echo "不支持的系统架构 / Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [ "$INTERACTIVE" = true ]; then configure_interactively; fi
valid_port "$PORT" || { echo "端口必须为 1-65535 / Port must be between 1 and 65535" >&2; exit 2; }
case "$INSTALL_DIR" in /*) ;; *) echo "安装路径必须为绝对路径 / Install path must be absolute" >&2; exit 2;; esac
case "$PROXY_MEDIA" in true|false) ;; *) echo "--proxy-media 必须为 true 或 false / must be true or false" >&2; exit 2;; esac
if [ "$(id -u)" -ne 0 ]; then echo "请以 root 运行 / Run: sudo $0" >&2; exit 1; fi

DOWNLOADED_BINARY=
if download_binary; then
  SOURCE=$DOWNLOADED_BINARY
  trap 'rm -f "$DOWNLOADED_BINARY"' EXIT
else
  SOURCE="$SCRIPT_DIR/stalker-aggregator-$ARCH"
  [ -x "$SOURCE" ] || { echo "下载失败且找不到本地二进制 / Download failed and local binary is missing: $SOURCE" >&2; exit 1; }
  printf '%b\n' "${YELLOW}使用本地二进制 / Using local binary fallback.${RESET}"
fi
REMOVE_INSTALL_DIR=false
[ -d "$INSTALL_DIR" ] || REMOVE_INSTALL_DIR=true
id -u stalker >/dev/null 2>&1 || useradd --system --home-dir "$INSTALL_DIR" --shell /usr/sbin/nologin stalker
install -d -o stalker -g stalker -m 0750 "$INSTALL_DIR" "$INSTALL_DIR/data"
install -o root -g root -m 0755 "$SOURCE" "$INSTALL_DIR/stalker-aggregator"
if [ ! -f "$INSTALL_DIR/.stalker-aggregator-install" ]; then
  printf 'REMOVE_INSTALL_DIR=%s\n' "$REMOVE_INSTALL_DIR" > "$INSTALL_DIR/.stalker-aggregator-install"
  chown root:root "$INSTALL_DIR/.stalker-aggregator-install"
  chmod 0644 "$INSTALL_DIR/.stalker-aggregator-install"
fi

ENV_FILE=/etc/stalker-aggregator.env
if [ ! -f "$ENV_FILE" ]; then
  ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
  ADMIN_PASSWORD=${ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n')}
  umask 077
  printf 'ADMIN_TOKEN=%s\nSTALKER_DB_KEY=%s\nADMIN_USERNAME=%s\nADMIN_PASSWORD=%s\n' "$(openssl rand -hex 32)" "$(openssl rand -hex 32)" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" > "$ENV_FILE"
elif [ -n "$ADMIN_USERNAME" ] || [ -n "$ADMIN_PASSWORD" ]; then
  [ -n "$ADMIN_USERNAME" ] && sed -i "s|^ADMIN_USERNAME=.*|ADMIN_USERNAME=$ADMIN_USERNAME|" "$ENV_FILE"
  [ -n "$ADMIN_PASSWORD" ] && sed -i "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=$ADMIN_PASSWORD|" "$ENV_FILE"
fi
sed -i \
  -e "s|^STALKER_BIND=.*|STALKER_BIND=0.0.0.0:$PORT|" \
  -e "s|^STALKER_BIND_V6=.*|STALKER_BIND_V6=[::]:$PORT|" \
  -e "s|^STALKER_DATABASE_URL=.*|STALKER_DATABASE_URL=sqlite://$INSTALL_DIR/data/stalker.db|" \
  -e "s|^STALKER_PROXY_MEDIA=.*|STALKER_PROXY_MEDIA=$PROXY_MEDIA|" "$ENV_FILE"
grep -q '^STALKER_BIND=' "$ENV_FILE" || printf 'STALKER_BIND=0.0.0.0:%s\n' "$PORT" >> "$ENV_FILE"
grep -q '^STALKER_BIND_V6=' "$ENV_FILE" || printf 'STALKER_BIND_V6=[::]:%s\n' "$PORT" >> "$ENV_FILE"
grep -q '^STALKER_DATABASE_URL=' "$ENV_FILE" || printf 'STALKER_DATABASE_URL=sqlite://%s/data/stalker.db\n' "$INSTALL_DIR" >> "$ENV_FILE"
grep -q '^STALKER_PROXY_MEDIA=' "$ENV_FILE" || printf 'STALKER_PROXY_MEDIA=%s\n' "$PROXY_MEDIA" >> "$ENV_FILE"
grep -q '^ADMIN_USERNAME=' "$ENV_FILE" || printf 'ADMIN_USERNAME=admin\n' >> "$ENV_FILE"
grep -q '^ADMIN_PASSWORD=' "$ENV_FILE" || printf 'ADMIN_PASSWORD=%s\n' "$(openssl rand -base64 24 | tr -d '\n')" >> "$ENV_FILE"
chmod 0600 "$ENV_FILE"

cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Stalker Portal Aggregator
After=network.target
[Service]
User=stalker
Group=stalker
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/stalker-aggregator
EnvironmentFile=$ENV_FILE
Restart=on-failure
RestartSec=5
TimeoutStopSec=15
KillSignal=SIGTERM
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
print_summary
