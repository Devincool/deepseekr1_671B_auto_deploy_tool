#!/bin/bash
#
# 作者: 华为山东产业发展与生态部 邱敏
# 描述: NPU网络环境检查工具
#

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BLUE='\033[0;34m'

echo -e "${BLUE}========== 开始网络检查 ==========${NC}\n"

# 检查LLDP信息
echo -e "${GREEN}1. 检查LLDP信息:${NC}"
for i in {0..7}; do
    echo -e "\n设备 $i:"
    hccn_tool -i $i -lldp -g | grep Ifname
done

# 检查链路状态
echo -e "\n${GREEN}2. 检查链路状态:${NC}"
for i in {0..7}; do
    echo -e "\n设备 $i:"
    hccn_tool -i $i -link -g
done

# 检查网络健康状态
echo -e "\n${GREEN}3. 检查网络健康状态:${NC}"
for i in {0..7}; do
    echo -e "\n设备 $i:"
    hccn_tool -i $i -net_health -g
done

# 检查网络检测状态
echo -e "\n${GREEN}4. 检查网络检测状态:${NC}"
for i in {0..7}; do
    echo -e "\n设备 $i:"
    hccn_tool -i $i -netdetect -g
done

# 检查网关信息
echo -e "\n${GREEN}5. 检查网关信息:${NC}"
for i in {0..7}; do
    echo -e "\n设备 $i:"
    hccn_tool -i $i -gateway -g
done

# 检查IP信息
echo -e "\n${GREEN}6. 检查IP信息:${NC}"
for i in {0..7}; do
    echo -e "\n设备 $i:"
    hccn_tool -i $i -ip -g
done

# 设置TLS
echo -e "\n${GREEN}7. 设置TLS:${NC}"
for i in {0..7}; do
    echo -e "\n设备 $i:"
    hccn_tool -i $i -tls -s enable 0
done

# 检查TLS状态
echo -e "\n${GREEN}8. 检查TLS状态:${NC}"
for i in {0..7}; do
    echo -e "\n设备 $i:"
    hccn_tool -i $i -tls -g | grep switch
done

# 添加机器卡间互联检查
check_inter_device_connection() {
    echo -e "\n${GREEN}9. 机器卡间互联检查:${NC}"
    echo -e "${BLUE}请输入目标NPU卡的IP地址 (输入q退出检查):${NC}"
    while true; do
        read -p "IP地址: " target_ip
        if [ "$target_ip" = "q" ]; then
            break
        fi
        
        if [[ ! $target_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}无效的IP地址格式，请重新输入${NC}"
            continue
        fi
        
        echo -e "\n${BLUE}正在检查与 $target_ip 的连接...${NC}"
        for i in {0..7}; do
            echo -e "\n本机设备 $i ping $target_ip:"
            hccn_tool -i $i -ping -g address $target_ip
        done
        
        echo -e "\n${BLUE}是否继续检查其他IP？(输入q退出，输入其他继续)${NC}"
        read -p "选择: " choice
        if [ "$choice" = "q" ]; then
            break
        fi
    done
}

# 主函数
main() {
    # 只在指定--check-connection参数时执行机器卡间互联检查
    if [ "$1" = "--check-connection" ]; then
        check_inter_device_connection
    fi
}

# 执行主函数，传递所有参数
main "$@"

echo -e "\n${BLUE}========== 检查完成 ==========${NC}"
