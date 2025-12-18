#!/bin/sh
# OpenWrt sing-box 更新脚本（BusyBox / 多架构 / 自动回滚）

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
# 依赖检查
# =====================
check_dependencies() {
    for cmd in jq uclient-fetch tar find uname; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}错误：缺少必要依赖 $cmd${NC}"
            exit 1
        fi
    done
}

# =====================
# 架构自动检测
# =====================
detect_arch() {
    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l|armv7*)
            ARCH="armv7"
            ;;
        armv6l|armv6*)
            ARCH="armv6"
            ;;
        mipsel*)
            ARCH="mipsel"
            ;;
        mips*)
            ARCH="mips"
            ;;
        *)
            echo -e "${RED}不支持的架构: $(uname -m)${NC}"
            exit 1
            ;;
    esac
    echo -e "${CYAN}检测到架构: $ARCH${NC}"
}

# =====================
# 带重试的下载
# =====================
fetch_with_retry() {
    url="$1"
    output="$2"
    i=0
    while [ $i -lt $MAX_RETRY ]; do
        uclient-fetch -qO "$output" "$url" && return 0
        i=$((i+1))
        sleep 2
    done
    return 1
}

# =====================
# 下载 release 资产（支持镜像）
# =====================
download_asset() {
    url="$1"
    out="$2"

    fetch_with_retry "$url" "$out" && return 0

    echo -e "${CYAN}直连失败，尝试 ghproxy...${NC}"
    fetch_with_retry "https://ghproxy.com/$url" "$out"
}

# =====================
# 获取 releases
# =====================
fetch_releases() {
    api="https://api.github.com/repos/$REPO/releases?per_page=5"
    if fetch_with_retry "$api" /tmp/releases.json; then
        cat /tmp/releases.json
        return
    fi
    echo -e "${RED}获取 releases 失败${NC}"
    exit 1
}

# =====================
# 安装指定版本
# =====================
install_version() {
    ver="$1"
    releases="$2"

    [ -z "$ver" ] && return 1

    expected="sing-box-$ver-linux-$ARCH-musl.tar.gz"
    bin_url=""

    echo "$releases" | jq -r '.[] | .assets[] | "\(.name) \(.browser_download_url)"' |
    while read -r name url; do
        [ "$name" = "$expected" ] || continue
        bin_url="$url"
        echo "$bin_url" > /tmp/sb_url
        break
    done

    [ -f /tmp/sb_url ] && bin_url=$(cat /tmp/sb_url) && rm -f /tmp/sb_url

    if [ -z "$bin_url" ]; then
        echo -e "${RED}未找到 $expected${NC}"
        return 1
    fi

    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    echo -e "${CYAN}下载 $expected${NC}"
    download_asset "$bin_url" "$TEMP_DIR/sing-box.tar.gz" || return 1

    echo -e "${CYAN}解压文件${NC}"
    tar -xzf "$TEMP_DIR/sing-box.tar.gz" -C "$TEMP_DIR" || return 1

    bin_file=$(find "$TEMP_DIR" -type f -name sing-box 2>/dev/null | head -n1)
    [ ! -f "$bin_file" ] && return 1

    [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box stop 2>/dev/null

    [ -f "$BIN_PATH" ] && mv "$BIN_PATH" "$BACKUP_BIN"
    mv "$bin_file" "$BIN_PATH"
    chmod 755 "$BIN_PATH"

    if [ -x /etc/init.d/sing-box ]; then
        /etc/init.d/sing-box enable
        /etc/init.d/sing-box restart
    fi

    rm -rf "$TEMP_DIR"

    if "$BIN_PATH" version >/dev/null 2>&1; then
        echo -e "${GREEN}sing-box $ver 安装成功${NC}"
    else
        echo -e "${RED}新版本异常，正在回滚${NC}"
        rollback_version
    fi
}

# =====================
# 回滚
# =====================
rollback_version() {
    if [ -f "$BACKUP_BIN" ]; then
        [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box stop 2>/dev/null
        mv "$BACKUP_BIN" "$BIN_PATH"
        chmod 755 "$BIN_PATH"
        [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box restart
        echo -e "${GREEN}已回滚到旧版本${NC}"
    else
        echo -e "${RED}无备份可回滚${NC}"
    fi
}

# =====================
# 菜单
# =====================
show_menu() {
    cur=$("$BIN_PATH" version 2>/dev/null | awk '/version/ {print $3}')

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

# =====================
# 主入口
# =====================
main() {
    check_dependencies
    detect_arch
    show_menu
}

main
