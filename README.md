# 昇腾MindIE多机集群推理自动化部署工具（支持Deepseek R1/V3满血版）

[English Version](README.en.md)

## 项目介绍

**功能特点:**
- 支持离线使用
- 支持昇腾多机/集群部署（当前不支持单机部署）
- 支持 MindIE 所有支持模型列表，不局限于 DeepSeek v3/r1
- 全自动化部署，预计部署时长 5-10 分钟

> 注：工具更新频率较高，建议收藏。

## 快速开始

### 1. 克隆仓库
```bash
git clone https://modelers.cn/devincool/deepseekr1_671B_auto_deploy_tool.git
```

### 2. 前置准备

部署前需要准备以下资源：

1. **驱动和 Docker 镜像**
   - 配套驱动和 mindie 2.0.T3/T3.1 docker 镜像下载：
   - 👉 [mindie2.0.T3 资源包](https://modelers.cn/models/LiuZhiwen/mindie2.0.T3)

2. **模型权重**
   - DeepSeek V3（需要 4 机部署，800I-A2-64G/800T-A2-64G）：
   - 👉 [DeepSeek V3 权重](https://modelers.cn/models/MindIE/deepseekv3)
   
   - DeepSeek R1-W8A8（需要 2 机部署，800I-A2-64G/800T-A2-64G）：
   - 👉 [DeepSeek R1 权重](https://modelers.cn/models/State_Cloud/DeepSeek-R1-bf16-hfd-w8a8)

> 注：lib里有个小工具trans_quote_to_real.sh，可以丢到openmind_hub下载的缓存路径下，执行后把软链接变成实体文件方便容器使用。

## 部署方法

### 方法一：全自动部署（推荐）

#### 1. 配置部署参数
编辑 `deploy_config.json` 文件：

> 注意：节点数必须为 2 的倍数（1、2、4、8...）

```json
{
    "master_ip": "192.168.1.100",        # 主节点IP
    "nodes": [                           # 所有节点IP列表（包含主节点）
        "192.168.1.100",
        "192.168.1.101",
        "192.168.1.102",
        "192.168.1.103"
    ],
    "model_name": "deepseekr1",         # 模型名称
    "model_path": "/model/deepseekr1_w8a8", # 容器中的模型路径，需要可以通过volums字段中挂载路径访问到
    "world_size": 32,                   # 总的设备数量
    "docker": {
        "image": "your_mindie_image_id", # Mindie Docker镜像 ID
        "volumes": {                     # docker 启动挂载配置
            "/data/model": "/model",    # /data/model 为宿主机目录  /model为容器内挂载的目录地址
        }
    },
    "ssh": {                            # SSH连接配置
        "username": "root",             # SSH用户名
        "use_key": true,               # 是否使用密钥认证
        "key_path": "~/.ssh/id_rsa",   # SSH密钥路径
        "password": "",                 # 如果不使用密钥，则提供密码
        "port": 22                     # 如果修改过ssh默认端口可以配置
    }
}
```

#### 2. 执行部署

1. 配置文件准备
   ```bash
   # 复制并修改配置文件
   cp deploy_config.json.example deploy_config.json
   vim deploy_config.json
   ```

> 注意：配置好后把工具包往所有节点都拷贝一份，每台机器都需要执行部署脚本。

2. 执行部署
   ```bash
   # 启动部署
   bash deploy.sh
   ```

3. 清理环境
   ```bash
   # 清理之前的容器和进程
   bash deploy.sh --cleanup

**部署流程：**
1. ✅ 检查网络环境
2. ✅ 生成 rank 表配置
3. ✅ 启动 Docker 容器
4. ✅ 配置环境变量
5. ✅ 修改 Mindie 服务配置
6. ✅ 执行内存预热
7. ✅ 启动服务

**重要提示：**
- 主节点需要最先启动服务
- 从节点需要在主节点启动后 1 分钟内启动
- 请按照提示确认每个步骤是否执行成功

#### 全自动部署工具FAQ

1. **执行脚本提示master_ip字段不存在**
   ```bash
   # 检查jq工具是否正常安装
   jq -h
   
   # 如果未安装jq，可以通过以下命令安装：
   # Ubuntu/Debian系统：
   apt-get update && apt-get install jq
   
   # CentOS/RHEL系统：
   yum install jq
   ```

2. **执行脚本提示pip包安装失败**
   当前预制的pip包都是paramiko及其依赖包，操作系统不同、python版本不同可能不适用，请自行安装。
   ```bash
   # 安装paramiko及其依赖包
   pip install paramiko -i https://pypi.tuna.tsinghua.edu.cn/simple
   ```
   然后注释掉deploy.sh脚本中pip安装的paramiko相关行。

3. **启动服务后报错**
   可以按照以下步骤进行故障排查：
   ```bash
   # 1. 进入docker容器
   docker exec -it xxxx bash
   
   # 2. 进入服务目录
   cd /usr/local/Ascend/mindie/latest/mindie-service/
   ```
   
   日志查看路径：
   - 服务日志：当前目录下的 `output_xxx.log`
   - 算子库日志：`~/atb/log`
   - 加速库日志：`~/mindie/log/debug`
   - MindIE LLM日志：`~/mindie/log/debug`
   - MindIE Service日志：`~/mindie/log/debug`

### 方法二：半自动部署（按需选择）

如果需要更细粒度的控制，可以按以下步骤手动执行：

#### 1. 网络环境检查
```bash
./lib/auto_check.sh
```

#### 2. 生成 rank 表配置
```bash
pip install -r requirements.txt
python3 lib/generate_ranktable_semiauto.py
```

> 注意：
> - 生成的 rank_table_file.json 需自行放置到容器中 /usr/local/Ascend/mindie/latest/mindie-service/rank_table_file.json
> - 脚本需要SSH访问各个服务器，支持密码认证和密钥认证两种方式：
>   - 如果已配置SSH密钥，选择"y"使用密钥认证
>   - 否则选择"N"使用密码认证

**以下在docker镜像中操作，deepseekr1需要用mindie2.0.t3版本的docker镜像：**
#### 3. 配置环境变量
```bash
./lib/add_env_settings.sh <master_ip> <container_ip> <world_size>
source ~/.bashrc
```

#### 4. 修改 Mindie 服务配置
```bash
python3 lib/modify_mindie_config_semiauto.py
```

#### 5. 内存预热（可选）
```bash
cd $MODEL_PATH
nohup bash lib/push_mem.sh > output_mem.log &
```

#### 6. 启动服务
```bash
cd /usr/local/Ascend/mindie/latest/mindie-service/
nohup ./bin/mindieservice_daemon > output_$(date +"%Y%m%d%H%M").log 2>&1 &
```

## 注意事项

1. ⚠️ 确保所有脚本具有执行权限
2. ⚠️ 在执行 add_env_settings.sh 前，请确保了解 master_ip 和 world_size 的正确值
3. ⚠️ 生成 rank 表时需要能够通过 SSH 访问所有服务器
4. ⚠️ 内存预热可能需要较长时间，请耐心等待
5. ⚠️ 建议按照顺序执行各个步骤，确保配置的正确性

## 常见问题

1. **SSH 连接失败**
   - 检查用户名和服务器 IP 地址是否正确
   - 确认目标机器SSH服务是否运行
   - 验证认证方式（密钥/密码）是否正确
   - 
2. **权限问题**
   - 确保脚本有执行权限

3. **环境变量未生效**
   - 记得执行 `source ~/.bashrc`

4. **网络检查失败**
   - 检查网络连接和 NPU 设备状态
   - 查看服务日志
   - 确认端口是否被占用

## 贡献鸣谢

感谢以下同事的贡献：
- 姚育平
- 刘志文
- 黄海宽（中移齐鲁创新院）
- 高俊秀（中移齐鲁创新院）
