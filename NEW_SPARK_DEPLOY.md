# MiniMax H3 新机器部署文档

## 方案选择

| 方案 | 脚本 | 适用场景 | 时间 |
|------|------|----------|------|
| **A: 从零下载** | `deploy_from_scratch.sh` | 全新机器，无从节点 | 取决于网速 |
| | `install_wizard.py` | 同上，交互式引导 | 取决于网速 |
| **B: 从主节点复制** | `deploy_to_new_spark.sh` | 已有主节点，快速克隆 | ~5 分钟 |
| | `install_wizard.py` | 同上，交互式引导 | ~5 分钟 |

---

## 方案 A: 从零下载（无主节点）

```bash
# 在新 DGX Spark 上直接执行
wget https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3/raw/master/deploy_from_scratch.sh
bash deploy_from_scratch.sh
```

如需代理：
```bash
PROXY=http://your-proxy:port bash deploy_from_scratch.sh
```

脚本自动完成 7 个阶段：
1. 系统依赖 (ffmpeg, git)
2. Python venv + PyTorch CUDA 13 + 依赖
3. ComfyUI + 8 个自定义节点
4. ModelScope 文本编码器 (~88GB)
5. HuggingFace Heretic TE (~32GB)
6. HuggingFace keys-heretic 权重 (~25GB)
7. 启动 ComfyUI

**下载总量**: ~145GB

---

## 方案 B: 从主节点复制（有主节点）

从已部署好的 DGX Spark（主节点）一键复制全部内容到新机器。

| 项目 | 主节点 | 新机器示例 |
|------|--------|-----------|
| 管理 IP | — | `192.168.x.x` |
| RoCE IP | `10.10.x.x` | `10.10.x.x` |
| 部署目录 | `/root/minnimax-h3/` | `/root/minnimax-h3/` |
| Python | 主节点 venv | `/opt/minnimax-h3-venv` |
| ComfyUI 端口 | `8188` | `8188` |

---

## 一键部署

```bash
# 在主节点上执行
cd /root/minnimax-h3
bash deploy_to_new_spark.sh <新机器管理IP> <新机器RoCE_IP> [密码]

# 示例
bash deploy_to_new_spark.sh 192.168.22.161 10.10.12.21 <你的密码>
```

**脚本自动完成：**
1. ✅ 探测目标机器环境
2. ✅ 安装系统依赖（ffmpeg）
3. ✅ 创建 Python venv + 安装 PyTorch CUDA 13 + ComfyUI 依赖
4. ✅ RoCE 高速传输项目文件（~57GB）和 ModelScope 缓存（~88GB）
5. ✅ 创建模型 symlink
6. ✅ 启动 ComfyUI

---

## 传输内容明细

### 项目文件 (~57GB)
```
/root/minnimax-h3/ → /root/minnimax-h3/
├── comfy/ComfyUI/          # ComfyUI v0.30.1 + 所有模型 + 自定义节点
├── comfy/workflows/        # 12 个工作流 JSON
├── scripts/                # 部署/下载脚本
├── DEPLOYMENT.md           # 主部署文档
└── deploy_to_new_spark.sh  # 本一键脚本
```

### ModelScope 缓存 (~88GB)
```
/root/.cache/modelscope/models/Comfy-Org--MiniMax-H3/snapshots/master/text_encoders/
├── qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors    (15 GB)
├── qwen3vl_32b_minimax_h3_int8_convrot.safetensors  (26 GB)
└── qwen3vl_32b_minimax_h3_bf16.safetensors          (48 GB)
```

### 传输带宽
通过 RoCE 直连网络（10.10.12.x），实测 ~550 MB/s。145GB 约 4.5 分钟传完。

---

## 手动部署步骤（参考）

如果一键脚本出问题，按以下步骤手动操作：

### 1. 探路
```bash
ssh root@<管理IP>  # 密码 <你的密码>
uname -a
nvidia-smi
df -h /
```

### 2. 远程装依赖
```bash
ssh root@<RoCE_IP>
apt-get install -y ffmpeg
python3 -m venv /opt/minnimax-h3-venv
/opt/minnimax-h3-venv/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130
/opt/minnimax-h3-venv/bin/pip install sageattention==1.0.6 sqlalchemy alembic pillow mss opencv-python-headless huggingface_hub
```

### 3. 主节点推送文件
```bash
# 在本机执行

# 设 SSH 免密 (一次性)
sshpass -p '<你的密码>' ssh-copy-id root@<RoCE_IP>

# 同步项目
rsync -av --progress \
  -e "sshpass -p '<你的密码>' ssh -o StrictHostKeyChecking=no -o BindAddress=<本机RoCE_IP>" \
  --exclude='.git' --exclude='__pycache__' --exclude='cache_hf' \
  /root/minnimax-h3/ root@<RoCE_IP>:/root/minnimax-h3/

# 同步 ModelScope 缓存
rsync -av --progress \
  -e "sshpass -p '<你的密码>' ssh -o StrictHostKeyChecking=no -o BindAddress=<本机RoCE_IP>" \
  /root/.cache/modelscope/models/Comfy-Org--MiniMax-H3/snapshots/master/text_encoders/ \
  root@<RoCE_IP>:/root/.cache/modelscope/models/Comfy-Org--MiniMax-H3/snapshots/master/text_encoders/
```

### 4. 创建模型 symlink
```bash
ssh root@<RoCE_IP>
DST=/root/minnimax-h3/comfy/ComfyUI/models/text_encoders
SRC=/root/.cache/modelscope/models/Comfy-Org--MiniMax-H3/snapshots/master/text_encoders
for f in qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors \
         qwen3vl_32b_minimax_h3_int8_convrot.safetensors \
         qwen3vl_32b_minimax_h3_bf16.safetensors; do
    ln -sf "$SRC/$f" "$DST/$f"
done
```

### 5. 装 ComfyUI 依赖 + 启动
```bash
cd /root/minnimax-h3/comfy/ComfyUI
/opt/minnimax-h3-venv/bin/pip install -r requirements.txt

nohup /opt/minnimax-h3-venv/bin/python main.py \
  --listen 0.0.0.0 --port 8188 --reserve-vram 8 \
  > /root/minnimax-h3/logs/comfyui.log 2>&1 &
```

---

## 远程 ComfyUI 管理

```bash
# 查看状态
curl -s -o /dev/null -w "%{http_code}" http://<管理IP>:8188/

# 查看日志
ssh root@<管理IP> "tail -f /root/minnimax-h3/logs/comfyui.log"

# 关闭
ssh root@<管理IP> "kill \$(cat /root/minnimax-h3/logs/comfyui.pid)"

# 重启
ssh root@<管理IP> "
  cd /root/minnimax-h3/comfy/ComfyUI
  nohup /opt/minnimax-h3-venv/bin/python main.py --listen 0.0.0.0 --port 8188 --reserve-vram 8 \
    > /root/minnimax-h3/logs/comfyui.log 2>&1 &
  echo \$! > /root/minnimax-h3/logs/comfyui.pid
"
```

---

## 常见问题

### Q: SSH 连不上 RoCE IP？
```bash
# 用管理 IP 先登录确认网络
ssh root@192.168.22.161
ip addr | grep 10.10.12   # 确认 RoCE 网卡存在
```

### Q: rsync 报 Permission denied？
```bash
# RoCE IP 和管理 IP 是不同 host key，分别传密钥
sshpass -p '<你的密码>' ssh-copy-id root@<管理IP>
sshpass -p '<你的密码>' ssh-copy-id root@<RoCE_IP>
```

### Q: pip 报 externally-managed-environment？
Python 3.12+ Ubuntu 24.04 需要 `--break-system-packages` 或使用 venv。
本部署脚本默认创建 `/opt/minnimax-h3-venv`。

### Q: 远程 ComfyUI 连不上？
```bash
# 检查是否在监听
ssh root@<IP> "ss -tlnp | grep 8188"
# 检查日志
ssh root@<IP> "tail -50 /root/minnimax-h3/logs/comfyui.log"
```
