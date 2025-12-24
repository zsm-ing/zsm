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

### 1️⃣ 下载 GitHub Actions 构建产物

```bash
chmod +x caddy-alpine-amd64
./caddy-alpine-amd64 version
