#!/bin/sh
# OpenWrt sing-box 更新脚本

# =====================
# 配置区
# =====================
REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
BACKUP_BIN="$BIN_PATH.bak"
TEMP_DIR="/tmp/sing-box_update"
MAX_RETRY=3
ARCH="amd64"
OS="linux"

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
    for cmd in jq uclient-fetch tar find; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}错误：缺少必要依赖 $cmd${NC}"
            exit 1
        fi
    done
}

# =====================
# 带重试的 fetch
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
# 获取 releases（自动镜像）
# =====================
fetch_releases() {
    base="https://api.github.com/repos/$REPO/releases?per_page=5"
    data=$(fetch_with_retry "$base" /tmp/releases.json && cat /tmp/releases.json)
    if [ -z "$data" ]; then
        echo -e "${CYAN}API 直连失败，尝试镜像...${NC}"
        mirror="https://ghproxy.com/$base"
        data=$(fetch_with_retry "$mirror" /tmp/releases.json && cat /tmp/releases.json)
    fi
    echo "$data"
}

# =====================
# 安装指定版本（二进制替换）
# =====================
install_version() {
    ver="$1"
    releases="$2"

    [ -z "$ver" ] && { echo -e "${RED}版本号为空${NC}"; return 1; }

    echo -e "${CYAN}固定架构: $ARCH${NC}"

    # 遍历 assets 查找匹配的 linux-amd64.tar.gz 文件（严格匹配，不包含 -glibc）
    bin_url=""
    mapfile -t assets < <(echo "$releases" | jq -r '.[] | .assets[] | "\(.name) \(.browser_download_url)"')

    for item in "${assets[@]}"; do
        name=$(echo "$item" | awk '{print $1}')
        url=$(echo "$item" | awk '{print $2}')
        if echo "$name" | grep -q "$ver" && echo "$name" | grep -q "$OS-$ARCH" && echo "$name" | grep -q 'linux-amd64\.tar\.gz$'; then
            bin_url="$url"
            break
        fi
    done

    if [ -z "$bin_url" ]; then
        echo -e "${RED}未找到 linux-$ARCH 的 tar.gz 文件${NC}"
        return 1
    fi

    mkdir -p "$TEMP_DIR"

    echo -e "${CYAN}下载 $bin_url ...${NC}"
    fetch_with_retry "$bin_url" "$TEMP_DIR/sing-box.tar.gz" || { echo -e "${RED}下载失败${NC}"; return 1; }

    echo -e "${CYAN}解压 tar.gz ...${NC}"
    tar -xzf "$TEMP_DIR/sing-box.tar.gz" -C "$TEMP_DIR" || { echo -e "${RED}解压失败${NC}"; return 1; }

    # 查找解压后的 sing-box 文件（兼容 OpenWrt BusyBox find）
    bin_file=$(find "$TEMP_DIR" -type f -name 'sing-box' -perm +111 2>/dev/null | head -n1)
    [ -z "$bin_file" ] && bin_file=$(find "$TEMP_DIR" -type f -name 'sing-box' 2>/dev/null | head -n1)
    [ ! -f "$bin_file" ] && { echo -e "${RED}未找到解压后的二进制文件${NC}"; return 1; }

    # 停止服务
    [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box stop 2>/dev/null

    # 备份旧版本
    [ -f "$BIN_PATH" ] && mv "$BIN_PATH" "$BACKUP_BIN"

    # 替换二进制文件并设置 755 权限
    mv "$bin_file" "$BIN_PATH"
    chmod 755 "$BIN_PATH"

    # 启动服务
    if [ -x /etc/init.d/sing-box ]; then
        /etc/init.d/sing-box enable
        /etc/init.d/sing-box restart
    else
        echo -e "${RED}警告：未找到 /etc/init.d/sing-box，无法自启动${NC}"
    fi

    rm -rf "$TEMP_DIR"

    if $BIN_PATH version >/dev/null 2>&1; then
        echo -e "${GREEN}sing-box 安装成功并可执行${NC}"
    else
        echo -e "${RED}sing-box 启动失败，请检查配置${NC}"
    fi
}

# =====================
# 回退使用备份二进制
# =====================
rollback_version() {
    if [ -f "$BACKUP_BIN" ]; then
        echo -e "${CYAN}回退到备份二进制${NC}"
        [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box stop 2>/dev/null
        mv "$BACKUP_BIN" "$BIN_PATH"
        chmod 755 "$BIN_PATH"
        [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box restart

        if $BIN_PATH version >/dev/null 2>&1; then
            echo -e "${GREEN}sing-box 回退成功${NC}"
        else
            echo -e "${RED}回退后的 sing-box 无法启动${NC}"
        fi
    else
        echo -e "${RED}未找到备份二进制，无法回退${NC}"
    fi
}

# =====================
# 菜单
# =====================
show_menu() {
    clear
    cur=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
    rel=$(fetch_releases)
    [ -z "$rel" ] && { echo "${RED}无法获取 releases${NC}"; exit 1; }

    stable=$(echo "$rel" | jq -r '[.[]|select(.prerelease==false)][0].tag_name' | sed 's/^v//')
    beta=$(echo "$rel" | jq -r '[.[]|select(.prerelease==true)][0].tag_name' | sed 's/^v//')

    echo -e "${CYAN}==== Sing-box 更新助手 ====${NC}"
    echo -e "[当前版本] ${GREEN}${cur:-未安装}${NC}"
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
        *) echo "无效输入"; sleep 2; show_menu ;;
    esac
}

# =====================
# 主入口
# =====================
main() {
    check_dependencies
    show_menu
}

main
