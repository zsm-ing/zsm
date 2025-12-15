#!/bin/sh
# OpenWrt LXC Status Fix Menu Script (FULL MEMORY FIX)
# Fix / Rollback Model, CPU, Memory (detail) display for LuCI

SYS_LUA="/usr/lib/lua/luci/sys.lua"
BACKUP="${SYS_LUA}.lxc.bak"
BOARD_JSON="/etc/board.json"

apply_fix() {
    echo "[*] Applying OpenWrt LXC display fixes..."

    # ---------- Model ----------
    echo "  - Fixing model"
    cat > "$BOARD_JSON" << 'EOF'
{
  "model": {
    "id": "pve-lxc",
    "name": "Proxmox VE LXC (OpenWrt)"
  }
}
EOF

    # ---------- Backup ----------
    if [ ! -f "$BACKUP" ]; then
        echo "  - Backing up luci sys.lua"
        cp "$SYS_LUA" "$BACKUP"
    fi

    # ---------- Patch ----------
    if grep -q "LXC CGROUP FULL MEMORY PATCH BEGIN" "$SYS_LUA"; then
        echo "  - Patch already applied, skipping"
        return
    fi

    echo "  - Patching CPU & FULL memory display"

    cat >> "$SYS_LUA" << 'EOF'

-- === LXC CGROUP FULL MEMORY PATCH BEGIN ===

local function read_proc_meminfo()
    local t = {}
    for line in io.lines("/proc/meminfo") do
        local k, v = line:match("(%w+):%s+(%d+)")
        if k and v then
            t[k] = tonumber(v)
        end
    end
    return t
end

local function read_cgroup_mem()
    local fmax = io.open("/sys/fs/cgroup/memory.max")
    local fcur = io.open("/sys/fs/cgroup/memory.current")
    if not fmax or not fcur then
        if fmax then fmax:close() end
        if fcur then fcur:close() end
        return nil
    end

    local max = fmax:read("*l")
    local cur = fcur:read("*l")
    fmax:close()
    fcur:close()

    if max == "max" then return nil end
    return tonumber(max) / 1024, tonumber(cur) / 1024
end

local function read_cgroup_cpu()
    local f = io.open("/sys/fs/cgroup/cpu.max")
    if not f then return nil end
    local q,p = f:read("*l"):match("(%d+)%s+(%d+)")
    f:close()
    if not q or not p then return nil end
    return tonumber(q) / tonumber(p)
end

-- override meminfo
local _meminfo = meminfo
function meminfo()
    local info = _meminfo()
    local proc = read_proc_meminfo()
    local total, used = read_cgroup_mem()

    if total and used then
        info.MemTotal  = total
        info.MemUsed   = used
        info.MemFree   = total - used
        info.Buffers   = proc.Buffers or 0
        info.Cached    = proc.Cached or 0

        -- LXC: swap from host is invalid
        info.SwapTotal = 0
        info.SwapFree  = 0
    end

    return info
end

-- override cpuinfo (core count)
local _cpuinfo = cpuinfo
function cpuinfo()
    local info = _cpuinfo()
    local cores = read_cgroup_cpu()
    if cores then
        info.cores = cores
    end
    return info
end

-- === LXC CGROUP FULL MEMORY PATCH END ===

EOF

    echo "[✓] Patch applied"
}

rollback_fix() {
    echo "[*] Rolling back OpenWrt LXC display fixes..."

    if [ -f "$BACKUP" ]; then
        echo "  - Restoring luci sys.lua"
        cp "$BACKUP" "$SYS_LUA"
    else
        echo "  - No sys.lua backup found"
    fi

    if [ -f "$BOARD_JSON" ]; then
        echo "  - Removing custom board.json"
        rm -f "$BOARD_JSON"
    fi

    echo "[✓] Rollback completed"
}

restart_services() {
    echo "[*] Restarting services..."
    /etc/init.d/ubus restart >/dev/null 2>&1
    /etc/init.d/uhttpd restart >/dev/null 2>&1
}

while true; do
    clear
    echo "OpenWrt LXC Status Fix Menu"
    echo "=========================="
    echo "1) 修复 显示问题（型号 / CPU / 内存-完整）"
    echo "2) 回退 到修复前状态"
    echo "0) 退出"
    echo
    printf "请选择: "
    read choice

    case "$choice" in
        1)
            apply_fix
            restart_services
            read -p "按回车继续..."
            ;;
        2)
            rollback_fix
            restart_services
            read -p "按回车继续..."
            ;;
        0)
            exit 0
            ;;
        *)
            echo "无效选项"
            sleep 1
            ;;
    esac
done
