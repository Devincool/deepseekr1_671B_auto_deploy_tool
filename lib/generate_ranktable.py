#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
作者: 华为山东产业发展与生态部 邱敏
描述: NPU集群rank_table文件生成工具
"""

import json
import subprocess
import paramiko
import sys
import re
import os
import argparse
from pathlib import Path

def get_npu_ips(ssh_client):
    """通过SSH获取NPU卡的IP地址"""
    npu_ips = []
    for i in range(8):  # 假设每台机器有8张NPU卡
        stdin, stdout, stderr = ssh_client.exec_command(f'hccn_tool -i {i} -ip -g')
        output = stdout.read().decode()
        # 使用正则表达式匹配IP地址
        ip_match = re.search(r'ipaddr+:(\d+\.\d+\.\d+\.\d+)', output)
        if ip_match:
            npu_ips.append(ip_match.group(1))
        else:
            print(f"警告: 无法获取NPU {i}的IP地址")
            return None
    return npu_ips

def connect_to_server(server_ip, username, password, use_key, key_path, port=22):
    """建立SSH连接"""
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        print(f"\n正在连接到 {server_ip}...")
        
        if use_key:
            if key_path:
                # 展开路径中的~
                key_path = os.path.expanduser(key_path)
                if not os.path.exists(key_path):
                    print(f"错误: SSH密钥文件不存在: {key_path}")
                    return None
                ssh.connect(server_ip, username=username, key_filename=key_path, port=port)
            else:
                # 使用默认密钥路径
                ssh.connect(server_ip, username=username, port=port)
        else:
            if not password:
                print("错误: 使用密码认证但未提供密码")
                return None
            ssh.connect(server_ip, username=username, password=password, port=port)
            
        return ssh
    except Exception as e:
        print(f"连接到 {server_ip} 失败: {str(e)}")
        return None

def get_local_ip(server_ips):
    """
    获取本机IP地址，并确保该IP地址在指定的server_ips列表中
    
    Args:
        server_ips: 服务器IP地址列表
        
    Returns:
        str: 匹配到的本机IP地址，如果未找到匹配则返回None
    """
    try:
        # 获取本机所有IP地址
        output = subprocess.check_output(['hostname', '-I'], text=True)
        local_ips = output.strip().split()
        
        # 在本机IP列表中查找匹配的server_ip
        for local_ip in local_ips:
            if local_ip in server_ips:
                return local_ip
                
        print("警告: 未在server_ips列表中找到匹配的本机IP地址")
        return None
    except subprocess.CalledProcessError as e:
        print(f"获取本地IP地址失败: {str(e)}")
        return None

def get_local_npu_ips():
    """在本地获取NPU卡的IP地址"""
    npu_ips = []
    for i in range(8):  # 假设每台机器有8张NPU卡
        try:
            output = subprocess.check_output(['hccn_tool', '-i', str(i), '-ip', '-g'], 
                                          stderr=subprocess.STDOUT).decode()
            ip_match = re.search(r'ipaddr+:(\d+\.\d+\.\d+\.\d+)', output)
            if ip_match:
                npu_ips.append(ip_match.group(1))
            else:
                print(f"警告: 无法获取NPU {i}的IP地址")
                return None
        except subprocess.CalledProcessError:
            print(f"警告: 执行hccn_tool命令失败")
            return None
    return npu_ips

def create_rank_table(server_ips, username, password, use_key, key_path, port=22):
    """创建rank_table文件的内容"""
    rank_table = {
        "server_count": str(len(server_ips)),
        "server_list": [],
        "status": "completed",
        "version": "1.0"
    }
    
    current_rank = 0
    local_ip = get_local_ip(server_ips)
    print(f"本机IP地址: {local_ip}")
    
    for server_idx, server_ip in enumerate(server_ips):
        try:
            # 检查是否为本机地址
            if local_ip and server_ip == local_ip:
                print(f"\n检测到本机地址 {server_ip}, 直接获取NPU信息...")
                npu_ips = get_local_npu_ips()
            else:
                ssh = connect_to_server(server_ip, username, password, use_key, key_path, port)
                if not ssh:
                    print("无法继续执行，请检查SSH连接配置")
                    return None
                npu_ips = get_npu_ips(ssh)
                ssh.close()
                
            if not npu_ips:
                print(f"错误: 无法从服务器 {server_ip} 获取NPU信息")
                continue
                
            # 创建服务器条目
            server_entry = {
                "device": [],
                "server_id": server_ip,
                "container_ip": server_ip
            }
            
            # 添加设备信息
            for device_id, device_ip in enumerate(npu_ips):
                device_entry = {
                    "device_id": str(device_id),
                    "device_ip": device_ip,
                    "rank_id": str(current_rank)
                }
                current_rank += 1
                server_entry["device"].append(device_entry)
            
            rank_table["server_list"].append(server_entry)
            
        except Exception as e:
            print(f"处理服务器 {server_ip} 时出错: {str(e)}")
            return None
    
    return rank_table

def parse_args():
    parser = argparse.ArgumentParser(description='NPU集群rank_table文件生成工具')
    parser.add_argument('--nodes', type=str, required=True,
                      help='节点IP地址列表，用逗号分隔')
    parser.add_argument('--username', type=str, required=True,
                      help='SSH用户名')
    parser.add_argument('--use-key', action='store_true',
                      help='使用SSH密钥认证')
    parser.add_argument('--key-path', type=str,
                      help='SSH私钥文件路径')
    parser.add_argument('--password', type=str,
                      help='SSH密码（不使用密钥认证时必需）')
    parser.add_argument('--port', type=int, default=22,
                      help='SSH端口号（默认：22）')
    return parser.parse_args()

def main():
    args = parse_args()
    nodes = args.nodes.split(',')
    print(f"处理的节点IP列表: {nodes}")
    
    rank_table = create_rank_table(
        server_ips=nodes,
        username=args.username,
        password=args.password,
        use_key=args.use_key,
        key_path=args.key_path,
        port=args.port
    )
    
    if rank_table is None:
        print("生成rank表失败")
        sys.exit(1)
        
    # 保存rank表
    output_path = 'rank_table_file.json'
    with open(output_path, 'w') as f:
        json.dump(rank_table, f, indent=4)
    print(f"rank表已生成并保存到: {output_path}")

if __name__ == '__main__':
    main() 