#!/bin/bash
# ================================
# 多系统安装引导脚本 (Debian/Ubuntu/Armbian/OpenWRT)
# ================================

# 脚本下载URL
DEBIAN_MAIN_SCRIPT_URL="https://gh-proxy.com/https://raw.githubusercontent.com/qljsyph/sbshell/refs/heads/main/debian/menu.sh"
OPENWRT_MAIN_SCRIPT_URL="https://gh-proxy.com/https://raw.githubusercontent.com/zming66/zsm/refs/heads/main/openwrt/menu.sh"

# 脚本存放目录
SCRIPT_DIR="/etc/sing-box/scripts"

# ================================
# 颜色定义
# ================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ================================
# 系统检测
# ================================
OS=""
if grep -qi 'debian\|ubuntu\|armbian' /etc/os-release; then
    OS="debian"
    MAIN_SCRIPT_URL="$DEBIAN_MAIN_SCRIPT_URL"
    DEPENDENCIES=("wget" "nftables")
elif grep -qi 'openwrt' /etc/os-release; then
    OS="openwrt"
    MAIN_SCRIPT_URL="$OPENWRT_MAIN_SCRIPT_URL"
    DEPENDENCIES=("nftables")
elif grep -qi 'alpine' /etc/os-release; then
    OS="alpine"
    MAIN_SCRIPT_URL="$ALPINE_MAIN_SCRIPT_URL"
    DEPENDENCIES=("wget" "nftables")
else
    echo -e "${RED}当前系统不支持运行此脚本。${NC}"
    exit 1
fi

echo -e "${GREEN}检测到系统: $OS${NC}"

# ================================
# root/sudo 检查
# ================================
USE_SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &> /dev/null; then
        USE_SUDO="sudo"
    else
        echo -e "${RED}当前用户不是 root 且未安装 sudo，无法继续执行。${NC}"
        exit 1
    fi
fi

# ================================
# 安装依赖函数
# ================================
install_dep() {
    local dep=$1
    local check_cmd=$2

    if ! $check_cmd &> /dev/null; then
        echo -e "${RED}$dep 未安装${NC}"
        read -rp "是否安装 $dep? (y/n): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            case "$OS" in
                debian)
                    $USE_SUDO apt-get update
                    $USE_SUDO apt-get install -y "$dep"
                    ;;
                openwrt)
                    opkg update
                    opkg install "$dep"
                    ;;
                alpine)
                    $USE_SUDO apk update
                    $USE_SUDO apk add "$dep"
                    ;;
            esac
            # 再次检查
            if ! $check_cmd &> /dev/null; then
                echo -e "${RED}安装 $dep 失败，请手动安装。${NC}"
                exit 1
            fi
            echo -e "${GREEN}$dep 安装成功${NC}"
        else
            echo -e "${RED}未安装 $dep，脚本无法继续。${NC}"
            exit 1
        fi
    fi
}

# ================================
# 检查依赖
# ================================
for DEP in "${DEPENDENCIES[@]}"; do
    if [ "$DEP" == "nftables" ]; then
        install_dep "$DEP" "nft --version"
    else
        install_dep "$DEP" "$DEP --version"
    fi
done

# ================================
# 创建脚本目录
# ================================
if [ "$OS" = "openwrt" ]; then
    mkdir -p "$SCRIPT_DIR"
else
    $USE_SUDO mkdir -p "$SCRIPT_DIR"
    $USE_SUDO chown "$(whoami)":"$(whoami)" "$SCRIPT_DIR"
fi

# ================================
# 下载主脚本
# ================================
echo -e "${GREEN}正在下载主脚本...${NC}"
if command -v curl &> /dev/null; then
    curl -fsSL "$MAIN_SCRIPT_URL" -o "$SCRIPT_DIR/menu.sh"
elif command -v wget &> /dev/null; then
    wget -q -O "$SCRIPT_DIR/menu.sh" "$MAIN_SCRIPT_URL"
else
    echo -e "${RED}未安装 curl 或 wget，无法下载主脚本${NC}"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/menu.sh" ]; then
    echo -e "${RED}下载主脚本失败，请检查网络或代理${NC}"
    exit 1
fi

chmod +x "$SCRIPT_DIR/menu.sh"
echo -e "${GREEN}下载完成，开始执行主脚本...${NC}"
bash "$SCRIPT_DIR/menu.sh"
