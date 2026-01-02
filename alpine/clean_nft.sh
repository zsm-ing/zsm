#!/bin/bash

# 检查并删除 sing-box 的 nftables 表
if nft list table inet sing-box >/dev/null 2>&1; then
    nft delete table inet sing-box
    echo "✅ 已清理 sing-box 相关的防火墙规则。"
else
    echo "⚠️ 未找到 sing-box 防火墙规则，无需清理。"
fi

# 停止 sing-box 服务（Alpine 使用 rc-service）
rc-service sing-box stop 2>/dev/null || true
echo "🔒 sing-box 服务已停止。"
