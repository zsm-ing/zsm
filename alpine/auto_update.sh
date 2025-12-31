#!/bin/bash
set -Eeuo pipefail

# ===== Alpine Linux 检测 =====
if [ ! -f /etc/os-release ] || ! grep -qi '^ID=alpine' /etc/os-release; then
    echo -e "\033[0;31m[ERROR]\033[0m 本脚本仅支持 Alpine Linux"
    exit 1
fi

# ===== 颜色 =====
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# ===== 依赖检查 =====
for pkg in bash curl cronie; do
    command -v "$pkg" >/dev/null 2>&1 || apk add --no-cache "$pkg"
done

# ===== 手动输入配置文件 =====
MANUAL_FILE="/etc/sing-box/manual.conf"

# ===== 创建定时更新脚本 =====
cat > /etc/sing-box/update-singbox.sh <<'EOF'
#!/bin/bash
set -Eeuo pipefail

echo "[INFO] 正在更新订阅地址..."

bash /etc/sing-box/scripts/set_defaults.sh 5

# 读取手动输入的配置参数
BACKEND_URL=$(grep '^BACKEND_URL=' /etc/sing-box/manual.conf | cut -d'=' -f2-)
SUBSCRIPTION_URL=$(grep '^SUBSCRIPTION_URL=' /etc/sing-box/manual.conf | cut -d'=' -f2-)
TEMPLATE_URL=$(grep '^TEMPLATE_URL=' /etc/sing-box/manual.conf | cut -d'=' -f2-)

# 构建完整 URL
FULL_URL="${BACKEND_URL}/config/${SUBSCRIPTION_URL}&file=${TEMPLATE_URL}"

# 备份配置
[ -f /etc/sing-box/config.json ] && \
cp /etc/sing-box/config.json /etc/sing-box/config.json.backup

# 下载新配置
if curl -fsSL --connect-timeout 10 --max-time 30 "$FULL_URL" -o /etc/sing-box/config.json; then
    if ! sing-box check -c /etc/sing-box/config.json; then
        echo "[ERROR] 新配置校验失败，回滚"
        cp /etc/sing-box/config.json.backup /etc/sing-box/config.json
    fi
else
    echo "[ERROR] 下载失败，回滚配置"
    cp /etc/sing-box/config.json.backup /etc/sing-box/config.json
fi

# 重启 sing-box（Alpine / OpenRC）
rc-service sing-box restart || true
EOF

chmod +x /etc/sing-box/update-singbox.sh

# ===== 主菜单 =====
while true; do
    echo -e "${CYAN}请选择操作:${NC}"
    echo "1. 设置自动更新间隔"
    echo "2. 取消自动更新"
    read -rp "请输入选项 (1或2, 默认为1): " menu_choice
    menu_choice=${menu_choice:-1}

    if [[ "$menu_choice" == "1" ]]; then
        while true; do
            read -rp "请输入更新间隔小时数 (1-23, 默认12): " interval_choice
            interval_choice=${interval_choice:-12}

            if [[ "$interval_choice" =~ ^([1-9]|1[0-9]|2[0-3])$ ]]; then
                break
            else
                echo -e "${RED}输入无效，请输入 1-23${NC}"
            fi
        done

        # 检查是否已有任务
        if crontab -l 2>/dev/null | grep -q '/etc/sing-box/update-singbox.sh'; then
            echo -e "${RED}检测到已有自动更新任务${NC}"
            read -rp "是否重新设置？(y/n): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "${CYAN}保持原任务，退出${NC}"
                exit 0
            fi
            crontab -l | grep -v '/etc/sing-box/update-singbox.sh' | crontab -
        fi

        # 写入 cron
        (crontab -l 2>/dev/null; echo "0 */$interval_choice * * * /etc/sing-box/update-singbox.sh") | crontab -

        # 启动 cron（Alpine）
        rc-service crond restart || rc-service crond start

        echo -e "${CYAN}已设置：每 $interval_choice 小时自动更新${NC}"
        break

    elif [[ "$menu_choice" == "2" ]]; then
        if crontab -l 2>/dev/null | grep -q '/etc/sing-box/update-singbox.sh'; then
            crontab -l | grep -v '/etc/sing-box/update-singbox.sh' | crontab -
            rc-service crond restart || true
            echo -e "${CYAN}自动更新任务已取消${NC}"
        else
            echo -e "${CYAN}未发现自动更新任务${NC}"
        fi
        break

    else
        echo -e "${RED}无效选项，请输入 1 或 2${NC}"
    fi
done
