#!/bin/bash

DEFAULTS_FILE="/etc/sing-box/defaults.conf"
MANUAL_FILE="/etc/sing-box/manual.conf"
HEADERS_FILE="/etc/sing-box/headers.txt"
POOL_FILE="/etc/sing-box/nodes.list"

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 错误处理函数
error_exit() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# 依赖检查
for cmd in curl jq awk sed; do
    command -v $cmd >/dev/null 2>&1 || error_exit "缺少依赖: $cmd"
done

# URL 编码函数
urlencode() {
    jq -rn --arg v "$1" '$v|@uri'
}

# 通用函数：更新指定配置文件中的 key=value，如果不存在则新增
update_conf_file() {
    local file="$1"
    local key="$2"
    local value="$3"

    # 如果文件不存在，先创建空文件
    [ -f "$file" ] || touch "$file"

    tmp=$(mktemp) || { echo "无法创建临时文件"; return 1; }
    awk -F= -v k="$key" -v v="$value" '
        BEGIN { found=0 }
        $1==k { print k"="v; found=1; next }
        { print }
        END { if(!found) print k"="v }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# 读取配置函数
get_config() {
    local key=$1
    # 文件不存在时返回空
    [ -f "$DEFAULTS_FILE" ] || { echo ""; return 0; }
    # awk 去掉 key 和 value 两边空格，匹配 key
    awk -F= -v k="$key" '{
        gsub(/^[ \t]+|[ \t]+$/, "", $1);
        gsub(/^[ \t]+|[ \t]+$/, "", $2);
        if($1==k) print $2
    }' "$DEFAULTS_FILE"
}

# 更新配置函数
set_config() {
    local key=$1
    local value=$2

    # 更新 defaults.conf
    update_conf_file "$DEFAULTS_FILE" "$key" "$value"
    echo -e "${GREEN}已更新 $key=$value${NC}"

    # 如果是 SUBSCRIPTION_URL，同步更新 manual.conf
    if [ "$key" == "SUBSCRIPTION_URL" ]; then
        update_conf_file "$MANUAL_FILE" "$key" "$value"
        echo -e "${GREEN}manual.conf 文件中也已更新${NC}"
    fi
}

# 初始化池文件
[ -f "$POOL_FILE" ] || touch "$POOL_FILE"

# 自动选择最快节点
get_best_node() {
    NAV_URL=$(get_config NAV_URL)
    [ -z "$NAV_URL" ] && echo "错误：未设置 NAV_URL！" && exit 1

    echo "=== 解析导航页：$NAV_URL ==="

    RAW_HTML=$(curl -fsS --max-time 5 "$NAV_URL" 2>/dev/null)

    NEW_LINKS=$(echo "$RAW_HTML" \
        | grep -Eo 'hongxingyun\.[A-Za-z0-9]{2,6}' \
        | sed 's#^#https://#' \
        | sort -u)

    echo "从导航页获得："
    echo "$NEW_LINKS"
    echo

    echo ">>> 测试新获取的地址"

    for link in $NEW_LINKS; do
        curl -o /dev/null -s --max-time 3 --connect-timeout 2 "$link"
        if [ $? -eq 0 ]; then
            echo "  $link ✓ 可用"
            grep -qx "$link" "$POOL_FILE" || echo "$link" >> "$POOL_FILE"
        else
            echo "  $link ✗ 不可用（不加入池）"
        fi
    done

    echo
    echo ">>> 地址池内容："
    cat "$POOL_FILE" 2>/dev/null || echo "(空)"
    echo "---------------"

    echo ">>> 从地址池全部重新测速（失败剔除）"

    BEST=""
    BEST_LAT=999999
    TMP_POOL=$(mktemp)

    while read -r node; do
        [ -z "$node" ] && continue

        LAT=$(curl -o /dev/null -s --max-time 3 --connect-timeout 2 -w "%{time_starttransfer}" "$node")
        RET=$?

        if [ $RET -ne 0 ]; then
            echo "  $node ✗ 已失效，剔除"
            continue
        fi

        LAT_MS=$(awk "BEGIN {print int($LAT * 1000)}")
        echo "  $node 延迟：${LAT_MS}ms"

        echo "$node" >> "$TMP_POOL"

        if [ "$LAT_MS" -lt "$BEST_LAT" ]; then
            BEST="$node"
            BEST_LAT="$LAT_MS"
        fi
    done < "$POOL_FILE"

    mv "$TMP_POOL" "$POOL_FILE"

    if [ -z "$BEST" ]; then
        echo "⚠ 地址池已空，尝试使用历史 JC_URL"
        BEST=$(get_config JC_URL)
        [ -z "$BEST" ] && error_exit "没有可用入口，也没有历史 JC_URL"
        BEST_LAT="未知"
    fi

    echo "=== 最终选择入口：$BEST（${BEST_LAT}ms）==="

    update_conf_file "$DEFAULTS_FILE" "JC_URL" "$BEST"
    echo "已更新 JC_URL=$BEST"

    echo "$BEST"
}

# 自动登录并获取订阅地址
auto_update_subscription() {
    USER=$(get_config USER)
    PASS=$(get_config PASS)

    if [ -z "$USER" ] || [ -z "$PASS" ]; then
        read -rp "请输入登录邮箱: " USER
        read -rp "请输入登录密码: " PASS
        set_config USER "$USER"
        set_config PASS "$PASS"
    fi

    BASE_URL=$(get_config JC_URL)

    echo "尝试登录..."
    LOGIN=$(curl -s -D $HEADERS_FILE \
      -d "email=$USER&password=$PASS" \
      "$BASE_URL/hxapicc/passport/auth/login")

    echo "登录返回原始数据: $LOGIN"

    COOKIE=$(grep -i "Set-Cookie" headers.txt | head -n1 | sed -E 's/Set-Cookie:[[:space:]]*([^;]+).*/\1/')
    if [ -n "$COOKIE" ]; then
        set_config COOKIE "$COOKIE"
        echo "✅ 已保存 Cookie 到 defaults.conf"
    else
        echo "❌ 未获取到 Cookie"
    fi

    AUTH=$(echo "$LOGIN" | jq -r '.data.auth_data // .data.token // .auth_data // .token')
    if [ -n "$AUTH" ] && [ "$AUTH" != "null" ]; then
        case $AUTH in
            Bearer*) ;;
            *) AUTH="Bearer $AUTH" ;;
        esac
        set_config AUTH "$AUTH"
        echo "✅ 已保存 Bearer Token 到 defaults.conf"
    else
        echo "❌ 登录失败，未获取到 Bearer Token"
        return 1
    fi

    echo "✅ 登录成功，获取到认证信息: $AUTH"

    SUB_INFO=$(curl -s -H "Authorization: $AUTH" -H "Cookie: $COOKIE" \
      "$BASE_URL/hxapicc/user/getSubscribe")

    echo "订阅接口返回原始数据: $SUB_INFO"

    SUB_URL=$(echo "$SUB_INFO" | jq -r '.data.subscribe_url')
    if [ -n "$SUB_URL" ] && [ "$SUB_URL" != "null" ]; then
        echo "✅ 订阅地址: $SUB_URL"
        set_config SUBSCRIPTION_URL "$SUB_URL"
    else
        echo "❌ 未能获取订阅地址，请检查接口返回"
    fi
}

# 参数模式执行
if [[ $# -gt 0 ]]; then
    choice=$1
    case $choice in
        5)
            get_best_node
            auto_update_subscription
            exit 0
            ;;
        *)
            echo "未知参数: $choice"
            exit 1
            ;;
    esac
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
