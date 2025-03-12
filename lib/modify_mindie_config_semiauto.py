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
from datetime import datetime

def load_json_file(file_path):
    """加载JSON文件"""
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"错误: 无法读取文件 {file_path}: {str(e)}")
        return None

def save_json_file(file_path, data):
    """保存JSON文件"""
    try:
        with open(file_path, 'w') as f:
            json.dump(data, f, indent=4)
        return True
    except Exception as e:
        print(f"错误: 无法保存文件 {file_path}: {str(e)}")
        return False

def backup_config_file(file_path):
    """备份配置文件"""
    try:
        backup_path = f"{file_path}.backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        shutil.copy2(file_path, backup_path)
        print(f"已创建配置文件备份: {backup_path}")
        return True
    except Exception as e:
        print(f"警告: 无法创建配置文件备份: {str(e)}")
        return False

def is_valid_ip(ip):
    """验证IP地址格式"""
    pattern = r'^(\d{1,3}\.){3}\d{1,3}$'
    if not re.match(pattern, ip):
        return False
    # 验证每个数字在0-255之间
    return all(0 <= int(num) <= 255 for num in ip.split('.'))

def get_user_input():
    """获取用户输入的配置参数"""
    # 获取IP地址
    while True:
        ip = input("请输入服务器IP地址: ").strip()
        if is_valid_ip(ip):
            break
        print("错误: 无效的IP地址格式，请重新输入")
    
    # 获取模型名称
    model_name = input("请输入模型名称: ").strip()
    while not model_name:
        print("错误: 模型名称不能为空")
        model_name = input("请输入模型名称: ").strip()
    
    # 获取模型权重路径
    model_path = input("请输入模型权重路径: ").strip()
    while not model_path:
        print("错误: 模型权重路径不能为空")
        model_path = input("请输入模型权重路径: ").strip()
    
    return {
        "ip": ip,
        "model_name": model_name,
        "model_path": model_path
    }

def modify_config(config_data, reference_data, user_input):
    """修改配置文件中的指定值"""
    try:
        # 修改ServerConfig部分
        config_data["ServerConfig"]["httpsEnabled"] = reference_data["ServerConfig"]["httpsEnabled"]
        config_data["ServerConfig"]["interCommTLSEnabled"] = reference_data["ServerConfig"]["interCommTLSEnabled"]
        config_data["ServerConfig"]["ipAddress"] = user_input["ip"]
        config_data["ServerConfig"]["managementIpAddress"] = user_input["ip"]

        # 修改BackendConfig部分
        backend_config = config_data["BackendConfig"]
        ref_backend_config = reference_data["BackendConfig"]

        backend_config["npuDeviceIds"] = ref_backend_config["npuDeviceIds"]
        backend_config["multiNodesInferEnabled"] = ref_backend_config["multiNodesInferEnabled"]
        backend_config["interNodeTLSEnabled"] = ref_backend_config["interNodeTLSEnabled"]

        # 修改ModelDeployConfig部分
        model_deploy_config = backend_config["ModelDeployConfig"]
        ref_model_deploy_config = ref_backend_config["ModelDeployConfig"]

        model_deploy_config["maxSeqLen"] = ref_model_deploy_config["maxSeqLen"]
        model_deploy_config["maxInputTokenLen"] = ref_model_deploy_config["maxInputTokenLen"]

        # 修改ModelConfig部分
        if "ModelConfig" in ref_model_deploy_config and ref_model_deploy_config["ModelConfig"]:
            model_config = model_deploy_config["ModelConfig"][0]
            model_config["modelName"] = user_input["model_name"]
            model_config["modelWeightPath"] = user_input["model_path"]
            model_config["worldSize"] = 8

        # 修改ScheduleConfig部分
        schedule_config = backend_config["ScheduleConfig"]
        ref_schedule_config = ref_backend_config["ScheduleConfig"]

        schedule_config["maxPrefillTokens"] = ref_schedule_config["maxPrefillTokens"]
        schedule_config["maxIterTimes"] = ref_schedule_config["maxIterTimes"]

        return True
    except Exception as e:
        print(f"错误: 修改配置时出错: {str(e)}")
        return False

def main():
    # 配置文件路径
    config_path = "/usr/local/Ascend/mindie/latest/mindie-service/conf/config.json"
    reference_path = "config.json"  # 参考配置文件路径

    # 检查文件是否存在
    if not os.path.exists(config_path):
        print(f"错误: 找不到配置文件: {config_path}")
        return
    if not os.path.exists(reference_path):
        print(f"错误: 找不到参考配置文件: {reference_path}")
        return

    # 获取用户输入
    print("\n=== Mindie服务配置修改工具 ===")
    user_input = get_user_input()

    # 加载配置文件
    config_data = load_json_file(config_path)
    reference_data = load_json_file(reference_path)
    if not config_data or not reference_data:
        return

    # 备份原配置文件
    if not backup_config_file(config_path):
        response = input("无法创建备份，是否继续？[y/N]: ")
        if response.lower() != 'y':
            return

    # 修改配置
    print("\n正在更新配置...")
    if modify_config(config_data, reference_data, user_input):
        # 保存修改后的配置
        if save_json_file(config_path, config_data):
            print("配置更新成功！")
            print(f"主节点服务器IP: {user_input['ip']}")
            print(f"模型名称: {user_input['model_name']}")
            print(f"模型路径: {user_input['model_path']}")
        else:
            print("错误: 保存配置文件失败")
    else:
        print("错误: 更新配置失败")

if __name__ == "__main__":
    main()
