#!/bin/bash
set -Eeuo pipefail

# ===== Alpine 系统检测 =====
if [ ! -f /etc/os-release ] || ! grep -qi '^ID=alpine' /etc/os-release; then
    echo -e "\033[0;31m[ERROR]\033[0m 本脚本仅支持 Alpine Linux"
    exit 1
fi

# ===== root 检查 =====
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m 此脚本需要 root 权限"
    exit 1
fi

# ===== 颜色 =====
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

MANUAL_FILE="/etc/sing-box/manual.conf"
DEFAULTS_FILE="/etc/sing-box/defaults.conf"

if [ ! -f "$DEFAULTS_FILE" ]; then
    echo -e "${RED}未找到默认配置文件 $DEFAULTS_FILE${NC}"
    exit 1
fi

MODE=$(grep -E '^MODE=' /etc/sing-box/mode.conf | sed 's/^MODE=//')

prompt_user_input() {
    read -rp "请输入后端地址(回车使用默认值可留空): " BACKEND_URL
    BACKEND_URL=${BACKEND_URL:-$(grep BACKEND_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)}
    echo -e "${CYAN}后端地址: $BACKEND_URL${NC}"

    read -rp "请输入订阅地址(回车使用默认值可留空): " SUBSCRIPTION_URL
    SUBSCRIPTION_URL=${SUBSCRIPTION_URL:-$(grep SUBSCRIPTION_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)}
    echo -e "${CYAN}订阅地址: $SUBSCRIPTION_URL${NC}"

    read -rp "请输入配置文件地址(回车使用默认值可留空): " TEMPLATE_URL
    if [ -z "$TEMPLATE_URL" ]; then
        case "$MODE" in
            TProxy) TEMPLATE_URL=$(grep TPROXY_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-) ;;
            TUN)    TEMPLATE_URL=$(grep TUN_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-) ;;
            *)      echo -e "${RED}未知模式: $MODE${NC}"; exit 1 ;;
        esac
    fi
    echo -e "${CYAN}配置文件地址: $TEMPLATE_URL${NC}"
}

while true; do
    prompt_user_input

    echo -e "${CYAN}你输入的配置信息如下:${NC}"
    echo "后端地址: $BACKEND_URL"
    echo "订阅地址: $SUBSCRIPTION_URL"
    echo "配置文件地址: $TEMPLATE_URL"

    read -rp "确认输入的配置信息？(y/n): " confirm_choice
    if [[ "$confirm_choice" =~ ^[Yy]$ ]]; then
        cat > "$MANUAL_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TEMPLATE_URL=$TEMPLATE_URL
EOF
        echo -e "${CYAN}手动输入配置已更新${NC}"

        # 构建完整配置 URL
        if [ -n "$BACKEND_URL" ] && [ -n "$SUBSCRIPTION_URL" ]; then
            FULL_URL="${BACKEND_URL}/config/${SUBSCRIPTION_URL}&file=${TEMPLATE_URL}"
        else
            FULL_URL="$TEMPLATE_URL"
        fi
        echo -e "${CYAN}生成完整订阅链接: $FULL_URL${NC}"

        # 下载并验证配置文件
        while true; do
            if curl -L --connect-timeout 10 --max-time 30 "$FULL_URL" -o /etc/sing-box/config.json; then
                echo -e "${CYAN}配置文件下载完成${NC}"
                if sing-box check -c /etc/sing-box/config.json; then
                    echo -e "${CYAN}配置文件验证通过${NC}"
                    break
                else
                    echo -e "${RED}配置文件验证失败${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}配置文件下载失败${NC}"
                read -rp "是否重试？(y/n): " retry_choice
                [[ "$retry_choice" =~ ^[Nn]$ ]] && exit 1
            fi
        done

        break
    else
        echo -e "${RED}请重新输入配置信息${NC}"
    fi
done
