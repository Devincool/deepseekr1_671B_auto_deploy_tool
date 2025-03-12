#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置文件
CONFIG_FILE="deploy_config.json"
CONTAINER_CACHE=".container_cache"  # 容器缓存文件

# 检查是否在Docker环境中
in_docker_env() {
    [ -f "/.dockerenv" ]
}

# 检查依赖
check_dependencies() {
    local deps=("jq" "docker")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            if [ $dep = "jq" ]; then
                echo -e "${RED}错误: 未找到命令 '$dep'${NC}"
                echo "请先安装必要的依赖"
                exit 1
            fi
        fi
    done
}

# 验证配置文件
validate_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: 未找到配置文件 $CONFIG_FILE${NC}"
        exit 1
    fi
    
    # 检查必要字段
    local required_fields=("master_ip" "nodes" "model_name" "model_path" "docker.image")
    for field in "${required_fields[@]}"; do
        if [ -z "$(jq -r ".$field" "$CONFIG_FILE" 2>/dev/null)" ]; then
            echo -e "${RED}错误: 配置文件缺少必要字段 '$field'${NC}"
            exit 1
        fi
    done

    # 检查SSH端口配置
    local ssh_port=$(jq -r '.ssh.port' "$CONFIG_FILE")
    if [ "$ssh_port" = "null" ]; then
        echo -e "${BLUE}注意: 未指定SSH端口，将使用默认端口22${NC}"
    fi

    # 增加SSH认证配置检查
    local use_key=$(jq -r '.ssh.use_key' "$CONFIG_FILE")
    local key_path=$(jq -r '.ssh.key_path' "$CONFIG_FILE")
    local password=$(jq -r '.ssh.password' "$CONFIG_FILE")
    
    if [ "$use_key" = "true" ]; then
        if [ -z "$key_path" ] || [ "$key_path" = "null" ]; then
            echo -e "${RED}错误: 使用SSH密钥认证但未指定密钥路径${NC}"
            exit 1
        fi
        # 展开路径中的~
        key_path=$(eval echo "$key_path")
        if [ ! -f "$key_path" ]; then
            echo -e "${RED}错误: SSH密钥文件不存在: $key_path${NC}"
            echo -e "${BLUE}请检查：${NC}"
            echo -e "1. 密钥文件路径是否正确"
            echo -e "2. 密钥文件权限是否正确 (建议: chmod 600 $key_path)"
            exit 1
        fi
        # 检查密钥文件权限
        local key_perms=$(stat -c %a "$key_path")
        if [ "$key_perms" != "600" ]; then
            echo -e "${RED}警告: SSH密钥文件权限不正确 ($key_perms)${NC}"
            echo -e "${BLUE}建议执行: chmod 600 $key_path${NC}"
        fi
    else
        if [ -z "$password" ] || [ "$password" = "null" ]; then
            echo -e "${RED}错误: 使用密码认证但未提供密码${NC}"
            exit 1
        fi
    fi
}

# 检查必要文件
check_files() {
    local required_files=(
        "lib/auto_check.sh"
        "lib/add_env_settings.sh"
        "lib/generate_ranktable.py"
        "lib/modify_mindie_config.py"
        "lib/push_mem.sh"
        "resources/paramiko-3.5.1-py3-none-any.whl"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo -e "${RED}错误: 缺少必要文件 $file${NC}"
            exit 1
        fi
        # 添加执行权限
        chmod +x "$file" 2>/dev/null
    done
}

# 添加容器管理相关函数
cleanup_previous_container() {
    if [ ! -f "$CONTAINER_CACHE" ]; then
        return 0
    fi
    
    local prev_container=$(cat "$CONTAINER_CACHE")
    if [ -n "$prev_container" ]; then
        echo -e "${BLUE}发现之前的容器: $prev_container${NC}"
        if docker ps -a --format '{{.Names}}' | grep -q "^${prev_container}$"; then
            echo -e "${BLUE}正在停止并删除之前的容器...${NC}"
            if ! docker stop "$prev_container"; then
                echo -e "${RED}停止容器失败${NC}"
                return 1
            fi
            
            # 等待容器完全停止
            while docker ps --format '{{.Names}}' | grep -q "^${prev_container}$"; do
                echo -e "${BLUE}等待容器停止...${NC}"
                sleep 1
            done
            
            if ! docker rm "$prev_container"; then
                echo -e "${RED}删除容器失败${NC}"
                return 1
            fi
            echo -e "${GREEN}之前的容器已清理${NC}"
        fi
    fi
    return 0
}

wait_for_container_ready() {
    local container_name="$1"
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            # 检查容器是否真正就绪
            if docker exec "$container_name" true >/dev/null 2>&1; then
                echo -e "${GREEN}容器已就绪${NC}"
                return 0
            fi
        fi
        echo -e "${BLUE}等待容器就绪... ($attempt/$max_attempts)${NC}"
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}等待容器就绪超时${NC}"
    return 1
}

# 在文件开头添加错误处理函数
cleanup_and_exit() {
    local exit_code=$1
    local error_msg=$2
    local container_name=$([ -f "$CONTAINER_CACHE" ] && cat "$CONTAINER_CACHE")
    
    echo -e "${RED}错误: $error_msg${NC}"
    
    # 清理容器
    if [ -n "$container_name" ]; then
        echo -e "${BLUE}清理容器: $container_name${NC}"
        docker rm -f "$container_name" >/dev/null 2>&1
    fi
    
    # 清理内存预热进程
    if ps aux | grep -v grep | grep push_mem.sh > /dev/null; then
        echo -e "${BLUE}清理内存预热进程...${NC}"
        pkill -f push_mem.sh
    fi
    
    # 清理服务进程
    if ps aux | grep -v grep | grep mindieservice_daemon > /dev/null; then
        echo -e "${BLUE}清理服务进程...${NC}"
        pkill -f mindie_llm_back
        sync; echo 3 > /proc/sys/vm/drop_caches
    fi
    
    exit $exit_code
}

# 启动Docker容器并执行部署
start_docker_and_deploy() {
    local image=$(jq -r '.docker.image' "$CONFIG_FILE")
    local model_path=$(jq -r '.model_path' "$CONFIG_FILE")
    local container_name="npu_deploy_$(date +%s)"
    
    # 清理之前的容器
    cleanup_previous_container || cleanup_and_exit 1 "清理之前的容器失败"
    
    echo -e "${BLUE}启动Docker容器...${NC}"
    
    # 从配置文件获取volumes配置
    local volumes_json=$(jq -r '.docker.volumes' "$CONFIG_FILE")
    local volumes_args=""
    
    # 将volumes配置转换为-v参数
    while IFS="=" read -r host_path container_path; do
        # 移除引号和大括号
        host_path=$(echo "$host_path" | tr -d '"' | tr -d '{' | tr -d '}' | tr -d ',')
        container_path=$(echo "$container_path" | tr -d '"' | tr -d '{' | tr -d '}' | tr -d ',')
        if [ ! -z "$host_path" ] && [ ! -z "$container_path" ]; then
            volumes_args="$volumes_args -v $host_path:$container_path"
        fi
    done < <(echo "$volumes_json" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"')
    
    # 调用start_docker.sh脚本，传递volumes参数
    chmod a+x lib/start_docker.sh
    ./lib/start_docker.sh "$container_name" "$image" "$volumes_args"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: Docker容器启动失败${NC}"
        exit 1
    fi
    
    # 等待容器就绪
    wait_for_container_ready "$container_name" || {
        docker rm -f "$container_name" >/dev/null 2>&1
        cleanup_and_exit 1 "容器未能正常启动"
    }
    
    # 记录容器名称到缓存文件
    echo "$container_name" > "$CONTAINER_CACHE"
    
    echo -e "${GREEN}容器启动成功: $container_name${NC}"
    
    # 在容器中创建工作目录和mindie目录
    echo -e "${BLUE}创建容器工作目录...${NC}"
    docker exec "$container_name" mkdir -p /workspace
    docker exec "$container_name" mkdir -p /usr/local/Ascend/mindie/latest/mindie-service/
    
    # 复制必要文件到容器
    echo -e "${BLUE}复制配置文件到容器...${NC}"
    docker cp "$CONFIG_FILE" "$container_name:/workspace/"
    docker cp . "$container_name:/workspace/"
    docker cp /usr/bin/hostname "$container_name:/usr/bin/"
    
    # 复制rank表到指定目录
    if [ -f "rank_table_file.json" ]; then
        echo -e "${BLUE}复制rank表到容器...${NC}"
        docker cp rank_table_file.json "$container_name:/usr/local/Ascend/mindie/latest/mindie-service/"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}rank表复制成功${NC}"
        else
            echo -e "${RED}错误: rank表复制失败${NC}"
            cleanup_and_exit 1 "rank表复制失败"
        fi
    else
        echo -e "${RED}错误: 未找到rank表文件${NC}"
        cleanup_and_exit 1 "rank表文件不存在"
    fi
    
    # 在容器中执行部署流程
    echo -e "${BLUE}开始执行部署流程...${NC}"
    if ! docker exec -it "$container_name" bash -l -c "cd /workspace && chmod +x deploy.sh && ./deploy.sh --in-container"; then
        echo -e "${RED}错误: 容器内部署失败${NC}"
        echo -e "${BLUE}清理容器...${NC}"
        docker rm -f "$container_name" >/dev/null 2>&1
        exit 1
    fi

    # 退出容器重进以达成刷新环境变量的目的
    echo -e "${BLUE}开始启动服务...${NC}"
    if ! docker exec -it "$container_name" bash -l -c "cd /workspace && chmod +x deploy.sh && ./deploy.sh --start-service"; then
        echo -e "${RED}错误: 容器内启动服务失败${NC}"
        echo -e "${BLUE}清理容器...${NC}"
        docker rm -f "$container_name" >/dev/null 2>&1
        exit 1
    fi
}
    
# 使用Python读取配置和获取IP
read_config() {
    python3 -c "
import json

def format_nodes(nodes):
    if isinstance(nodes, list):
        return '\\n'.join(nodes)
    return nodes

with open('$CONFIG_FILE') as f:
    config = json.load(f)
    value = config.get('$1')
    if '$1' == 'nodes':
        print(format_nodes(value))
    else:
        print(value)
"
}

# 容器内部署流程
deploy_in_container() {
    echo -e "${BLUE}=== 开始容器内部署 ===${NC}"
    
    # 5. 配置环境变量
    echo -e "\n${GREEN}[4/8] 配置环境变量...${NC}"
    
    # 获取IP和配置
    nodes=$(read_config "nodes")
    current_ip=$(hostname -I | awk -v nodes="$nodes" '
BEGIN {
    n = split(nodes, node_array, "\n")
}
{
    for(i=1; i<=NF; i++) {
        for(j=1; j<=n; j++) {
            if ($i == node_array[j]) {
                print $i
                exit
            }
        }
    }
}')

    if [ -z "$current_ip" ]; then
        echo -e "${RED}错误: 未能在nodes列表中找到匹配的本机IP地址${NC}"
        exit 1
    fi
    world_size=$(read_config "world_size") || cleanup_and_exit 1 "获取world_size失败"
    master_ip=$(read_config "master_ip") || cleanup_and_exit 1 "获取master_ip失败"
    
    chmod a+x lib/add_env_settings.sh
    ./lib/add_env_settings.sh "$master_ip" "$current_ip" "$world_size" || cleanup_and_exit 1 "环境变量配置失败"
    
    # 6. 修改Mindie服务配置
    echo -e "\n${GREEN}[5/8] 修改Mindie服务配置...${NC}"

    # 从配置文件获取参数
    model_name=$(read_config "model_name")
    model_path=$(read_config "model_path")

    # 构建命令行参数
    cmd="python3 lib/modify_mindie_config.py"
    cmd="$cmd --master-ip $master_ip"
    cmd="$cmd --model-name $model_name"
    cmd="$cmd --model-path $model_path"
    cmd="$cmd --world-size $world_size"

    # 执行配置修改
    eval "$cmd" || cleanup_and_exit 1 "Mindie服务配置修改失败"
    
    # 7. 内存预热
    echo -e "\n${GREEN}[6/8] 执行内存预热...${NC}"
    # 从配置文件获取模型路径
    model_path=$(read_config "model_path") || cleanup_and_exit 1 "获取model_path失败"
    
    if [ -d "$model_path" ]; then
        # 复制预热脚本到模型目录
        cp lib/push_mem.sh "$model_path/" || cleanup_and_exit 1 "复制预热脚本失败"
        
        # 切换到模型目录并执行预热
        current_dir=$(pwd)
        cd "$model_path" || cleanup_and_exit 1 "切换到模型目录失败"
        echo -e "${BLUE}开始在 $model_path 目录下执行内存预热...${NC}"
        nohup bash push_mem.sh > output_mem.log 2>&1 &
        cd "$current_dir"
        
        # 等待预热脚本启动
        sleep 2
        ps -ef | grep push_mem.sh  || cleanup_and_exit 1 "内存预热进程启动失败"
    else
        echo -e "${RED}警告: 模型目录不存在: $model_path${NC}"
        echo -e "${RED}跳过内存预热${NC}"
    fi
}

start_service() {
    # 8. 启动服务
    echo -e "\n${GREEN}[7/8] 启动服务...${NC}"
    model_path=$(read_config "model_path") || {
        echo -e "${RED}错误: 获取model_path失败${NC}"
        exit 1
    }

    # 获取IP和配置
    nodes=$(read_config "nodes")
    current_ip=$(hostname -I | awk -v nodes="$nodes" '
BEGIN {
    n = split(nodes, node_array, "\n")
}
{
    for(i=1; i<=NF; i++) {
        for(j=1; j<=n; j++) {
            if ($i == node_array[j]) {
                print $i
                exit
            }
        }
    }
}')

    if [ -z "$current_ip" ]; then
        echo -e "${RED}错误: 未能在nodes列表中找到匹配的本机IP地址${NC}"
        exit 1
    fi
    master_ip=$(read_config "master_ip") || {
        echo -e "${RED}错误: 获取master_ip失败${NC}"
        exit 1
    }
    
    world_size=$(read_config "world_size") || {
        echo -e "${RED}错误: 获取world_size失败${NC}"
        exit 1
    } 
    # 修改模型权重路径config权限
    config_file="$model_path/config.json"
    if [ -f "$config_file" ]; then
        echo -e "${BLUE}修改模型配置文件权限: $config_file${NC}"
        chmod -R 640 $model_path
        chmod 750 "$config_file"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}配置文件权限修改成功${NC}"
        else
            echo -e "${RED}警告: 配置文件权限修改失败${NC}"
        fi
    else
        echo -e "${RED}警告: 未找到模型配置文件: $config_file${NC}"
    fi
    

    if [ "$current_ip" = "$master_ip" ]; then
        echo -e "${BLUE}当前机器是主节点 ($current_ip)${NC}"
        echo -e "${BLUE}注意: 主节点应该最先启动服务${NC}"
    else
        echo -e "${BLUE}当前机器是从节点 ($current_ip)${NC}"
        echo -e "${BLUE}注意: 请确保主节点 ($master_ip) 已经启动服务${NC}"
    fi

    # 修改rank_table_file.json权限
    chmod 640 /usr/local/Ascend/mindie/latest/mindie-service/rank_table_file.json
    
    # 询问是否启动服务
    while true; do
        read -p "请确保启动服务前所有节点已运行到这一步。是否现在启动服务? (y/n): " yn
        case $yn in
            [Yy]* )
                echo -e "${BLUE}正在启动服务...${NC}"

                if [ -z "$ASCEND_RT_VISIBLE_DEVICES" ]; then
                    echo -e "${RED}~/.bashrc未正确加载，请进入容器手动启动服务${NC}"
                    echo -e "cd /usr/local/Ascend/mindie/latest/mindie-service/"
                    echo -e "nohup ./bin/mindieservice_daemon > output_\$(date +\"%Y%m%d%H%M\").log 2>&1 &"
                else
                    echo -e "${GREEN}~/.bashrc已正确加载 ${NC}"
                fi

                cd /usr/local/Ascend/mindie/latest/mindie-service/
                nohup ./bin/mindieservice_daemon > output_$(date +"%Y%m%d%H%M").log 2>&1 &
                
                # 等待服务启动
                sleep 5
                if ps aux | grep -v grep | grep mindieservice_daemon > /dev/null; then
                    echo -e "${GREEN}服务已成功启动${NC}"
                else
                    echo -e "${RED}警告: 服务可能未正常启动，请检查日志${NC}"
                fi
                cd -
                break;;
            [Nn]* )
                echo -e "${BLUE}跳过服务启动${NC}"
                echo -e "${BLUE}您可以稍后手动启动服务:${NC}"
                echo -e "cd /usr/local/Ascend/mindie/latest/mindie-service/"
                echo -e "nohup ./bin/mindieservice_daemon > output_\$(date +\"%Y%m%d%H%M\").log 2>&1 &"
                break;;
            * )
                echo "请输入 y 或 n";;
        esac
    done
    
    echo -e "\n${GREEN}部署完成!${NC}"
    if [ "$current_ip" = "$master_ip" ]; then
        echo -e "${BLUE}提示: 主节点服务启动后，请在1分钟内启动所有从节点服务${NC}"
    else
        echo -e "${BLUE}提示: 从节点服务应该在主节点服务启动后1分钟内启动${NC}"
    fi
    echo -e "${BLUE}请检查各个步骤的输出确保部署成功${NC}"
}

# 主函数
main() {
    # 设置错误处理
    set -e
    trap 'cleanup_and_exit $? "执行过程中发生错误"' ERR
    
    echo -e "${BLUE}=== NPU集群自动化部署工具 ===${NC}"
    
    if [ "$1" = "--in-container" ]; then
        check_files || cleanup_and_exit 1 "必要文件检查失败"
        deploy_in_container
    elif [ "$1" = "--start-service" ]; then
        start_service
    elif [ "$1" = "--cleanup" ]; then
        cleanup_previous_container
        exit 0
    else
        check_dependencies || cleanup_and_exit 1 "依赖检查失败"
        validate_config || cleanup_and_exit 1 "配置验证失败"
        
        # 1. 执行网络检查
        echo -e "\n${GREEN}[1/8] 执行网络环境检查...${NC}"
        chmod a+x lib/auto_check.sh
        ./lib/auto_check.sh || cleanup_and_exit 1 "网络检查失败"
        
        # 2. 安装依赖并生成rank表
        echo -e "\n${GREEN}[2/8] 生成rank表配置...${NC}"
        
        # Python和pip检查
        command -v python3 >/dev/null 2>&1 || cleanup_and_exit 1 "未找到python3命令"
        command -v pip3 >/dev/null 2>&1 || cleanup_and_exit 1 "未找到pip3命令"
        
        # 安装paramiko
        echo -e "${BLUE}安装SSH连接所需的paramiko库...${NC}"
        pip3 install paramiko -i https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple || cleanup_and_exit 1 "paramiko安装失败"
        
        # 从配置文件获取节点信息和SSH配置
        nodes=$(jq -r '.nodes | join(",")' "$CONFIG_FILE")
        username=$(jq -r '.ssh.username' "$CONFIG_FILE")
        use_key=$(jq -r '.ssh.use_key' "$CONFIG_FILE")
        key_path=$(jq -r '.ssh.key_path' "$CONFIG_FILE")
        password=$(jq -r '.ssh.password' "$CONFIG_FILE")
        ssh_port=$(jq -r '.ssh.port' "$CONFIG_FILE")

        # 构建命令行参数
        cmd="python3 lib/generate_ranktable.py --nodes $nodes --username $username"
        
        # 添加端口参数
        if [ "$ssh_port" != "null" ]; then
            cmd="$cmd --port $ssh_port"
        fi

        if [ "$use_key" = "true" ]; then
            cmd="$cmd --use-key"
            # 如果指定了密钥路径，确保它存在
            if [ ! -z "$key_path" ] && [ "$key_path" != "null" ]; then
                key_path=$(eval echo "$key_path")  # 展开路径中的~
                if [ ! -f "$key_path" ]; then
                    echo -e "${RED}错误: SSH密钥文件不存在: $key_path${NC}"
                    exit 1
                fi
            fi
        else
            if [ -z "$password" ] || [ "$password" = "null" ]; then
                echo -e "${RED}错误: 未使用SSH密钥但未提供密码${NC}"
                exit 1
            fi
            cmd="$cmd --password $password"
        fi

        # 执行rank表生成
        eval "$cmd" || cleanup_and_exit 1 "rank表生成失败"
        
        # 3. 启动Docker容器
        echo -e "\n${GREEN}[3/8] 启动Docker容器...${NC}"
        start_docker_and_deploy || cleanup_and_exit 1 "Docker容器启动或部署失败"
    fi
}

# 执行主函数
main "$@" 