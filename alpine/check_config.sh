#!/bin/bash

#################################################
# 描述: Alpine 下 sing-box 配置文件检查脚本
# 版本: 1.0.0
#################################################

# 定义颜色
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # 无颜色

CONFIG_FILE="/etc/sing-box/config.json"

# 检查配置文件是否存在
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${CYAN}正在检查配置文件: ${CONFIG_FILE} ...${NC}"
    
    # 验证配置文件
    if sing-box check -c "$CONFIG_FILE"; then
        echo -e "${GREEN}配置文件验证通过！${NC}"
        exit 0
    else
        echo -e "${RED}配置文件验证失败，请检查语法或内容！${NC}"
        exit 1
    fi
else
    echo -e "${RED}配置文件 ${CONFIG_FILE} 不存在！${NC}"
    echo -e "${CYAN}请先生成或下载配置文件到 ${CONFIG_FILE}${NC}"
    exit 1
fi
