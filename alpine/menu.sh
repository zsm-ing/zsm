#!/bin/bash

#################################################
# 描述: Alpine 官方 sing-box 全自动脚本
# 版本: 2.0.0
#################################################

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 脚本下载目录和初始化标志文件
SCRIPT_DIR="/etc/sing-box/scripts"
INITIALIZED_FILE="$SCRIPT_DIR/.initialized"

mkdir -p "$SCRIPT_DIR"
if grep -qi 'alpine' /etc/os-release; then
    chown root:root "$SCRIPT_DIR"
fi

# 脚本的URL基础路径
BASE_URL="https://raw.githubusercontent.com/zsm-ing/zsm/refs/heads/main/alpine"

# 脚本列表
SCRIPTS=(
    "check_environment.sh"     # 检查系统环境
    "install_singbox.sh"       # 安装 Sing-box
    "manual_input.sh"          # 手动输入配置
    "manual_update.sh"         # 手动更新配置
    "auto_update.sh"           # 自动更新配置
    "configure_tproxy.sh"      # 配置 TProxy 模式
    "configure_tun.sh"         # 配置 TUN 模式
    "start_singbox.sh"         # 手动启动 Sing-box
    "stop_singbox.sh"          # 手动停止 Sing-box
    "clean_nft.sh"             # 清理 nftables 规则
    "set_defaults.sh"          # 设置默认配置
    "commands.sh"              # 常用命令
    "network.sh"               # 网络设置
    "switch_mode.sh"           # 切换代理模式
    "manage_autostart.sh"      # 设置自启动
    "check_config.sh"          # 检查配置文件
    "update_singbox.sh"        # 更新 sing-box
    "update_scripts.sh"        # 更新脚本
    "update_ui.sh"             # 控制面板安装/更新/检查
    "menu.sh"                  # 主菜单
)

# 下载并设置单个脚本，带重试和日志记录逻辑
download_script() {
    local SCRIPT="$1"
    local RETRIES=5
    local RETRY_DELAY=5

    for ((i=1; i<=RETRIES; i++)); do
        if curl -s -o "$SCRIPT_DIR/$SCRIPT" "$BASE_URL/$SCRIPT"; then
            chmod +x "$SCRIPT_DIR/$SCRIPT"
            return 0
        else
            echo -e "${YELLOW}下载 $SCRIPT 失败，重试 $i/${RETRIES}...${NC}"
            sleep "$RETRY_DELAY"
        fi
    done

    echo -e "${RED}下载 $SCRIPT 失败，请检查网络连接。${NC}"
    return 1
}

# 并行下载脚本
parallel_download_scripts() {
    local pids=()
    for SCRIPT in "${SCRIPTS[@]}"; do
        download_script "$SCRIPT" &
        pids+=("$!")
    done

    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # 检查是否有缺失脚本
    for SCRIPT in "${SCRIPTS[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$SCRIPT" ]; then
            echo -e "${RED}缺失 $SCRIPT，尝试重新下载...${NC}"
            download_script "$SCRIPT"
        fi
    done
}

# 初始化操作
initialize() {
    if ls "$SCRIPT_DIR"/*.sh 1> /dev/null 2>&1; then
        find "$SCRIPT_DIR" -type f -name "*.sh" ! -name "menu.sh" -exec rm -f {} \;
        rm -f "$INITIALIZED_FILE"
    fi

    parallel_download_scripts
    auto_setup
    touch "$INITIALIZED_FILE"
}

# 自动引导设置
auto_setup() {
    rc-service sing-box stop 2>/dev/null || true
    mkdir -p /etc/sing-box/
    [ -f /etc/sing-box/mode.conf ] || touch /etc/sing-box/mode.conf
    chmod 644 /etc/sing-box/mode.conf

    bash "$SCRIPT_DIR/check_environment.sh"

    if ! command -v sing-box &> /dev/null; then
        apk update && apk add sing-box curl bash jq || bash "$SCRIPT_DIR/check_update.sh"
    fi

    bash "$SCRIPT_DIR/switch_mode.sh"
    bash "$SCRIPT_DIR/manual_input.sh"
    rc-service sing-box start
}

# 检查是否需要初始化
if [ ! -f "$INITIALIZED_FILE" ]; then
    echo -e "${CYAN}回车进入初始化引导设置,输入skip跳过引导${NC}"
    read -r init_choice
    if [[ "$init_choice" =~ ^[Ss]kip$ ]]; then
        echo -e "${CYAN}跳过初始化引导，直接进入菜单...${NC}"
    else
        initialize
    fi
fi

# 添加别名
[ -f ~/.bashrc ] || touch ~/.bashrc
if ! grep -q "alias sb=" ~/.bashrc; then
    echo "alias sb='bash $SCRIPT_DIR/menu.sh menu'" >> ~/.bashrc
fi

# 创建快捷脚本
if [ ! -f /usr/bin/sb ]; then
    echo -e '#!/bin/bash\nbash /etc/sing-box/scripts/menu.sh menu' | tee /usr/bin/sb >/dev/null
    chmod +x /usr/bin/sb
fi

show_singbox_status() {
    echo "=== SingBox 状态 ==="
    PID=$(pgrep -f sing-box)
    if [ -n "$PID" ]; then
        echo "[OK] SingBox 正在运行"

        # 获取启动时间并计算运行时长（兼容 BusyBox）
        START_TIME=$(ps -p $PID -o lstart=)
        if [ -n "$START_TIME" ]; then
            START_TS=$(date -d "$START_TIME" +%s 2>/dev/null || date -j -f "%a %b %d %T %Y" "$START_TIME" +%s 2>/dev/null)
            NOW_TS=$(date +%s)
            if [ -n "$START_TS" ] && [ -n "$NOW_TS" ]; then
                ELAPSED=$((NOW_TS - START_TS))
                DAYS=$((ELAPSED / 86400))
                HOURS=$(( (ELAPSED % 86400) / 3600 ))
                MINUTES=$(( (ELAPSED % 3600) / 60 ))
                SECONDS=$((ELAPSED % 60))
                echo "运行时间: ${DAYS}天 ${HOURS}小时 ${MINUTES}分 ${SECONDS}秒"
            fi
        fi
    else
        echo "[WARN] SingBox 未运行"
    fi

    # 代理模式（兼容 BusyBox）
    MODE="未知"
    if [ -r /etc/sing-box/mode.conf ]; then
        MODE=$(grep '^MODE=' /etc/sing-box/mode.conf | cut -d= -f2)
        [ -z "$MODE" ] && MODE="未知"
    fi
    echo "代理模式: $MODE"

    echo
    echo "=== 系统资源 ==="
    load=$(uptime | awk -F'load average:' '{print $2}' | sed 's/ //g')
    echo "CPU 负载: $load"

    mem_used=$(free -h | awk '/Mem:/ {print $3}')
    mem_total=$(free -h | awk '/Mem:/ {print $2}')
    echo "内存使用: $mem_used / $mem_total"

    disk_used=$(df -h / | awk 'NR==2 {print $3}')
    disk_total=$(df -h / | awk 'NR==2 {print $2}')
    echo "磁盘使用: $disk_used / $disk_total"

    if [ -d /sys/class/net/eth0/statistics ]; then
        RX=$(cat /sys/class/net/eth0/statistics/rx_bytes)
        TX=$(cat /sys/class/net/eth0/statistics/tx_bytes)

        bytes_to_human() {
            BYTES=$1
            if [ "$BYTES" -ge 1073741824 ]; then
                VAL=$(awk "BEGIN {printf \"%.2f\", $BYTES/1024/1024/1024}")
                echo "${VAL} GB"
            else
                VAL=$(awk "BEGIN {printf \"%.2f\", $BYTES/1024/1024}")
                echo "${VAL} MB"
            fi
        }

        RX_H=$(bytes_to_human $RX)
        TX_H=$(bytes_to_human $TX)
        echo "eth0 网络流量: 接收 $RX_H, 发送 $TX_H"
    fi
}

show_menu() {
    echo -e "${CYAN}=========== Sbshell 管理菜单 ===========${NC}"
    echo -e "${GREEN}1. Tproxy/Tun模式切换${NC}"
    echo -e "${GREEN}2. 手动更新配置文件${NC}"
    echo -e "${GREEN}3. 自动更新配置文件${NC}"
    echo -e "${GREEN}4. 手动启动 sing-box${NC}"
    echo -e "${GREEN}5. 手动停止 sing-box${NC}"
    echo -e "${GREEN}6. 设置参数${NC}"
    echo -e "${GREEN}7. 设置自启动${NC}"
    echo -e "${GREEN}8. 常用命令${NC}"
    echo -e "${GREEN}9. 更新脚本${NC}"
    echo -e "${GREEN}10. 更新面板${NC}"
    echo -e "${GREEN}11. 更新sing-box${NC}"
    echo -e "${GREEN}12. 网络设置${NC}"
    echo -e "${GREEN}0. 退出${NC}"
    echo -e "${CYAN}=======================================${NC}"
}
handle_choice() {
    read -rp "请选择操作: " choice
    case $choice in
        1) bash "$SCRIPT_DIR/switch_mode.sh"; bash "$SCRIPT_DIR/manual_input.sh"; rc-service sing-box restart ;;
        2) bash "$SCRIPT_DIR/manual_update.sh" ;;
        3) bash "$SCRIPT_DIR/auto_update.sh" ;;
        4) bash "$SCRIPT_DIR/start_singbox.sh" ;;
        5) bash "$SCRIPT_DIR/stop_singbox.sh" ;;
        6) bash "$SCRIPT_DIR/set_defaults.sh" ;;
        7) bash "$SCRIPT_DIR/manage_autostart.sh" ;;
        8) bash "$SCRIPT_DIR/commands.sh" ;;
        9) bash "$SCRIPT_DIR/update_scripts.sh" ;;
        10) bash "$SCRIPT_DIR/update_ui.sh" ;;
        11) bash "$SCRIPT_DIR/update_singbox.sh" ;;
        12) bash "$SCRIPT_DIR/network.sh" ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效的选择${NC}" ;;
    esac
    read -rp "按回车返回菜单..." _
}

# 主循环
while true; do
    show_singbox_status
    show_menu
    handle_choice
done
