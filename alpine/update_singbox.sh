#!/bin/sh
# Alpine sing-box 更新脚本（curl / 多架构 / 自动回滚）

# =====================
# 配置区
# =====================
REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
BACKUP_BIN="$BIN_PATH.bak"
TEMP_DIR="/tmp/sing-box_update"
MAX_RETRY=3

# =====================
# 颜色定义
# =====================
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# =====================
# 临时文件清理
# =====================
trap 'rm -f /tmp/releases.json /tmp/sb_url; rm -rf "$TEMP_DIR"' EXIT

# =====================
# 依赖检查
# =====================
check_dependencies() {
    for cmd in jq curl tar find uname; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}错误：缺少必要依赖 $cmd，请运行 apk add $cmd 安装${NC}"
            exit 1
        fi
    done
}

# =====================
# 架构自动检测
# =====================
detect_arch() {
    case "$(uname -m)" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l|armv7*) ARCH="armv7" ;;
        armv6l|armv6*) ARCH="armv6" ;;
        mipsel*) ARCH="mipsel" ;;
        mips*) ARCH="mips" ;;
        *) echo -e "${RED}不支持的架构: $(uname -m)${NC}"; exit 1 ;;
    esac
    echo -e "${CYAN}检测到架构: $ARCH${NC}"
}

# =====================
# 安装指定版本（优化错误处理）
# =====================
install_version() {
    ver="$1"
    releases="$2"
    [ -z "$ver" ] && return 1

    candidates="
sing-box-$ver-linux-$ARCH-musl.tar.gz
sing-box-$ver-linux-$ARCH.tar.gz
"

    bin_url=""

    echo "$releases" | jq -r '.[] | .assets[] | "\(.name) \(.browser_download_url)"' |
    while read -r name url; do
        for expected in $candidates; do
            if [ "$name" = "$expected" ]; then
                bin_url="$url"
                echo "$bin_url" > /tmp/sb_url
                break 2
            fi
        done
    done

    [ -f /tmp/sb_url ] && bin_url=$(cat /tmp/sb_url)

    if [ -z "$bin_url" ]; then
        echo -e "${RED}未找到匹配的 release 资产${NC}"
        return 1
    fi

    mkdir -p "$TEMP_DIR"

    echo -e "${CYAN}下载 $bin_url${NC}"
    download_asset "$bin_url" "$TEMP_DIR/sing-box.tar.gz" || return 1

    echo -e "${CYAN}解压文件${NC}"
    if ! tar -xzf "$TEMP_DIR/sing-box.tar.gz" -C "$TEMP_DIR"; then
        echo -e "${RED}解压失败，请检查下载的文件是否完整${NC}"
        return 1
    fi

    bin_file=$(find "$TEMP_DIR" -type f -name sing-box 2>/dev/null | head -n1)
    [ ! -f "$bin_file" ] && return 1

    rc-service sing-box stop 2>/dev/null

    [ -f "$BIN_PATH" ] && mv "$BIN_PATH" "$BACKUP_BIN"
    mv "$bin_file" "$BIN_PATH"
    chmod 755 "$BIN_PATH"

    rc-update add sing-box default
    rc-service sing-box restart

    if "$BIN_PATH" version >/dev/null 2>&1; then
        echo -e "${GREEN}sing-box $ver 安装成功${NC}"
    else
        echo -e "${RED}新版本异常，正在回滚${NC}"
        rollback_version
    fi
}

# =====================
# 菜单（优化版本检测）
# =====================
show_menu() {
    cur=$("$BIN_PATH" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    rel=$(fetch_releases)

    stable=$(echo "$rel" | jq -r '[.[]|select(.prerelease==false)][0].tag_name' | sed 's/^v//')
    beta=$(echo "$rel" | jq -r '[.[]|select(.prerelease==true)][0].tag_name' | sed 's/^v//')

    echo -e "${CYAN}==== Sing-box 更新助手 ====${NC}"
    echo -e "当前版本: ${GREEN}${cur:-未安装}${NC}"
    echo "1) 稳定版 : $stable"
    echo "2) 测试版 : $beta"
    echo "3) 回退"
    echo "0) 退出"
    echo -n "请选择: "
    read -r c

    case "$c" in
        1) install_version "$stable" "$rel" ;;
        2) install_version "$beta" "$rel" ;;
        3) rollback_version ;;
        0) exit 0 ;;
        *) echo "无效输入" ;;
    esac
}
