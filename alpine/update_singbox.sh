#!/bin/sh
# Alpine sing-box 更新脚本（HTML 解析 / 极限抗封锁版）

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
    for cmd in curl tar find uname grep sed; do
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
        curl -fsSL --connect-timeout 10 --max-time 30 -o "$out" "$url" && return 0
        i=$((i+1))
        sleep 2
    done
    return 1
}

get_versions() {
    page="$(fetch "$RELEASE_PAGE" /dev/stdout || true)"

    stable=$(echo "$page" \
        | grep -oE '/tag/v[0-9]+\.[0-9]+\.[0-9]+"' \
        | head -n1 \
        | sed 's#.*/v##;s/"//')

    beta=$(echo "$page" \
        | grep -oE '/tag/v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+"' \
        | head -n1 \
        | sed 's#.*/v##;s/"//')

    echo "$stable|$beta"
}

install_version() {
    ver="$1"
    [ -z "$ver" ] && {
        echo -e "${RED}版本号为空，跳过${NC}"
        return 1
    }

    url="https://github.com/$REPO/releases/download/v$ver/sing-box-$ver-linux-$ARCH-musl.tar.gz"

    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    echo -e "${CYAN}下载 v$ver${NC}"
    fetch "$url" "$TEMP_DIR/sb.tar.gz" || {
        echo -e "${RED}下载失败${NC}"
        return 1
    }

    tar -xzf "$TEMP_DIR/sb.tar.gz" -C "$TEMP_DIR" || return 1

    bin_file=$(find "$TEMP_DIR" -type f -name sing-box -perm -111 | head -n1)
    [ ! -f "$bin_file" ] && return 1

    rc-service sing-box stop 2>/dev/null
    [ -f "$BIN_PATH" ] && mv "$BIN_PATH" "$BACKUP_BIN"

    mv "$bin_file" "$BIN_PATH"
    chmod 755 "$BIN_PATH"

    rc-update show | grep -q sing-box || rc-update add sing-box default
    rc-service sing-box restart

    rm -rf "$TEMP_DIR"

    "$BIN_PATH" version >/dev/null 2>&1 \
        && echo -e "${GREEN}sing-box $ver 安装成功${NC}" \
        || rollback_version
}

rollback_version() {
    [ -f "$BACKUP_BIN" ] || {
        echo -e "${RED}无备份可回滚${NC}"
        return
    }
    rc-service sing-box stop 2>/dev/null
    mv "$BACKUP_BIN" "$BIN_PATH"
    chmod 755 "$BIN_PATH"
    rc-service sing-box restart
    echo -e "${GREEN}已回滚${NC}"
}

show_menu() {
    cur=$("$BIN_PATH" version 2>/dev/null | awk '/version/ {print $3}')
    vers="$(get_versions)"

    stable="${vers%%|*}"
    beta="${vers##*|}"

    echo -e "${CYAN}==== Sing-box 更新助手 ====${NC}"
    echo -e "当前版本: ${GREEN}${cur:-未安装}${NC}"
    echo "1) 稳定版 : ${stable:-无}"
    echo "2) 测试版 : ${beta:-无}"
    echo "3) 回退"
    echo "0) 退出"
    printf "请选择: "
    read -r c

    case "$c" in
        1) install_version "$stable" ;;
        2) install_version "$beta" ;;
        3) rollback_version ;;
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
