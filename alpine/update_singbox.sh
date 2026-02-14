#!/bin/sh
# Alpine sing-box 更新脚本 (修复版)
# 功能：多镜像源选择 + 架构自动检测 + 自动回滚

REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
BACKUP_BIN="$BIN_PATH.bak"
TEMP_DIR="/tmp/sing-box_update_$(date +%s)"
MAX_RETRY=3

# 默认镜像 (初始为空，将在菜单中选择)
PROXY_URL=""

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# =====================
# 退出清理
# =====================
cleanup() {
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

# =====================
# 依赖检查
# =====================
check_dependencies() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 请使用 root 权限运行${NC}"
        exit 1
    fi
    local missing_deps=""
    for cmd in jq curl tar find uname; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps="$missing_deps $cmd"
        fi
    done
    if [ -n "$missing_deps" ]; then
        echo -e "${YELLOW}安装依赖:$missing_deps ...${NC}"
        apk add --no-cache $missing_deps || exit 1
    fi
}

# =====================
# 架构检测
# =====================
detect_arch() {
    case "$(uname -m)" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l|armv7*) ARCH="armv7" ;;
        *) echo -e "${RED}不支持的架构: $(uname -m)${NC}"; exit 1 ;;
    esac
}

# =====================
# 镜像源选择 (新增)
# =====================
select_mirror() {
    echo -e "${CYAN}请选择下载线路:${NC}"
    echo "1) [推荐] 官方直连 (适合日本/香港/海外VPS)"
    echo "2) [国内] ghproxy.net (通用镜像)"
    echo "3) [国内] fastgh.manduobur.com"
    echo "4) [国内] gh.llkk.cc"
    printf "请输入选项 [默认1]: "
    read -r m
    case "$m" in
        2) PROXY_URL="https://ghproxy.net/" ;;
        3) PROXY_URL="https://fastgh.manduobur.com/" ;;
        4) PROXY_URL="https://gh.llkk.cc/" ;;
        *) PROXY_URL="" ;; # 默认直连
    esac
    
    if [ -z "$PROXY_URL" ]; then
        echo -e "当前线路: ${GREEN}官方直连${NC}"
    else
        echo -e "当前线路: ${GREEN}${PROXY_URL}${NC}"
    fi
}

# =====================
# 网络请求封装
# =====================
fetch_url() {
    url="$1"
    out="$2"
    # 如果是 API 请求且没有设置代理，直接请求 GitHub API
    # 如果是文件下载，前面拼接 PROXY_URL
    
    i=0
    while [ $i -lt $MAX_RETRY ]; do
        curl -fsSL --connect-timeout 15 -H "User-Agent: sing-box-update" "$url" -o "$out" && return 0
        i=$((i+1))
        echo -e "${YELLOW}请求失败，重试 ($i/$MAX_RETRY)...${NC}"
        sleep 2
    done
    return 1
}

# =====================
# 获取版本
# =====================
fetch_releases() {
    echo -e "${CYAN}获取版本列表...${NC}"
    # API 始终直连，除非你要代理 API (通常 API 直连没问题，下载文件才慢)
    # 如果 API 也需要代理，可以改写这里，但大多数镜像只代理文件下载
    if ! fetch_url "https://api.github.com/repos/$REPO/releases?per_page=10" "$TEMP_DIR/releases.json"; then
        echo -e "${RED}获取版本列表失败，请检查网络${NC}"
        exit 1
    fi
}

# =====================
# 安装核心
# =====================
install_version() {
    target_ver="$1"
    expected="sing-box-$target_ver-linux-$ARCH-musl.tar.gz"
    
    echo -e "${CYAN}准备安装: ${GREEN}$target_ver${NC} ($ARCH-musl)"

    # 提取下载链接
    download_url=$(jq -r --arg tag "v$target_ver" --arg name "$expected" '
        .[] | select(.tag_name==$tag) | .assets[] | select(.name==$name) | .browser_download_url
    ' "$TEMP_DIR/releases.json" | head -n1)

    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        echo -e "${RED}未找到对应的 musl 版本文件${NC}"
        return 1
    fi

    # 拼接镜像地址
    final_url="${PROXY_URL}${download_url}"
    echo -e "${CYAN}下载地址: $final_url${NC}"

    mkdir -p "$TEMP_DIR/extract"
    if ! fetch_url "$final_url" "$TEMP_DIR/sb.tgz"; then
        echo -e "${RED}下载失败，请尝试更换线路${NC}"
        return 1
    fi

    echo -e "正在解压..."
    tar -xzf "$TEMP_DIR/sb.tgz" -C "$TEMP_DIR/extract" || { echo "解压失败"; return 1; }

    new_bin=$(find "$TEMP_DIR/extract" -name sing-box -type f | head -n1)
    
    # 停止服务
    [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box stop >/dev/null 2>&1

    # 备份与替换
    [ -f "$BIN_PATH" ] && cp "$BIN_PATH" "$BACKUP_BIN"
    cp -f "$new_bin" "$BIN_PATH"
    chmod 755 "$BIN_PATH"

    # 验证
    if "$BIN_PATH" version >/dev/null 2>&1; then
        echo -e "${GREEN}更新成功! $("$BIN_PATH" version | awk '{print $3}' | head -n1)${NC}"
        [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box restart
    else
        echo -e "${RED}验证失败，回滚中...${NC}"
        [ -f "$BACKUP_BIN" ] && cp "$BACKUP_BIN" "$BIN_PATH"
        [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box restart
    fi
}

# =====================
# 主菜单
# =====================
show_menu() {
    mkdir -p "$TEMP_DIR"
    check_dependencies
    detect_arch
    
    # 1. 先让用户选线路
    select_mirror
    
    # 2. 获取版本
    fetch_releases

    if [ -f "$BIN_PATH" ]; then
        cur_ver=$("$BIN_PATH" version 2>/dev/null | awk '{print $3}' | head -n1)
    else
        cur_ver="未安装"
    fi

    stable_ver=$(jq -r '[.[] | select(.prerelease==false)] | .[0].tag_name' "$TEMP_DIR/releases.json" | sed 's/^v//')
    beta_ver=$(jq -r '[.[] | select(.prerelease==true)] | .[0].tag_name' "$TEMP_DIR/releases.json" | sed 's/^v//')

    echo -e "\n${CYAN}==== Alpine Sing-box 更新 (Fix) ====${NC}"
    echo -e "当前版本: ${GREEN}${cur_ver}${NC}"
    echo "--------------------------------"
    echo "1) 更新 稳定版 [${stable_ver}]"
    echo "2) 更新 测试版 [${beta_ver}]"
    echo "3) 回滚上一版本"
    echo "0) 退出"
    echo "--------------------------------"
    printf "请输入选项: "
    read -r c

    case "$c" in
        1) [ -n "$stable_ver" ] && install_version "$stable_ver" ;;
        2) [ -n "$beta_ver" ] && install_version "$beta_ver" ;;
        3) 
           if [ -f "$BACKUP_BIN" ]; then
               cp "$BACKUP_BIN" "$BIN_PATH"
               echo "已回滚"
               /etc/init.d/sing-box restart
           else
               echo "无备份"
           fi
           ;;
        0) exit 0 ;;
        *) echo "无效选项";;
    esac
}

show_menu
