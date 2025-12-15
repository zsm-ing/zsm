import urllib.request
import os
from datetime import datetime

def main():
    # 下载APNIC地址分配数据
    url = "https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"
    raw_data = urllib.request.urlopen(url).read().decode('utf-8')

    # 提取中国IPv6地址段
    china_ipv6 = []
    for line in raw_data.splitlines():
        if line.startswith("apnic|CN|ipv6|"):
            parts = line.split('|')
            prefix = parts[3]
            mask = parts[4]
            china_ipv6.append(f"{prefix}/{mask}")

    # 生成RouterOS脚本
    ros_script = f"""################################################################
# 中国IPv6地址列表 - 自动生成 ({datetime.utcnow().strftime('%Y-%m-%d')})
# 来源: APNIC | 条目数: {len(china_ipv6)}
################################################################
/ipv6 firewall address-list remove [find where list="CN"]
/ipv6 firewall address-list\n"""

    for cidr in china_ipv6:
        ros_script += f"add address={cidr} list=CN\n"

    # 保存文件
    with open("china-ipv6.rsc", "w") as f:
        f.write(ros_script)

if __name__ == "__main__":
    main()
