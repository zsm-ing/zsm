#!/bin/sh
# Alpine sing-box 更新脚本 (Optimized)
# 功能：官方 API + 镜像加速 + 自动回滚 + 自动安装依赖

REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
BACKUP_BIN="$BIN_PATH.bak"
TEMP_DIR="/tmp/sing-box_update_$(date +%s)"
MAX_RETRY=3

# 设置 GitHub 镜像代理 (如果失效可更换，例如: https://fastgh.manduobur.com/)
PROXY_URL="https://mirror.ghproxy.com/"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# =====================
# 退出清理 (Trap)
# =====================
cleanup() {
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

# =====================
# 依赖检查与安装
# =====================
check_dependencies() {
    # 检查 root 权限
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
        exit 1
    fi

    local missing_deps=""
    for cmd in jq curl tar find uname; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps="$missing_deps $cmd"
        fi
    done

    if [ -n "$missing_deps" ]; then
        echo -e "${YELLOW}缺少依赖:$missing_deps，尝试自动安装...${NC}"
        if command -v apk >/dev/null 2>&1; then
            apk add --no-cache $missing_deps || { echo -e "${RED}安装依赖失败${NC}"; exit 1; }
        else
            echo -e "${RED}无法自动安装，请手动安装:$missing_deps${NC}"
            exit 1
        fi
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
        armv6l|armv6*) ARCH="armv6" ;;
        mipsel*) ARCH="mipsel" ;;
        mips*)   ARCH="mips" ;;
        *) echo -e "${RED}不支持的架构: $(uname -m)${NC}"; exit 1 ;;
    esac
    # Alpine 默认使用 musl libc
    echo -e "${CYAN}检测到系统架构: $ARCH (musl)${NC}"
}

# =====================
# curl 带重试
# =====================
fetch_with_retry() {
    url="$1"
    out="$2"
    i=0
    while [ $i -lt $MAX_RETRY ]; do
        curl -fsSL --connect-timeout 10 -H "User-Agent: sing-box-update" "$url" -o "$out" && return 0
        i=$((i+1))
        echo -e "${YELLOW}请求失败，重试 ($i/$MAX_RETRY)...${NC}"
        sleep 2
    done
    return 1
}

# =====================
# 获取 Releases
# =====================
fetch_releases() {
    echo -e "${CYAN}正在从 GitHub API 获取版本列表...${NC}"
    api="https://api.github.com/repos/$REPO/releases?per_page=10"
    
    if ! fetch_with_retry "$api" "$TEMP_DIR/releases.json"; then
        echo -e "${RED}获取版本列表失败，请检查网络或 GitHub API 限制${NC}"
        exit 1
    fi
}

# =====================
# 下载并安装
# =====================
install_version() {
    target_ver="$1" # 传入版本号 (不带 v)
    
    # 构造期望的文件名 (Alpine 需要 musl 版本)
    expected="sing-box-$target_ver-linux-$ARCH-musl.tar.gz"
    
    echo -e "${CYAN}目标版本: ${GREEN}$target_ver${NC}"
    echo -e "查找文件: $expected"

    # 使用 jq 精确查找对应 tag 的 assets 下载链接
    # 注意：这里我们遍历 JSON 寻找 tag_name 匹配的 release，然后找其中的 asset
    download_url=$(jq -r --arg tag "v$target_ver" --arg name "$expected" '
        .[] | select(.tag_name==$tag) | .assets[] | select(.name==$name) | .browser_download_url
    ' "$TEMP_DIR/releases.json" | head -n1)

    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        echo -e "${RED}未在版本 v$target_ver 中找到适用于 $ARCH-musl 的文件${NC}"
        return 1
    fi

    # 拼接代理地址
    final_url="${PROXY_URL}${download_url}"
    echo -e "${CYAN}开始下载: $final_url${NC}"

    mkdir -p "$TEMP_DIR/extract"
    if ! fetch_with_retry "$final_url" "$TEMP_DIR/sb.tgz"; then
        echo -e "${RED}下载失败${NC}"
        return 1
    fi

    echo -e "${CYAN}正在解压...${NC}"
    if ! tar -xzf "$TEMP_DIR/sb.tgz" -C "$TEMP_DIR/extract"; then
        echo -e "${RED}解压失败${NC}"
        return 1
    fi

    # 查找二进制文件 (解压后通常在子目录里)
    new_bin=$(find "$TEMP_DIR/extract" -name sing-box -type f | head -n1)
    if [ ! -f "$new_bin" ]; then
        echo -e "${RED}解压后未找到 sing-box 二进制文件${NC}"
        return 1
    fi

    # === 开始替换 ===
    echo -e "${CYAN}正在安装...${NC}"
    
    # 停止服务
    if [ -x /etc/init.d/sing-box ]; then
        /etc/init.d/sing-box stop >/dev/null 2>&1
    fi

    # 备份旧版本
    if [ -f "$BIN_PATH" ]; then
        cp "$BIN_PATH" "$BACKUP_BIN"
    fi

    # 覆盖文件
    cp -f "$new_bin" "$BIN_PATH"
    chmod 755 "$BIN_PATH"

    # 验证版本
    echo -e "${CYAN}验证新版本...${NC}"
    if "$BIN_PATH" version >/dev/null 2>&1; then
        installed_ver=$("$BIN_PATH" version 2>/dev/null | awk '{print $3}' | head -n1)
        echo -e "${GREEN}更新成功! 当前版本: $installed_ver${NC}"
        
        if [ -x /etc/init.d/sing-box ]; then
            echo "重启服务..."
            /etc/init.d/sing-box restart
        fi
    else
        echo -e "${RED}新版本验证失败，正在回滚...${NC}"
        rollback_version
    fi
}

# =====================
# 回滚
# =====================
rollback_version() {
    if [ -f "$BACKUP_BIN" ]; then
        cp -f "$BACKUP_BIN" "$BIN_PATH"
        chmod 755 "$BIN_PATH"
        echo -e "${GREEN}已回滚至旧版本${NC}"
        [ -x /etc/init.d/sing-box ] && /etc/init.d/sing-box restart
    else
        echo -e "${RED}无备份文件，无法回滚${NC}"
    fi
}

# =====================
# 菜单
# =====================
show_menu() {
    mkdir -p "$TEMP_DIR"
    
    if [ -f "$BIN_PATH" ]; then
        cur_ver=$("$BIN_PATH" version 2>/dev/null | awk '{print $3}' | head -n1)
    else
        cur_ver="未安装"
    fi

    fetch_releases

    # 提取最新的正式版和测试版 Tag
    stable_tag=$(jq -r '[.[] | select(.prerelease==false)] | .[0].tag_name' "$TEMP_DIR/releases.json")
    beta_tag=$(jq -r '[.[] | select(.prerelease==true)] | .[0].tag_name' "$TEMP_DIR/releases.json")
    
    # 去掉 v 前缀用于显示
    stable_ver=${stable_tag#v}
    beta_ver=${beta_tag#v}

    echo -e "\n${CYAN}==== Alpine Sing-box 更新助手 ====${NC}"
    echo -e "当前版本: ${GREEN}${cur_ver}${NC}"
    echo -e "架构: $ARCH (musl)"
    echo "--------------------------------"
    echo "1) 更新 稳定版 [${stable_ver:-无}]"
    if [ "$stable_ver" != "$beta_ver" ] && [ -n "$beta_ver" ]; then
        echo "2) 更新 测试版 [${beta_ver}]"
    else
        echo "2) 更新 测试版 [无新版]"
    fi
    echo "3) 回滚上一版本"
    echo "0) 退出"
    echo "--------------------------------"
    printf "请输入选项: "
    read -r c

    case "$c" in
        1) 
            [ -n "$stable_ver" ] && install_version "$stable_ver" || echo "无稳定版信息"
            ;;
        2) 
            [ -n "$beta_ver" ] && install_version "$beta_ver" || echo "无测试版信息"
            ;;
        3) rollback_version ;;
        0) exit 0 ;;
        *) echo "无效选项"; exit 1 ;;
    esac
}

main() {
    check_dependencies
    detect_arch
    show_menu
}

main
