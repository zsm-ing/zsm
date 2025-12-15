import urllib.request
import math
from datetime import datetime
import ipaddress
import os
import logging

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger()

def main():
    logger.info("开始生成中国IPv4地址列表...")
    
    try:
        # 下载 APNIC 地址分配数据
        url = "https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"
        logger.info(f"下载APNIC数据: {url}")
        with urllib.request.urlopen(url, timeout=30) as response:
            raw_data = response.read().decode('utf-8')
        
        # 提取中国 IPv4 地址段
        china_ipv4 = []
        logger.info("处理原始数据...")
        for line in raw_data.splitlines():
            if line.startswith("apnic|CN|ipv4|"):
                parts = line.split('|')
                if len(parts) < 5:
                    continue
                
                ip = parts[3]
                count = int(parts[4])
                
                # 计算 CIDR 掩码
                cidr = 32 - int(math.log2(count))
                china_ipv4.append(f"{ip}/{cidr}")
        
        logger.info(f"获取到 {len(china_ipv4)} 个原始IPv4地址段")
        
        # 添加自定义地址段
        custom_ranges = [
            "10.10.10.0/24",   # 示例自定义网络
            "192.168.1.0/24"   # 示例本地网络
        ]
        
        # 合并所有地址段
        all_ranges = china_ipv4 + custom_ranges
        logger.info(f"添加 {len(custom_ranges)} 个自定义地址段，总计 {len(all_ranges)} 个地址段")
        
        # CIDR 合并优化 (使用标准库方法)
        logger.info("合并CIDR地址段...")
        networks = []
        for cidr in all_ranges:
            try:
                # 标准化CIDR表示
                network = ipaddress.ip_network(cidr, strict=False)
                networks.append(network)
            except ValueError as e:
                logger.warning(f"跳过无效CIDR: {cidr} - {e}")
        
        # 合并相邻的网络
        merged_cidrs = []
        if networks:
            merged_cidrs = list(ipaddress.collapse_addresses(networks))
        
        logger.info(f"合并后剩余 {len(merged_cidrs)} 个CIDR地址段 (减少 {len(all_ranges) - len(merged_cidrs)} 个)")
        
        # 生成 RouterOS 脚本
        ros_script = f"""################################################################
# 中国IPv4地址列表 - 自动生成 ({datetime.utcnow().strftime('%Y-%m-%d')})
# 来源: APNIC | 原始条目: {len(china_ipv4)} | 自定义条目: {len(custom_ranges)} | 优化后条目: {len(merged_cidrs)}
################################################################
/ip firewall address-list remove [find where list="CN"]
/ip firewall address-list\n"""
        
        for cidr in merged_cidrs:
            ros_script += f"add address={cidr} list=CN\n"
        
        # 添加注释标记自定义地址段
        ros_script += "\n# 以下为自定义地址段\n"
        for custom in custom_ranges:
            ros_script += f"add address={custom} list=CN comment=\"Custom Range\"\n"
        
        # 保存文件
        output_file = "china-ipv4.rsc"
        with open(output_file, "w") as f:
            f.write(ros_script)
        
        logger.info(f"生成完成! 输出文件: {output_file}")
        logger.info(f"文件大小: {os.path.getsize(output_file)/1024:.2f} KB")
        
        return 0
    
    except Exception as e:
        logger.error(f"处理失败: {str(e)}")
        return 1

if __name__ == "__main__":
    exit(main())
