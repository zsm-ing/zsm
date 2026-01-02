#!/bin/bash
# Alpine sing-box UI 管理脚本（支持多面板 / 自动更新 / 回滚）

UI_DIR="/etc/sing-box/ui"
BACKUP_DIR="/tmp/sing-box/ui_backup"
TEMP_DIR="/tmp/sing-box-ui"

ZASHBOARD_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip"
METACUBEXD_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
YACD_URL="https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip"

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

mkdir -p "$BACKUP_DIR" "$TEMP_DIR"

# 检查依赖并安装 (Alpine 用 apk)
check_and_install_dependencies() {
    if ! command -v unzip &> /dev/null; then
        echo -e "${RED}unzip 未安装，正在安装...${NC}"
        apk update > /dev/null 2>&1
        apk add unzip > /dev/null 2>&1
    fi
}

# 获取下载地址
get_download_url() {
    CONFIG_FILE="/etc/sing-box/config.json"
    DEFAULT_URL="$ZASHBOARD_URL"
    
    if [ -f "$CONFIG_FILE" ]; then
        URL=$(grep -o '"external_ui_download_url": "[^"]*' "$CONFIG_FILE" | sed 's/"external_ui_download_url": "//')
        echo "${URL:-$DEFAULT_URL}"
    else
        echo "$DEFAULT_URL"
    fi
}

# 备份并移除旧 UI
backup_and_remove_ui() {
    if [ -d "$UI_DIR" ]; then
        echo -e "${CYAN}备份当前 UI 文件夹...${NC}"
        mv "$UI_DIR" "$BACKUP_DIR/$(date +%Y%m%d%H%M%S)_ui"
        echo -e "${GREEN}已备份至 $BACKUP_DIR${NC}"
    fi
}

# 下载并安装 UI
download_and_process_ui() {
    local url="$1"
    local temp_file="$TEMP_DIR/ui.zip"
    
    rm -rf "${TEMP_DIR:?}"/*
    
    echo -e "${CYAN}正在下载面板...${NC}"
    curl -L "$url" -o "$temp_file" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败,正在还原备份...${NC}"
        [ -d "$BACKUP_DIR" ] && mv "$BACKUP_DIR/"* "$UI_DIR" 2>/dev/null
        return 1
    fi

    echo -e "${CYAN}解压中...${NC}"
    if unzip "$temp_file" -d "$TEMP_DIR" > /dev/null 2>&1; then
        mkdir -p "$UI_DIR"
        rm -rf "${UI_DIR:?}"/*
        mv "$TEMP_DIR"/*/* "$UI_DIR"
        echo -e "${GREEN}面板安装完成${NC}"
        return 0
    else
        echo -e "${RED}解压失败,正在还原备份...${NC}"
        [ -d "$BACKUP_DIR" ] && mv "$BACKUP_DIR/"* "$UI_DIR" 2>/dev/null
        return 1
    fi
}

# 安装默认 UI
install_default_ui() {
    echo -e "${CYAN}正在安装默认 UI 面板...${NC}"
    DOWNLOAD_URL=$(get_download_url)
    backup_and_remove_ui
    download_and_process_ui "$DOWNLOAD_URL"
}

# 安装指定 UI
install_selected_ui() {
    local url="$1"
    backup_and_remove_ui
    download_and_process_ui "$url"
}

# 检查 UI 状态
check_ui() {
    if [ -d "$UI_DIR" ] && [ "$(ls -A "$UI_DIR")" ]; then
        echo -e "${GREEN}UI 面板已安装${NC}"
    else
        echo -e "${RED}UI 面板未安装或为空${NC}"
    fi
}

# 设置定时自动更新
setup_auto_update_ui() {
    local schedule_choice
    while true; do
        echo -e "${CYAN}请选择自动更新频率：${NC}"
        echo "1. 每周一"
        echo "2. 每月1号"
        read -rp "请输入选项(1/2, 默认为1): " schedule_choice
        schedule_choice=${schedule_choice:-1}

        if [[ "$schedule_choice" =~ ^[12]$ ]]; then
            break
        else
            echo -e "${RED}输入无效,请输入1或2。${NC}"
        fi
    done

    if crontab -l 2>/dev/null | grep -q '/etc/sing-box/update-ui.sh'; then
        echo -e "${RED}检测到已有自动更新任务。${NC}"
        read -rp "是否重新设置自动更新任务？(y/n): " confirm_reset
        if [[ "$confirm_reset" =~ ^[Yy]$ ]]; then
            crontab -l 2>/dev/null | grep -v '/etc/sing-box/update-ui.sh' | crontab -
            echo "已删除旧的自动更新任务。"
        else
            echo -e "${CYAN}保持已有的自动更新任务。返回菜单。${NC}"
            return
        fi
    fi

    cat > /etc/sing-box/update-ui.sh <<EOF
#!/bin/bash
CONFIG_FILE="/etc/sing-box/config.json"
DEFAULT_URL="$ZASHBOARD_URL"
URL=\$(grep -o '"external_ui_download_url": "[^"]*' "\$CONFIG_FILE" | sed 's/"external_ui_download_url": "//')
URL="\${URL:-\$DEFAULT_URL}"

TEMP_DIR="/tmp/sing-box-ui"
UI_DIR="/etc/sing-box/ui"
BACKUP_DIR="/tmp/sing-box/ui_backup"

mkdir -p "\$BACKUP_DIR" "\$TEMP_DIR"

if [ -d "\$UI_DIR" ]; then
    mv "\$UI_DIR" "\$BACKUP_DIR/\$(date +%Y%m%d%H%M%S)_ui"
fi

curl -L "\$URL" -o "\$TEMP_DIR/ui.zip"
if unzip "\$TEMP_DIR/ui.zip" -d "\$TEMP_DIR" > /dev/null 2>&1; then
    mkdir -p "\$UI_DIR"
    rm -rf "\${UI_DIR:?}"/*
    mv "\$TEMP_DIR"/*/* "\$UI_DIR"
else
    echo "解压失败，正在还原备份..."
    [ -d "\$BACKUP_DIR" ] && mv "\$BACKUP_DIR/"* "\$UI_DIR" 2>/dev/null
fi
EOF

    chmod a+x /etc/sing-box/update-ui.sh

    if [ "$schedule_choice" -eq 1 ]; then
        (crontab -l 2>/dev/null; echo "0 0 * * 1 /etc/sing-box/update-ui.sh") | crontab -
        echo -e "${GREEN}定时更新任务已设置，每周一执行一次${NC}"
    else
        (crontab -l 2>/dev/null; echo "0 0 1 * * /etc/sing-box/update-ui.sh") | crontab -
        echo -e "${GREEN}定时更新任务已设置，每月1号执行一次${NC}"
    fi

    rc-service crond restart
}

# 主菜单
update_ui() {
    check_and_install_dependencies
    while true; do
        echo -e "${CYAN}请选择功能：${NC}"
        echo "1. 默认 UI (依据配置文件)"
        echo "2. 安装/更新自选 UI"
        echo "3. 检查 UI 状态"
        echo "4. 设置定时自动更新"
        read -r -p "请输入选项(1/2/3/4)或按回车退出: " choice

        if [ -z "$choice" ]; then
            echo "退出程序。"
            exit 0
        fi

        case "$choice" in
            1) install_default_ui ;;
            2)
                echo -e "${CYAN}请选择面板：${NC}"
                echo "1. zashboard"
                echo "2. metacubexd"
                echo "3. yacd"
                read -r -p "请输入选项(1/2/3): " ui_choice
                case "$ui_choice" in
                    1) install_selected_ui "$ZASHBOARD_URL" ;;
                    2) install_selected_ui "$METACUBEXD_URL" ;;
                    3) install_selected_ui "$YACD_URL" ;;
                    *) echo -e "${RED}无效选项${NC}" ;;
                esac
                ;;
            3) check_ui ;;
            4) setup_auto_update_ui ;;
            *) echo -e "${RED}无效选项
