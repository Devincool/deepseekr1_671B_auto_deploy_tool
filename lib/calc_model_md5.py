#!/usr/bin/env python3
import os
import hashlib
import argparse
from pathlib import Path

def calculate_md5(file_path):
    """计算文件的MD5值"""
    md5_hash = hashlib.md5()
    with open(file_path, "rb") as f:
        # 分块读取文件，避免大文件导致内存问题
        for chunk in iter(lambda: f.read(4096), b""):
            md5_hash.update(chunk)
    return md5_hash.hexdigest()

def find_model_files(directory):
    """查找目录中所有以model开头的文件"""
    results = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.startswith('model'):
                full_path = os.path.join(root, file)
                results.append(full_path)
    return results

def main():
    parser = argparse.ArgumentParser(description='计算指定目录下所有model*文件的MD5值')
    parser.add_argument('directory', nargs='?', default='.', 
                      help='要扫描的目录路径（默认为当前目录）')
    parser.add_argument('-o', '--output', help='输出结果到文件')
    
    args = parser.parse_args()
    
    # 确保目录存在
    if not os.path.exists(args.directory):
        print(f"错误：目录 '{args.directory}' 不存在")
        return

    # 查找所有model文件
    model_files = find_model_files(args.directory)
    
    if not model_files:
        print(f"在 '{args.directory}' 中没有找到以model开头的文件")
        return

    # 计算并存储结果
    results = []
    for file_path in model_files:
        try:
            md5 = calculate_md5(file_path)
            relative_path = os.path.relpath(file_path, args.directory)
            results.append((relative_path, md5))
            print(f"处理: {relative_path}")
        except Exception as e:
            print(f"处理文件 '{file_path}' 时出错: {e}")

    # 输出结果
    output_content = "\n=== MD5计算结果 ===\n"
    for file_path, md5 in sorted(results):
        output_content += f"{file_path}: {md5}\n"

    print(output_content)

    # 如果指定了输出文件，将结果写入文件
    if args.output:
        try:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(output_content)
            print(f"\n结果已保存到: {args.output}")
        except Exception as e:
            print(f"写入输出文件时出错: {e}")

if __name__ == "__main__":
    main() 