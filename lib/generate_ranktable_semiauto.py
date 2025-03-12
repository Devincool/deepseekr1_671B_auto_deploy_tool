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

def get_ssh_credentials():
    """获取SSH连接凭据"""
    username = input("请输入SSH用户名 (默认为当前用户): ").strip() or os.getenv('USER')
    use_key = input("是否使用SSH密钥登录? (y/N): ").lower().strip() == 'y'
    
    password = None
    if not use_key:
        import getpass
        password = getpass.getpass("请输入SSH密码: ")
    
    return username, password, use_key

def connect_to_server(server_ip, username, password, use_key):
    """建立SSH连接"""
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        print(f"\n正在连接到 {server_ip}...")
        
        if use_key:
            ssh.connect(server_ip, username=username)
        else:
            ssh.connect(server_ip, username=username, password=password)
            
        return ssh
    except Exception as e:
        print(f"连接到 {server_ip} 失败: {str(e)}")
        return None

def create_rank_table(server_ips, username, password, use_key):
    """创建rank_table文件的内容"""
    rank_table = {
        "server_count": str(len(server_ips)),
        "server_list": [],
        "status": "completed",
        "version": "1.0"
    }
    
    current_rank = 0
    
    for server_idx, server_ip in enumerate(server_ips):
        try:
            ssh = connect_to_server(server_ip, username, password, use_key)
            if not ssh:
                print("无法继续执行，请检查SSH连接配置")
                return None
                
            # 获取NPU卡IP地址
            npu_ips = get_npu_ips(ssh)
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
            ssh.close()
            
        except Exception as e:
            print(f"处理服务器 {server_ip} 时出错: {str(e)}")
            return None
    
    return rank_table

def main():
    print("=== NPU集群rank_table文件生成工具 ===")
    
    username, password, use_key = get_ssh_credentials()
    
    # 获取服务器IP地址列表
    server_ips = []
    print("\n请输入服务器IP地址（第一个将作为主节点，输入'done'完成）:")
    while True:
        ip = input("服务器IP (或 'done'): ").strip()
        if ip.lower() == 'done':
            break
        if re.match(r'^\d+\.\d+\.\d+\.\d+$', ip):
            server_ips.append(ip)
        else:
            print("无效的IP地址格式，请重新输入")
    
    if len(server_ips) == 0:
        print("错误: 至少需要输入一个服务器IP地址")
        return
    
    # 创建rank_table内容，传递所有认证参数
    rank_table = create_rank_table(server_ips, username, password, use_key)
    if not rank_table:
        print("生成rank_table文件失败")
        return
    
    # 保存到文件
    try:
        with open('rank_table_file.json', 'w') as f:
            json.dump(rank_table, f, indent=3)
        print("\n成功生成rank_table_file.json文件")
    except Exception as e:
        print(f"错误: 保存文件失败: {str(e)}")

if __name__ == "__main__":
    main()
