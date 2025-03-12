#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
作者: 华为山东产业发展与生态部 邱敏
描述: Mindie服务配置修改工具
"""

import json
import os
import shutil
import re
import argparse
from datetime import datetime

CONFIG_PATH = "/usr/local/Ascend/mindie/latest/mindie-service/conf/config.json"

def load_json_file(file_path):
    """加载JSON文件"""
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"错误: 无法读取文件 {file_path}: {str(e)}")
        return None

def backup_config(file_path):
    """备份配置文件"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = f"{file_path}.backup_{timestamp}"
    try:
        shutil.copy2(file_path, backup_path)
        print(f"已创建配置文件备份: {backup_path}")
        return True
    except Exception as e:
        print(f"错误: 备份配置文件失败: {str(e)}")
        return False

def validate_ip(ip):
    """验证IP地址格式"""
    pattern = r'^(\d{1,3}\.){3}\d{1,3}$'
    if not re.match(pattern, ip):
        return False
    return all(0 <= int(x) <= 255 for x in ip.split('.'))

def modify_config(config_data, master_ip, model_name, model_path, world_size):
    """修改配置文件内容"""
    try:
        # 修改ServerConfig
        config_data["ServerConfig"]["ipAddress"] = master_ip
        config_data["ServerConfig"]["managementIpAddress"] = master_ip
        config_data["ServerConfig"]["httpsEnabled"] = False
        config_data["ServerConfig"]["interCommTLSEnabled"] = False

        # 修改BackendConfig
        backend_config = config_data["BackendConfig"]
        backend_config["multiNodesInferEnabled"] = True
        backend_config["interNodeTLSEnabled"] = False
        backend_config["npuDeviceIds"] = [[0,1,2,3,4,5,6,7]]

        # 修改ModelDeployConfig
        model_deploy_config = backend_config["ModelDeployConfig"]
        model_deploy_config["maxSeqLen"] = 10000
        model_deploy_config["maxInputTokenLen"] = 2048
        
        # 修改ModelConfig
        model_config = model_deploy_config["ModelConfig"][0]
        model_config["modelName"] = model_name
        model_config["modelWeightPath"] = model_path
        model_config["worldSize"] = 8

        # 添加缺失的ScheduleConfig配置
        schedule_config = backend_config["ScheduleConfig"]
        schedule_config["maxPrefillTokens"] = 10000
        schedule_config["maxIterTimes"] = 7052

        return True
    except Exception as e:
        print(f"错误: 修改配置失败: {str(e)}")
        return False

def save_config(config_data, file_path):
    """保存配置文件"""
    try:
        with open(file_path, 'w') as f:
            json.dump(config_data, f, indent=4)
        print(f"配置已成功保存到: {file_path}")
        return True
    except Exception as e:
        print(f"错误: 保存配置文件失败: {str(e)}")
        return False

def parse_args():
    parser = argparse.ArgumentParser(description='Mindie服务配置修改工具')
    parser.add_argument('--master-ip', type=str, required=True,
                      help='主节点IP地址')
    parser.add_argument('--model-name', type=str, required=True,
                      help='模型名称')
    parser.add_argument('--model-path', type=str, required=True,
                      help='模型路径')
    parser.add_argument('--world-size', type=int, required=True,
                      help='总的设备数量')
    parser.add_argument('--config-path', type=str, default=CONFIG_PATH,
                      help=f'配置文件路径 (默认: {CONFIG_PATH})')
    return parser.parse_args()

def main():
    args = parse_args()
    
    # 验证IP地址
    if not validate_ip(args.master_ip):
        print(f"错误: 无效的IP地址格式: {args.master_ip}")
        return

    # 检查配置文件是否存在
    if not os.path.exists(args.config_path):
        print(f"错误: 配置文件不存在: {args.config_path}")
        return

    # 加载配置文件
    config_data = load_json_file(args.config_path)
    if not config_data:
        return

    # 备份配置文件
    if not backup_config(args.config_path):
        return

    # 修改配置
    if not modify_config(config_data, args.master_ip, args.model_name, 
                        args.model_path, args.world_size):
        return

    # 保存配置
    if not save_config(config_data, args.config_path):
        return

    print("配置修改完成!")

if __name__ == "__main__":
    main() 