#!/bin/sh
# Alpine sing-box 更新脚本（ghproxy 默认，自动回滚 / 多架构 / BusyBox 兼容）

REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
BACKUP_BIN="$BIN_PATH.bak"
TEMP_DIR="/tmp/sing-box_update"
MAX_RETRY=3

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# =====================
# 依赖检查
# =====================
check_dependencies() {
    for cmd in jq curl tar find uname; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}缺少依赖: $cmd${NC}"
            exit 1
        fi
    done
}

# =====================
# 架构检测
# =====================
detect_arch() {
    case "$(uname -m)" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l|armv7*) ARCH="armv7" ;;
        armv6l|armv6*) ARCH="armv6" ;;
        mipsel*) ARCH="mipsel" ;;
        mips*) ARCH="mips" ;;
        *) echo -e "${RED}不支持架构: $(uname -m)${NC}"; exit 1 ;;
    esac
    echo -e "${CYAN}检测到架构: $ARCH${NC}"
}

# =====================
# curl 带重试
# =====================
fetch_with_retry() {
    url="$1"
    out="$2"
    i=0
    while [ $i -lt $MAX_RETRY ]; do
        curl -fsSL -H "User-Agent: sing-box-update" "$url" -o "$out" && return 0
        i=$((i+1))
        sleep 2
    done
    return 1
}

# =====================
# 下载 release 资产
# =====================
download_asset() {
    url="$1"
    out="$2"

    echo -e "${CYAN}下载: $url${NC}"
    fetch_with_retry "https://ghproxy.com/$url" "$out" || {
        echo -e "${RED}下载失败: $url${NC}"
        return 1
    }
}

# =====================
# 获取 releases
# =====================
fetch_releases() {
    api="https://ghproxy.com/https://api.github.com/repos/$REPO/releases?per_page=5"
    fetch_with_retry "$api" /tmp/releases.json || {
        echo -e "${RED}获取 releases 失败${NC}"
        exit 1
    }
    cat /tmp/releases.json
}

# =====================
# 安装指定版本
# =====================
install_version() {
    ver="$1"
    rel="$2"
    expected="sing-box-$ver-linux-$ARCH-musl.tar.gz"

    url=$(echo "$rel" | jq -r --arg n "$expected" '
        .[] | .assets[] | select(.name==$n) | .browser_download_url
    ' | head -n1)

    [ -z "$url" ] && {
        echo -e "${RED}未找到 $expected${NC}"
        return 1
    }

    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    download_asset "$url" "$TEMP_DIR/sb.tgz" || return 1

    tar -xzf "$TEMP_DIR/sb.tgz" -C "$TEMP_DIR" || return 1
    bin=$(find "$TEMP_DIR" -name sing-box -type f | head -n1)
    [ -f "$bin" ] || return 1

    [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box stop 2>/dev/null
    [ -f "$BIN_PATH" ] && mv "$BIN_PATH" "$BACKUP_BIN"

    mv "$bin" "$BIN_PATH"
    chmod 755 "$BIN_PATH"

    if "$BIN_PATH" version >/dev/null 2>&1; then
        echo -e "${GREEN}sing-box $ver 安装成功${NC}"
        [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box restart
    else
        rollback_version
    fi
}

# =====================
# 回滚
# =====================
rollback_version() {
    if [ -f "$BACKUP_BIN" ]; then
        mv "$BACKUP_BIN" "$BIN_PATH"
        chmod 755 "$BIN_PATH"
        [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box restart
        echo -e "${GREEN}已回滚${NC}"
    else
        echo -e "${RED}无备份可回滚${NC}"
    fi
}

# =====================
# 菜单
# =====================
show_menu() {
    cur=$("$BIN_PATH" version 2>/dev/null | awk '{print $3}')
    rel=$(fetch_releases)

    stable=$(echo "$rel" | jq -r '[.[]|select(.prerelease==false)][0].tag_name' | sed 's/^v//')
    beta=$(echo "$rel" | jq -r '[.[]|select(.prerelease==true)][0].tag_name' | sed 's/^v//')

    echo -e "${CYAN}==== Sing-box 更新助手 ====${NC}"
    echo -e "当前版本: ${GREEN}${cur:-未安装}${NC}"
    echo "1) 稳定版 $stable"
    echo "2) 测试版 $beta"
    echo "3) 回滚"
    echo "0) 退出"
    read -r c

    case "$c" in
        1) install_version "$stable" "$rel" ;;
        2) install_version "$beta" "$rel" ;;
        3) rollback_version ;;
    esac
}

main() {
    check_dependencies
    detect_arch
    show_menu
}

main
