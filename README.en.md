# Ascend MindIE Multi-Node Cluster Inference Auto-Deployment Tool (Supporting Deepseek R1/V3 Full Version)

## Project Introduction

**Features:**
- Supports offline usage
- Supports Ascend multi-node/cluster deployment (currently does not support single-node deployment)
- Supports all MindIE-compatible models, not limited to DeepSeek v3/r1
- Fully automated deployment, estimated deployment time 5-10 minutes

> Note: The tool is frequently updated, bookmarking is recommended.

## Quick Start

### 1. Clone Repository
```bash
git clone https://modelers.cn/devincool/deepseekr1_671B_auto_deploy_tool.git
```

### 2. Prerequisites

The following resources are required before deployment:

1. **Drivers and Docker Image**
   - Download compatible drivers and mindie 2.0.T3/T3.1 docker image:
   - 👉 [mindie2.0.T3 Resource Package](https://modelers.cn/models/LiuZhiwen/mindie2.0.T3)

2. **Model Weights**
   - DeepSeek V3 (requires 4 nodes, 800I-A2-64G/800T-A2-64G):
   - 👉 [DeepSeek V3 Weights](https://modelers.cn/models/MindIE/deepseekv3)
   
   - DeepSeek R1-W8A8 (requires 2 nodes, 800I-A2-64G/800T-A2-64G):
   - 👉 [DeepSeek R1 Weights](https://modelers.cn/models/State_Cloud/DeepSeek-R1-bf16-hfd-w8a8)

> Note: There's a utility script `trans_quote_to_real.sh` in the lib directory that can be placed in the openmind_hub download cache path to convert symbolic links to real files for container use.

## Deployment Methods

### Method 1: Fully Automated Deployment (Recommended)

#### 1. Configure Deployment Parameters
Edit the `deploy_config.json` file:

> Note: Number of nodes must be a power of 2 (1, 2, 4, 8...)

```json
{
    "master_ip": "192.168.1.100",        # Master node IP
    "nodes": [                           # List of all node IPs (including master)
        "192.168.1.100",
        "192.168.1.101",
        "192.168.1.102",
        "192.168.1.103"
    ],
    "model_name": "deepseekr1",         # Model name
    "model_path": "/model/deepseekr1_w8a8", # Model path in container, must be accessible via volumes mount
    "world_size": 32,                   # Total number of devices
    "docker": {
        "image": "your_mindie_image_id", # Mindie Docker image ID
        "volumes": {                     # Docker volume mount configuration
            "/data/model": "/model",    # /data/model is host directory, /model is container mount point
        }
    },
    "ssh": {                            # SSH connection configuration
        "username": "root",             # SSH username
        "use_key": true,               # Whether to use key authentication
        "key_path": "~/.ssh/id_rsa",   # SSH key path
        "password": "",                 # Password if not using key authentication
        "port": 22                     # Custom SSH port if modified
    }
}
```

#### 2. Execute Deployment

1. Prepare Configuration File
   ```bash
   # Copy and modify config file
   cp deploy_config.json.example deploy_config.json
   vim deploy_config.json
   ```

> Note: After configuration, copy the tool package to all nodes, deployment script needs to be executed on each machine.

2. Execute Deployment
   ```bash
   # Start deployment
   bash deploy.sh
   ```

3. Clean Environment
   ```bash
   # Clean up previous containers and processes
   bash deploy.sh --cleanup
   ```

**Deployment Process:**
1. ✅ Check network environment
2. ✅ Generate rank table configuration
3. ✅ Launch Docker containers
4. ✅ Configure environment variables
5. ✅ Modify Mindie service configuration
6. ✅ Execute memory warmup
7. ✅ Start service

**Important Notes:**
- Master node must start service first
- Worker nodes must start within 1 minute after master node
- Please confirm successful execution of each step as prompted

#### Automated Deployment Tool FAQ

1. **Script reports master_ip field not found**
   ```bash
   # Check if jq tool is properly installed
   jq -h
   
   # If jq is not installed, install using:
   # Ubuntu/Debian:
   apt-get update && apt-get install jq
   
   # CentOS/RHEL:
   yum install jq
   ```

2. **Script reports pip package installation failure**
   The pre-packaged pip packages are paramiko and its dependencies, which may not be compatible with different OS/Python versions. Please install manually.
   ```bash
   # Install paramiko and dependencies
   pip install paramiko -i https://pypi.tuna.tsinghua.edu.cn/simple
   ```
   Then comment out the paramiko-related pip installation lines in deploy.sh script.

3. **Service reports error after startup**
   Follow these troubleshooting steps:
   ```bash
   # 1. Enter docker container
   docker exec -it xxxx bash
   
   # 2. Enter service directory
   cd /usr/local/Ascend/mindie/latest/mindie-service/
   ```
   
   Log file locations:
   - Service logs: `output_xxx.log` in current directory
   - Operator library logs: `~/atb/log`
   - Acceleration library logs: `~/mindie/log/debug`
   - MindIE LLM logs: `~/mindie/log/debug`
   - MindIE Service logs: `~/mindie/log/debug`

### Method 2: Semi-Automated Deployment (Optional)

For finer control, follow these manual steps:

#### 1. Check Network Environment
```bash
./lib/auto_check.sh
```

#### 2. Generate Rank Table Configuration
```bash
pip install -r requirements.txt
python3 lib/generate_ranktable_semiauto.py
```

> Note:
> - Generated rank_table_file.json needs to be manually placed at /usr/local/Ascend/mindie/latest/mindie-service/rank_table_file.json in container
> - Script requires SSH access to all servers, supports both password and key authentication:
>   - Choose "y" for key authentication if SSH keys are configured
>   - Choose "N" for password authentication otherwise

**Following operations are performed in docker container, deepseekr1 requires mindie2.0.t3 version docker image:**
#### 3. Configure Environment Variables
```bash
./lib/add_env_settings.sh <master_ip> <container_ip> <world_size>
source ~/.bashrc
```

#### 4. Modify Mindie Service Configuration
```bash
python3 lib/modify_mindie_config_semiauto.py
```

#### 5. Memory Warmup (Optional)
```bash
cd $MODEL_PATH
nohup bash lib/push_mem.sh > output_mem.log &
```

#### 6. Start Service
```bash
cd /usr/local/Ascend/mindie/latest/mindie-service/
nohup ./bin/mindieservice_daemon > output_$(date +"%Y%m%d%H%M").log 2>&1 &
```

## Important Notes

1. ⚠️ Ensure all scripts have execution permissions
2. ⚠️ Verify correct master_ip and world_size values before executing add_env_settings.sh
3. ⚠️ SSH access to all servers is required for rank table generation
4. ⚠️ Memory warmup may take considerable time, please be patient
5. ⚠️ Execute steps in order to ensure correct configuration

## Common Issues

1. **SSH Connection Failure**
   - Verify username and server IP address
   - Confirm SSH service is running on target machine
   - Verify authentication method (key/password)
   
2. **Permission Issues**
   - Ensure scripts have execution permissions

3. **Environment Variables Not Taking Effect**
   - Remember to execute `source ~/.bashrc`

4. **Network Check Failure**
   - Check network connectivity and NPU device status
   - Review service logs
   - Confirm port availability

## Acknowledgements

Thanks to the following colleagues for their contributions:
- Yuping Yao
- Zhiwen Liu
- Haikuan Huang (China Mobile Qilu Innovation Institute)
- Junxiu Gao (China Mobile Qilu Innovation Institute) 