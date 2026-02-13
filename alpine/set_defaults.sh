#!/bin/bash

# 配置路径
DEFAULTS_FILE="/etc/sing-box/defaults.conf"
MANUAL_FILE="/etc/sing-box/manual.conf"
HEADERS_FILE="/tmp/sing-box-headers.txt"
POOL_FILE="/etc/sing-box/nodes.list"

# 颜色定义
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 错误处理
error_exit() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# 依赖检查
for cmd in curl jq awk sed; do
    command -v $cmd >/dev/null 2>&1 || error_exit "缺少依赖: $cmd"
done

# URL 编码
urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

# 更新配置文件
update_conf_file() {
    local file="$1" key="$2" value="$3"
    [ -f "$file" ] || touch "$file"
    local tmp=$(mktemp)
    awk -F= -v k="$key" -v v="$value" '
        BEGIN { found=0 }
        {
            split($0, a, "=");
            gsub(/^[ \t]+|[ \t]+$/, "", a[1]);
            if(a[1]==k) { print k"="v; found=1 }
            else { print $0 }
        }
        END { if(!found) print k"="v }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# 读取配置
get_config() {
    [ -f "$DEFAULTS_FILE" ] || return 0
    awk -F= -v k="$1" '{
        gsub(/^[ \t]+|[ \t]+$/, "", $1);
        gsub(/^[ \t]+|[ \t]+$/, "", $2);
        if($1==k) print $2
    }' "$DEFAULTS_FILE"
}

# 核心功能：获取最快节点
get_best_node() {
    NAV_URL=$(get_config NAV_URL)
    [ -z "$NAV_URL" ] && error_exit "未设置 NAV_URL！"

    echo -e "${CYAN}=== 正在解析导航页: $NAV_URL ===${NC}"
    
    # 增强正则匹配：匹配包含 hongxingyun 的完整 https 地址
    RAW_HTML=$(curl -fsSL --max-time 10 "$NAV_URL")
    NEW_LINKS=$(echo "$RAW_HTML" | grep -Eo 'https?://[a-zA-Z0-9.-]*hongxingyun[a-zA-Z0-9.-]*\.[a-z]{2,}' | sort -u)

    if [ -z "$NEW_LINKS" ]; then
        echo -e "${YELLOW}⚠ 导航页未提取到新域名，保持现有地址池${NC}"
    else
        echo -e "${GREEN}发现新地址:${NC}\n$NEW_LINKS"
        for link in $NEW_LINKS; do
            # 去掉末尾斜杠
            link=${link%/}
            grep -qx "$link" "$POOL_FILE" || echo "$link" >> "$POOL_FILE"
        done
    fi

    echo -e "\n${CYAN}>>> 正在对地址池进行延迟测试...${NC}"
    BEST=""
    BEST_LAT=9999
    TMP_POOL=$(mktemp)

    while read -r node; do
        [ -z "$node" ] && continue
        # 使用 -w %{time_connect} 获取连接时间，UA 模拟浏览器避免屏蔽
        LAT=$(curl -o /dev/null -sL --max-time 3 --connect-timeout 2 \
             -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
             -w "%{time_connect}" "$node")
        
        if [ $? -eq 0 ] && [ "$LAT" != "0.000" ]; then
            LAT_MS=$(awk "BEGIN {print int($LAT * 1000)}")
            echo -e "  $node ${GREEN}${LAT_MS}ms${NC}"
            echo "$node" >> "$TMP_POOL"
            if [ "$LAT_MS" -lt "$BEST_LAT" ]; then
                BEST="$node"
                BEST_LAT="$LAT_MS"
            fi
        else
            echo -e "  $node ${RED}连接失败${NC}"
        fi
    done < "$POOL_FILE"

    mv "$TMP_POOL" "$POOL_FILE"

    if [ -z "$BEST" ]; then
        BEST=$(get_config JC_URL)
        echo -e "${YELLOW}⚠ 无可用新节点，使用历史地址: $BEST${NC}"
    else
        echo -e "${GREEN}★ 最佳入口: $BEST (${BEST_LAT}ms)${NC}"
    fi

    update_conf_file "$DEFAULTS_FILE" "JC_URL" "$BEST"
    echo "$BEST"
}

# 核心功能：自动登录并获取订阅
auto_update_subscription() {
    USER=$(get_config USER)
    PASS=$(get_config PASS)
    BASE_URL=$(get_config JC_URL)

    [ -z "$USER" ] || [ -z "$PASS" ] && error_exit "账号或密码未配置，请先执行选项 6"

    echo -e "${CYAN}正在尝试登录 ${BASE_URL} ...${NC}"
    
    # 修复 Headers 文件路径
    rm -f "$HEADERS_FILE"
    LOGIN=$(curl -s -L -D "$HEADERS_FILE" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
      -d "email=$USER&password=$PASS" \
      "$BASE_URL/hxapicc/passport/auth/login")

    # 提取 Cookie
    COOKIE=$(grep -i "Set-Cookie" "$HEADERS_FILE" | head -n1 | sed -E 's/Set-Cookie:[[:space:]]*([^;]+).*/\1/')
    [ -n "$COOKIE" ] && update_conf_file "$DEFAULTS_FILE" "COOKIE" "$COOKIE"

    # 提取 Token
    AUTH=$(echo "$LOGIN" | jq -r '.data.auth_data // .data.token // .auth_data // .token')
    if [ "$AUTH" != "null" ] && [ -n "$AUTH" ]; then
        [[ $AUTH != Bearer* ]] && AUTH="Bearer $AUTH"
        update_conf_file "$DEFAULTS_FILE" "AUTH" "$AUTH"
    else
        error_exit "登录失败，接口返回: $LOGIN"
    fi

    echo -e "${GREEN}✅ 登录成功，正在获取订阅链接...${NC}"

    SUB_INFO=$(curl -s -L -H "Authorization: $AUTH" -H "Cookie: $COOKIE" \
      -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
      "$BASE_URL/hxapicc/user/getSubscribe")

    SUB_URL=$(echo "$SUB_INFO" | jq -r '.data.subscribe_url')

    if [ -n "$SUB_URL" ] && [ "$SUB_URL" != "null" ]; then
        echo -e "${GREEN}✅ 成功获取订阅: ${SUB_URL}${NC}"
        update_conf_file "$DEFAULTS_FILE" "SUBSCRIPTION_URL" "$SUB_URL"
        update_conf_file "$MANUAL_FILE" "SUBSCRIPTION_URL" "$SUB_URL"
    else
        echo -e "${RED}❌ 订阅解析失败。接口原始返回: $SUB_INFO${NC}"
    fi
}

# 处理参数模式（用于定时任务）
if [[ "$1" == "5" ]]; then
    get_best_node
    auto_update_subscription
    exit 0
fi

# 主菜单
while true; do
    echo -e "${CYAN}============================${NC}"
    echo -e "${CYAN} 配置订阅菜单${NC}"
    echo -e "${CYAN}============================${NC}"
    echo -e "${GREEN}1) 修改后端地址 ${NC}(当前: $(get_config BACKEND_URL))"
    echo -e "${GREEN}2) 修改订阅地址 ${NC}(当前: $(get_config SUBSCRIPTION_URL))"
    echo -e "${GREEN}3) 修改TProxy配置文件地址 ${NC}(当前: $(get_config TPROXY_TEMPLATE_URL))"
    echo -e "${GREEN}4) 修改TUN配置文件地址 ${NC}(当前: $(get_config TUN_TEMPLATE_URL))"
    echo -e "${GREEN}5) 自动登录并更新订阅地址 ${NC}(当前: $(get_config JC_URL))"
    echo -e "${GREEN}6) 修改 账号-密码-机场导航 ${NC}(当前: $(get_config NAV_URL))"
    echo -e "${YELLOW}7) 查看当前配置${NC}"
    echo -e "${RED}0) 退出${NC}"
    echo -e "${CYAN}============================${NC}"
    read -rp "请选择操作: " choice

    case $choice in
        1)
            read -rp "请输入新的后端地址: " val
            [ -n "$val" ] && set_config BACKEND_URL "$val"
            ;;
        2)
            read -rp "是否输入多个订阅地址? (y/n): " multi
            if [[ "$multi" =~ ^[Yy]$ ]]; then
                echo "请输入多个订阅地址，每行一个，输入空行结束:"
                urls=()
                while true; do
                    read -rp "> " addr
                    [ -z "$addr" ] && break
                    urls+=("$addr")
                done
                if [ ${#urls[@]} -eq 0 ]; then
                    echo -e "${RED}未输入任何地址${NC}"
                else
                    combined=$(printf "%s|" "${urls[@]}")
                    combined=${combined%|}
                    encoded_combined=$(urlencode "$combined")
                    set_config SUBSCRIPTION_URL "$encoded_combined"
                    echo -e "${GREEN}多地址已编码并更新${NC}"
                fi
            else
                read -rp "请输入新的订阅地址(单地址不编码): " val
                [ -n "$val" ] && set_config SUBSCRIPTION_URL "$val"
                echo -e "${GREEN}单地址已更新（未编码）${NC}"
            fi
            ;;
        3)
            read -rp "请输入新的TProxy配置文件地址: " val
            [ -n "$val" ] && set_config TPROXY_TEMPLATE_URL "$val"
            ;;
        4)
            read -rp "请输入新的TUN配置文件地址: " val
            [ -n "$val" ] && set_config TUN_TEMPLATE_URL "$val"
            ;;
        5)
            get_best_node
            auto_update_subscription
            ;;
        6)
            read -rp "是否修改登录邮箱? (y/n): " ans_user
            if [ "$ans_user" = "y" ]; then
                read -rp "请输入新的登录邮箱: " USER
                [ -n "$USER" ] && set_config USER "$USER" && echo "✅ 邮箱已更新" || echo "❌ 邮箱不能为空"
            fi

            read -rp "是否修改登录密码? (y/n): " ans_pass
            if [ "$ans_pass" = "y" ]; then
                read -rsp "请输入新的登录密码: " PASS
                echo
                [ -n "$PASS" ] && set_config PASS "$PASS" && echo "✅ 密码已更新" || echo "❌ 密码不能为空"
            fi

            read -rp "是否修改机场导航网址 NAV_URL? (y/n): " ans_url
            if [ "$ans_url" = "y" ]; then
                read -rp "请输入新机场导航网址 NAV_URL: " NAV_URL
                [ -n "$NAV_URL" ] && set_config NAV_URL "$NAV_URL" && echo "✅ 机场导航网址 已更新" || echo "❌ 机场导航网址 不能为空"
            fi
            ;;
        7)
            echo -e "${YELLOW}------ 当前配置 ------${NC}"
            [ -f "$DEFAULTS_FILE" ] && cat "$DEFAULTS_FILE" || echo "(配置文件不存在)"
            echo -e "${YELLOW}----------------------${NC}"
            ;;
        0)
            echo -e "${RED}已退出${NC}"
            break
            ;;
        *)
            echo -e "${RED}无效选择，请重试${NC}"
            ;;
    esac
done
