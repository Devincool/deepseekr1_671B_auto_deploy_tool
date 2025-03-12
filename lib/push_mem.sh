#!/bin/bash
# 
# 作者: 华为山东产业发展与生态部 邱敏
# 描述: 模型文件内存预热工具
#

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取当前目录下的.safetensors文件数量和命名格式
get_model_info() {
    # 获取第一个.safetensors文件的名称
    local first_file=$(ls *.safetensors 2>/dev/null | head -n 1)
    if [ -z "$first_file" ]; then
        echo -e "${RED}错误: 当前目录下没有找到.safetensors文件${NC}"
        exit 1
    fi

    # 计算文件总数
    local total_files=$(ls *.safetensors 2>/dev/null | wc -l)
    
    # 分析文件命名格式
    # 示例: quant_model_weight_w8a8_dynamic-00001-of-00157.safetensors
    local prefix=$(echo "$first_file" | sed -E 's/-[0-9]+-of-[0-9]+\.safetensors$//')
    local total_parts=$(echo "$first_file" | grep -oE 'of-[0-9]+' | grep -oE '[0-9]+')
    # 获取编号的长度（例如：00001 的长度为 5）
    local number_format=5  # 固定使用5位数字

    echo "$prefix" "$total_parts" "$number_format"
}

# 主函数
main() {
    # 获取模型文件信息
    read prefix total_parts number_format <<< $(get_model_info)
    
    echo -e "${BLUE}检测到模型文件信息:${NC}"
    echo -e "文件前缀: ${GREEN}$prefix${NC}"
    echo -e "文件总数: ${GREEN}$total_parts${NC}"
    echo -e "编号格式: ${GREEN}%0${number_format}d${NC}"

    # 构建文件名格式
    local file_format="${prefix}-%0${number_format}d-of-${total_parts}.safetensors"
    
    echo -e "\n${BLUE}开始预热模型文件...${NC}"
    
    # 持续循环读取文件以保持在内存中
    echo -e "${BLUE}将持续循环读取文件以保持在内存中...${NC}"
    
    while true; do
        echo -e "\n${BLUE}开始新一轮预热循环${NC}"
        for ((i=1; i<=$total_parts; i++)); do
            # 使用printf格式化文件名
            file=$(printf "$file_format" $i)
            echo -e "${GREEN}读取文件 ($i/$total_parts): $file${NC}"
            cat "$file" > /dev/null
            sleep 3
        done
    done
}

# 执行主函数
main