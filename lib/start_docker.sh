#!/bin/bash

# 检查参数
if [ "$#" -lt 3 ]; then
    echo "用法: $0 <container_name> <image> <volumes_args>"
    exit 1
fi

CONTAINER_NAME="$1"
IMAGE="$2"
VOLUMES_ARGS="$3"

# 检查是否已存在同名容器
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "错误: 容器 ${CONTAINER_NAME} 已存在"
    exit 1
fi

# 构建docker run命令
CMD="docker run -itd --name ${CONTAINER_NAME}"

# 添加volumes挂载
eval "CMD=\"\$CMD $VOLUMES_ARGS\""

# 添加其他必要参数
CMD="$CMD --net=host --privileged=true --shm-size=500g"
CMD="$CMD --device=/dev/davinci0"
CMD="$CMD --device=/dev/davinci1"
CMD="$CMD --device=/dev/davinci2"
CMD="$CMD --device=/dev/davinci3"
CMD="$CMD --device=/dev/davinci4"
CMD="$CMD --device=/dev/davinci5"
CMD="$CMD --device=/dev/davinci6"
CMD="$CMD --device=/dev/davinci7"
CMD="$CMD --device=/dev/davinci_manager"
CMD="$CMD --device=/dev/devmm_svm"
CMD="$CMD --device=/dev/hisi_hdc"
CMD="$CMD -v /usr/local/Ascend/driver:/usr/local/Ascend/driver"
CMD="$CMD -v /usr/local/Ascend/add-ons/:/usr/local/Ascend/add-ons/"
CMD="$CMD -v /usr/local/sbin/:/usr/local/sbin/"
CMD="$CMD -v /var/log/npu/slog/:/var/log/npu/slog"
CMD="$CMD -v /var/log/npu/profiling/:/var/log/npu/profiling"
CMD="$CMD -v /var/log/npu/dump/:/var/log/npu/dump"
CMD="$CMD -v /var/log/npu/:/usr/slog"
CMD="$CMD -v /etc/hccn.conf:/etc/hccn.conf"

# 添加镜像和命令
CMD="$CMD $IMAGE /bin/bash"

# 执行docker run命令
echo "执行命令: $CMD"
eval "$CMD"

# 检查容器是否成功启动
if [ $? -eq 0 ]; then
    # 等待容器完全启动
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            # 检查容器是否真正就绪
            if docker exec "${CONTAINER_NAME}" true >/dev/null 2>&1; then
                echo "容器 ${CONTAINER_NAME} 启动成功并就绪"
                exit 0
            fi
        fi
        echo "等待容器就绪... ($attempt/$max_attempts)"
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echo "错误: 容器启动后未能就绪"
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1
    exit 1
else
    echo "错误: 容器 ${CONTAINER_NAME} 启动失败"
    exit 1
fi