#######  --sing-box--  #######


## 脚本：
```
bash <(curl -sL https://gh-proxy.com/https://raw.githubusercontent.com/zsm-ing/zsm/refs/heads/main/sbshall.sh)
```

# Custom Caddy for Alpine (layer4 + Cloudflare DNS)

这是一个 **专为 Alpine / Docker 构建的 Caddy**，内置：

- ✅ layer4（TCP / UDP 代理）
- ✅ Cloudflare DNS（DNS-01 / DDNS）
- ✅ 静态编译（musl），Alpine 直接运行

---

## 📦 包含插件

- github.com/mholt/caddy-l4
- github.com/caddy-dns/cloudflare

---

## 🚀 使用方式

```bash
#!/sbin/openrc-run

name="sing-box"
command="/usr/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
pidfile="/run/sing-box.pid"
command_background="yes"

depend() {
    need net
    use dns logger
}

start_pre() {
    # 清理旧的 pidfile，避免残留导致 stop 失败
    rm -f /run/sing-box.pid
    sleep 3
    MODE=$(grep -oE '^MODE=.*' /etc/sing-box/mode.conf | cut -d'=' -f2)
    if [ "$MODE" = "TProxy" ]; then
        [ -x /etc/sing-box/scripts/configure_tproxy.sh ] && /etc/sing-box/scripts/configure_tproxy.sh
    elif [ "$MODE" = "TUN" ]; then
        [ -x /etc/sing-box/scripts/configure_tun.sh ] && /etc/sing-box/scripts/configure_tun.sh
    fi
}

stop() {
    ebegin "Stopping sing-box"
    # 同时指定 exec 和 pidfile，确保能匹配到进程
    start-stop-daemon --stop --exec /usr/bin/sing-box --pidfile /run/sing-box.pid
    eend $?
}

reload() {
    ebegin "Reloading sing-box"
    # 发送 HUP 信号以重新加载配置文件
    start-stop-daemon --signal HUP --pidfile /run/sing-box.pid
    eend $?
}
```
