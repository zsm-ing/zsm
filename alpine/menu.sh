#!/bin/bash
set -Eeuo pipefail

#################################################
# 描述: Alpine Linux sing-box 全自动脚本
# 版本: 1.1.0 (Alpine ONLY)
#################################################

# ===== Alpine 系统检测 =====
if [ ! -f /etc/os-release ] || ! grep -qi '^ID=alpine' /etc/os-release; then
    echo -e "\033[0;31m[ERROR]\033[0m 本脚本仅支持 Alpine Linux"
    exit 1
fi

# ===== 依赖检查 =====
for pkg in bash curl; do
    command -v "$pkg" >/dev/null 2>&1 || {
        echo "[INFO] 安装依赖: $pkg"
        apk add --no-cache "$pkg"
    }
done

# ===== 颜色 =====
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ===== 路径 =====
SCRIPT_DIR="/etc/sing-box/scripts"
INITIALIZED_FILE="$SCRIPT_DIR/.initialized"

mkdir -p "$SCRIPT_DIR"
chown root:root "$SCRIPT_DIR" 2>/dev/null || true

# ===== GitHub 仓库 =====
BASE_URL="https://raw.githubusercontent.com/zsm-ing/zsm/main/openwrt"

# ===== 脚本列表 =====
SCRIPTS=(
    "check_environment.sh"
    "install_singbox.sh"
    "manual_input.sh"
    "manual_update.sh"
    "auto_update.sh"
    "configure_tproxy.sh"
    "configure_tun.sh"
    "start_singbox.sh"
    "stop_singbox.sh"
    "clean_nft.sh"
    "set_defaults.sh"
    "commands.sh"
    "switch_mode.sh"
    "manage_autostart.sh"
    "check_config.sh"
    "update_singbox.sh"
    "update_scripts.sh"
    "update_ui.sh"
    "menu.sh"
)

# ===== 下载函数 =====
download_script() {
    local script="$1"
    local retries=5

    for ((i=1; i<=retries; i++)); do
        if curl -fsSL -o "$SCRIPT_DIR/$script" "$BASE_URL/$script"; then
            chmod +x "$SCRIPT_DIR/$script"
            return 0
        fi
        echo -e "${YELLOW}下载 $script 失败，重试 $i/$retries${NC}"
        sleep 2
    done

    echo -e "${RED}下载 $script 失败${NC}"
    return 1
}

# ===== 并行下载 =====
parallel_download_scripts() {
    local failed=0
    local pids=()

    for s in "${SCRIPTS[@]}"; do
        download_script "$s" &
        pids+=("$!")
    done

    for pid in "${pids[@]}"; do
        wait "$pid" || failed=1
    done

    [ "$failed" -eq 0 ] || {
        echo -e "${RED}部分脚本下载失败，初始化中止${NC}"
        exit 1
    }
}

# ===== 初始化 =====
initialize() {
    echo -e "${CYAN}初始化 Alpine sing-box 环境...${NC}"

    rm -rf "$SCRIPT_DIR"/*
    mkdir -p "$SCRIPT_DIR"

    parallel_download_scripts

    mkdir -p /etc/sing-box
    touch /etc/sing-box/mode.conf
    chmod 600 /etc/sing-box/mode.conf

    bash "$SCRIPT_DIR/check_environment.sh"
    command -v sing-box >/dev/null 2>&1 \
        || bash "$SCRIPT_DIR/install_singbox.sh" \
        || bash "$SCRIPT_DIR/update_singbox.sh"

    bash "$SCRIPT_DIR/switch_mode.sh"
    bash "$SCRIPT_DIR/manual_input.sh"
    bash "$SCRIPT_DIR/start_singbox.sh"

    touch "$INITIALIZED_FILE"
}

# ===== 首次运行 =====
if [ ! -f "$INITIALIZED_FILE" ]; then
    echo -e "${CYAN}回车开始初始化，输入 skip 跳过${NC}"
    read -r choice
    if [[ ! "$choice" =~ ^[Ss]kip$ ]]; then
        initialize
    fi
fi

# ===== 命令别名（Alpine 推荐方式）=====
mkdir -p /etc/profile.d
cat <<'EOF' > /etc/profile.d/sb.sh
alias sb='bash /etc/sing-box/scripts/menu.sh menu'
EOF

# ===== 快捷命令 =====
if [ ! -f /usr/bin/sb ]; then
    cat <<'EOF' > /usr/bin/sb
#!/bin/bash
bash /etc/sing-box/scripts/menu.sh menu
EOF
    chmod +x /usr/bin/sb
fi

# ===== 菜单 =====
show_menu() {
    echo -e "${CYAN}=========== Sbshell 管理菜单 (Alpine) ===========${NC}"
    echo -e "${GREEN}1. Tproxy/TUN 模式切换${NC}"
    echo -e "${GREEN}2. 手动更新配置${NC}"
    echo -e "${GREEN}3. 自动更新配置${NC}"
    echo -e "${GREEN}4. 启动 sing-box${NC}"
    echo -e "${GREEN}5. 停止 sing-box${NC}"
    echo -e "${GREEN}6. 设置参数${NC}"
    echo -e "${GREEN}7. 设置自启动${NC}"
    echo -e "${GREEN}8. 常用命令${NC}"
    echo -e "${GREEN}9. 更新脚本${NC}"
    echo -e "${GREEN}10. 更新面板${NC}"
    echo -e "${GREEN}11. 更新 sing-box${NC}"
    echo -e "${GREEN}0. 退出${NC}"
    echo -e "${CYAN}===============================================${NC}"
}

handle_choice() {
    read -rp "请选择操作: " c
    case "$c" in
        1) bash "$SCRIPT_DIR/switch_mode.sh"; bash "$SCRIPT_DIR/manual_input.sh"; bash "$SCRIPT_DIR/start_singbox.sh" ;;
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
        0) exit 0 ;;
        *) echo -e "${RED}无效选择${NC}" ;;
    esac
}

while true; do
    show_menu
    handle_choice
done
