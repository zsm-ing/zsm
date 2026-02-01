#!/bin/sh
# Alpine sing-box 更新脚本（HTML / 抗封锁稳定版）

REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
BACKUP_BIN="$BIN_PATH.bak"
TEMP_DIR="/tmp/sing-box_update"
MAX_RETRY=3
RELEASE_PAGE="https://github.com/SagerNet/sing-box/releases"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check_dependencies() {
  for cmd in curl tar find uname grep sed awk; do
    command -v "$cmd" >/dev/null 2>&1 || {
      echo -e "${RED}缺少依赖: $cmd${NC}"
      exit 1
    }
  done
}

detect_arch() {
  case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l|armv7*) ARCH="armv7" ;;
    armv6l|armv6*) ARCH="armv6" ;;
    mipsel*) ARCH="mipsel" ;;
    mips*) ARCH="mips" ;;
    *)
      echo -e "${RED}不支持架构: $(uname -m)${NC}"
      exit 1
      ;;
  esac
  echo -e "${CYAN}检测到架构: $ARCH${NC}"
}

fetch() {
  url="$1"
  out="$2"
  i=0
  while [ "$i" -lt "$MAX_RETRY" ]; do
    curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$out" && return 0
    i=$((i+1))
    sleep 2
  done
  return 1
}

get_versions() {
  html="$TEMP_DIR/releases.html"
  fetch "$RELEASE_PAGE" "$html" || return

  stable=$(grep -oE '/tag/v[0-9]+\.[0-9]+\.[0-9]+"' "$html" \
    | head -n1 | sed 's#.*/v##;s/"//')

  beta=$(grep -oE '/tag/v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+"' "$html" \
    | head -n1 | sed 's#.*/v##;s/"//')

  echo "$stable|$beta"
}

download_pkg() {
  ver="$1"
  for suffix in "linux-$ARCH-musl" "linux-$ARCH"; do
    url="https://github.com/$REPO/releases/download/v$ver/sing-box-$ver-$suffix.tar.gz"
    fetch "$url" "$TEMP_DIR/sb.tar.gz" && return 0
  done
  return 1
}

install_version() {
  ver="$1"
  [ -z "$ver" ] && return 1

  rm -rf "$TEMP_DIR"
  mkdir -p "$TEMP_DIR"

  echo -e "${CYAN}下载 v$ver${NC}"
  download_pkg "$ver" || {
    echo -e "${RED}下载失败${NC}"
    return 1
  }

  tar -xzf "$TEMP_DIR/sb.tar.gz" -C "$TEMP_DIR" || return 1

  bin_file=$(find "$TEMP_DIR" -type f -name sing-box -perm -111 | head -n1)
  [ -z "$bin_file" ] && return 1

  [ -x "$BIN_PATH" ] && mv "$BIN_PATH" "$BACKUP_BIN"

  mv "$bin_file" "$BIN_PATH"
  chmod 755 "$BIN_PATH"

  if command -v rc-service >/dev/null 2>&1 && [ -f /etc/init.d/sing-box ]; then
    rc-service sing-box restart || true
  fi

  "$BIN_PATH" version >/dev/null 2>&1 \
    && echo -e "${GREEN}sing-box $ver 安装成功${NC}" \
    || rollback_version
}

rollback_version() {
  [ -f "$BACKUP_BIN" ] || {
    echo -e "${RED}无备份可回滚${NC}"
    return
  }
  mv "$BACKUP_BIN" "$BIN_PATH"
  chmod 755 "$BIN_PATH"
  command -v rc-service >/dev/null 2>&1 && rc-service sing-box restart || true
  echo -e "${GREEN}已回滚${NC}"
}

show_menu() {
  cur=$("$BIN_PATH" version 2>/dev/null | awk '{print $3}')
  vers="$(get_versions)"

  stable="${vers%%|*}"
  beta="${vers##*|}"

  echo -e "${CYAN}==== Sing-box 更新助手 ====${NC}"
  echo -e "当前版本: ${GREEN}${cur:-未安装}${NC}"
  echo "1) 稳定版 : ${stable:-无}"
  echo "2) 测试版 : ${beta:-无}"
  echo "0) 退出"
  printf "请选择: "
  read -r c

  case "$c" in
    1) install_version "$stable" ;;
    2) install_version "$beta" ;;
    0) exit 0 ;;
    *) echo "无效输入" ;;
  esac
}

main() {
  check_dependencies
  detect_arch
  show_menu
}

main
