#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 检查 sing-box 是否已安装
if ! command -v sing-box &> /dev/null; then
    echo -e "${RED}❌ 未检测到 sing-box，请先安装。${NC}"
    bash /etc/sing-box/scripts/install_singbox.sh
    exit 1
fi

# 确定文件存在
mkdir -p /etc/sing-box/
[ -f /etc/sing-box/mode.conf ] || touch /etc/sing-box/mode.conf
chmod 644 /etc/sing-box/mode.conf

echo -e "${CYAN}切换模式开始...请根据提示输入操作。${NC}"

while true; do
    # 选择模式
    read -rp "请选择模式(1: TProxy 模式, 2: TUN 模式): " mode_choice

    # 停止 sing-box 服务 (Alpine 使用 rc-service)
    rc-service sing-box stop

    case $mode_choice in
        1)
            echo "MODE=TProxy" > /etc/sing-box/mode.conf
            echo -e "${GREEN}✅ 当前选择模式为: TProxy 模式${NC}"
            break
            ;;
        2)
            echo "MODE=TUN" > /etc/sing-box/mode.conf
            echo -e "${GREEN}✅ 当前选择模式为: TUN 模式${NC}"
            break
            ;;
        *)
            echo -e "${RED}❌ 无效的选择，请重新输入。${NC}"
            ;;
    esac
done

# 重启 sing-box 服务以应用新模式
rc-service sing-box start
if rc-service sing-box status | grep -q "started"; then
    echo -e "${GREEN}✅ sing-box 已重新启动并应用新模式${NC}"
else
    echo -e "${RED}❌ sing-box 启动失败，请检查日志${NC}"
fi
