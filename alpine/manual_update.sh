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
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

MANUAL_FILE="/etc/sing-box/manual.conf"
DEFAULTS_FILE="/etc/sing-box/defaults.conf"
CONFIG_FILE="/etc/sing-box/config.json"

# ===== 当前模式 =====
MODE=$(grep '^MODE=' /etc/sing-box/mode.conf 2>/dev/null | cut -d'=' -f2 || echo "TProxy")

# ===== 输入函数 =====
prompt_user_input() {
    while true; do
        read -rp "请输入后端地址(不填使用默认值): " BACKEND_URL
        BACKEND_URL=${BACKEND_URL:-$(grep BACKEND_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)}
        if [ -z "$BACKEND_URL" ]; then
            echo -e "${RED}未设置默认后端地址，请先设置默认值！${NC}"
            continue
        fi
        echo -e "${CYAN}使用后端地址: $BACKEND_URL${NC}"
        break
    done

    while true; do
        read -rp "请输入订阅地址(不填使用默认值): " SUBSCRIPTION_URL
        SUBSCRIPTION_URL=${SUBSCRIPTION_URL:-$(grep SUBSCRIPTION_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)}
        if [ -z "$SUBSCRIPTION_URL" ]; then
            echo -e "${RED}未设置默认订阅地址，请先设置默认值！${NC}"
            continue
        fi
        echo -e "${CYAN}使用订阅地址: $SUBSCRIPTION_URL${NC}"
        break
    done

    while true; do
        read -rp "请输入配置文件地址(不填使用默认值): " TEMPLATE_URL
        if [ -z "$TEMPLATE_URL" ]; then
            case "$MODE" in
                TProxy) TEMPLATE_URL=$(grep TPROXY_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-) ;;
                TUN)    TEMPLATE_URL=$(grep TUN_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-) ;;
                *)      echo -e "${RED}未知模式: $MODE${NC}"; exit 1 ;;
            esac
        fi
        if [ -z "$TEMPLATE_URL" ]; then
            echo -e "${RED}未设置默认配置文件地址，请先设置默认值！${NC}"
            continue
        fi
        echo -e "${CYAN}使用配置文件地址: $TEMPLATE_URL${NC}"
        break
    done
}

# ===== 主流程 =====
read -rp "是否更换订阅地址？(y/n): " change_subscription
if [[ "$change_subscription" =~ ^[Yy]$ ]]; then
    while true; do
        prompt_user_input
        echo -e "${CYAN}你输入的配置信息如下:${NC}"
        echo "后端地址: $BACKEND_URL"
        echo "订阅地址: $SUBSCRIPTION_URL"
        echo "配置文件地址: $TEMPLATE_URL"

        read -rp "确认输入？(y/n): " confirm_choice
        if [[ "$confirm_choice" =~ ^[Yy]$ ]]; then
            # 更新手动配置
            cat > "$MANUAL_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TEMPLATE_URL=$TEMPLATE_URL
EOF
            echo -e "${GREEN}手动输入配置已更新${NC}"
            break
        else
            echo -e "${RED}请重新输入配置信息${NC}"
        fi
    done
else
    if [ ! -f "$MANUAL_FILE" ]; then
        echo -e "${RED}订阅地址为空，请先设置！${NC}"
        exit 1
    fi
    BACKEND_URL=$(grep BACKEND_URL "$MANUAL_FILE" 2>/dev/null | cut -d'=' -f2-)
    SUBSCRIPTION_URL=$(grep SUBSCRIPTION_URL "$MANUAL_FILE" 2>/dev/null | cut -d'=' -f2-)
    TEMPLATE_URL=$(grep TEMPLATE_URL "$MANUAL_FILE" 2>/dev/null | cut -d'=' -f2-)

    if [ -z "$BACKEND_URL" ] || [ -z "$SUBSCRIPTION_URL" ] || [ -z "$TEMPLATE_URL" ]; then
        echo -e "${RED}订阅地址为空，请先设置！${NC}"
        exit 1
    fi

    echo -e "${CYAN}当前配置如下:${NC}"
    echo "后端地址: $BACKEND_URL"
    echo "订阅地址: $SUBSCRIPTION_URL"
    echo "配置文件地址: $TEMPLATE_URL"
fi

# 构建完整 URL
FULL_URL="${BACKEND_URL}/config/${SUBSCRIPTION_URL}&file=${TEMPLATE_URL}"
echo -e "${CYAN}生成完整订阅链接: $FULL_URL${NC}"

# 备份旧配置
[ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_FILE.backup"

# 下载并验证配置
while true; do
    if curl -L --connect-timeout 10 --max-time 30 "$FULL_URL" -o "$CONFIG_FILE"; then
        echo -e "${GREEN}配置文件下载完成${NC}"
        if sing-box check -c "$CONFIG_FILE"; then
            echo -e "${GREEN}配置文件验证通过${NC}"
            break
        else
            echo -e "${RED}配置文件验证失败，恢复备份${NC}"
            [ -f "$CONFIG_FILE.backup" ] && cp "$CONFIG_FILE.backup" "$CONFIG_FILE"
            exit 1
        fi
    else
        echo -e "${RED}下载失败${NC}"
        read -rp "是否重试？(y/n): " retry_choice
        [[ "$retry_choice" =~ ^[Nn]$ ]] && { [ -f "$CONFIG_FILE.backup" ] && cp "$CONFIG_FILE.backup" "$CONFIG_FILE"; exit 1; }
    fi
done

# 重启 sing-box 并检查状态
/etc/init.d/sing-box start
if /etc/init.d/sing-box status | grep -q "running"; then
    echo -e "${GREEN}sing-box 启动成功${NC}"
else
    echo -e "${RED}sing-box 启动失败${NC}"
fi
