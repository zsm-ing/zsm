#!/bin/bash

#################################################
# 描述: Alpine 下 sing-box 安装检测脚本
# 版本: 1.0.0
#################################################

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 此脚本需要 root 权限，请使用 sudo 或 root 运行。"
    exit 1
fi

# 检查 sing-box 是否已安装
if command -v sing-box &> /dev/null; then
    current_version=$(sing-box version | grep 'sing-box version' | awk '{print $3}')
    echo "✅ sing-box 已安装，版本：$current_version"
else
    echo "⚠️ sing-box 未安装"
    echo "提示: 在 Alpine 下可以使用以下命令安装："
    echo "  apk update && apk add sing-box"
fi
