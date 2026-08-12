#!/bin/bash
# ============================================================
# MiniMax H3 一键部署到新 DGX Spark
# 从当前机器复制全部文件 + 安装依赖 → 启动 ComfyUI
#
# 用法:
#   bash deploy_to_new_spark.sh <管理IP> <RoCE_IP> <密码> <本机RoCE_IP>
#   bash deploy_to_new_spark.sh 10.0.0.101 10.10.0.101 your_password 10.10.0.1
# ============================================================
set -euo pipefail

# ── 参数 ──────────────────────────────────────────
MGMT_IP="${1:?用法: $0 <管理IP> <RoCE_IP> <密码>}"
ROCE_IP="${2:?用法: $0 <管理IP> <RoCE_IP> <密码>}"
PASSWORD="${3:?用法: $0 <管理IP> <RoCE_IP> <密码>}"
REMOTE_DIR="/root/minnimax-h3"
VENV_DIR="/opt/minnimax-h3-venv"
COMFY_PORT="${COMFY_PORT:-8188}"
RESERVE_VRAM="${RESERVE_VRAM:-8}"

# 源目录 (当前机器)
SOURCE_DIR="/root/minnimax-h3"
MODELSCOPE_CACHE="/root/.cache/modelscope/models/Comfy-Org--MiniMax-H3"
LOCAL_ROCE_IP="${4:?用法: $0 <管理IP> <RoCE_IP> <密码> <本机RoCE_IP>}"

# ── 颜色 ──────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── SSH 封装 ──────────────────────────────────────
SSH_CMD="sshpass -p '${PASSWORD}' ssh -o StrictHostKeyChecking=no -o BindAddress=${LOCAL_ROCE_IP}"
RSYNC_SSH="sshpass -p '${PASSWORD}' ssh -o StrictHostKeyChecking=no -o BindAddress=${LOCAL_ROCE_IP}"

do_ssh() {
    $SSH_CMD root@${ROCE_IP} "$@"
}

do_ssh_mgmt() {
    sshpass -p "${PASSWORD}" ssh -o StrictHostKeyChecking=no root@${MGMT_IP} "$@"
}

# ── 开始 ──────────────────────────────────────────
echo "============================================"
echo " MiniMax H3 一键部署"
echo " 目标: ${MGMT_IP} (管理) / ${ROCE_IP} (RoCE)"
echo " 源:   ${SOURCE_DIR}"
echo "============================================"
echo ""

# ──────────────────────────────────────────────────
# 阶段 1: 探路
# ──────────────────────────────────────────────────
info "阶段 1/5: 探测目标机器..."
do_ssh "hostname && uname -m" || error "SSH 连接失败，检查 IP/密码"

GPU_NAME=$(do_ssh "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null" || echo "unknown")
DISK=$(do_ssh "df -h / | tail -1 | awk '{print \$4}'" || echo "unknown")
info "  主机: $(do_ssh hostname)"
info "  GPU:  ${GPU_NAME}"
info "  可用磁盘: ${DISK}"

# ──────────────────────────────────────────────────
# 阶段 2: 远程安装系统 + Python 依赖
# ──────────────────────────────────────────────────
info "阶段 2/5: 安装系统依赖 + Python 环境..."

do_ssh "apt-get update -qq && apt-get install -y -qq ffmpeg wget git 2>&1 | tail -1" &
PID_APT=$!

do_ssh "python3 -m venv ${VENV_DIR} 2>/dev/null || echo 'venv exists'" &
PID_VENV=$!

wait $PID_APT $PID_VENV
info "  系统依赖 OK"

# 安装 torch + ComfyUI 依赖 (最耗时)
info "  安装 PyTorch + ComfyUI 依赖..."
do_ssh "
  ${VENV_DIR}/bin/pip install -q torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130 2>&1 | tail -3
  ${VENV_DIR}/bin/pip install -q sageattention==1.0.6 sqlalchemy alembic pillow mss opencv-python-headless huggingface_hub 2>&1 | tail -3
  ${VENV_DIR}/bin/python -c 'import torch; print(\"torch\", torch.__version__, \"CUDA\", torch.version.cuda)'
  ${VENV_DIR}/bin/python -c 'import sageattention; print(\"sage ok\")'
"
info "  Python 环境 OK"

# ──────────────────────────────────────────────────
# 阶段 3: Rsync 项目文件 (RoCE)
# ──────────────────────────────────────────────────
info "阶段 3/5: 同步项目文件 (RoCE)..."

do_ssh "mkdir -p ${REMOTE_DIR} ${REMOTE_DIR}/logs"

# 3a: 项目主体 (ComfyUI + 模型 + 脚本 + 工作流)
info "  3a: 项目主体..."
rsync -a --info=progress2 \
  -e "${RSYNC_SSH}" \
  --exclude='.git' --exclude='__pycache__' --exclude='cache_hf' \
  "${SOURCE_DIR}/" \
  "root@${ROCE_IP}:${REMOTE_DIR}/" || error "rsync 项目失败"
info "  项目主体 OK"

# 3b: ModelScope 缓存 (文本编码器 88GB)
info "  3b: ModelScope 缓存 (88GB)..."
do_ssh "mkdir -p ${MODELSCOPE_CACHE}/snapshots/master/text_encoders"
rsync -a --info=progress2 \
  -e "${RSYNC_SSH}" \
  "${MODELSCOPE_CACHE}/snapshots/master/text_encoders/" \
  "root@${ROCE_IP}:${MODELSCOPE_CACHE}/snapshots/master/text_encoders/" || error "rsync ModelScope 失败"
info "  ModelScope 缓存 OK"

# ──────────────────────────────────────────────────
# 阶段 4: 配置 + 修 symlink
# ──────────────────────────────────────────────────
info "阶段 4/5: 配置模型路径..."

do_ssh "
  # 清理可能残留的坏 symlink
  rm -f ${REMOTE_DIR}/comfy/ComfyUI/models/text_encoders/qwen3vl_32b_minimax_h3_*.safetensors

  # 创建文本编码器 symlink (指向 ModelScope 缓存)
  SRC=${MODELSCOPE_CACHE}/snapshots/master/text_encoders
  DST=${REMOTE_DIR}/comfy/ComfyUI/models/text_encoders
  for f in qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors \
           qwen3vl_32b_minimax_h3_int8_convrot.safetensors \
           qwen3vl_32b_minimax_h3_bf16.safetensors; do
    ln -sf \"\${SRC}/\${f}\" \"\${DST}/\${f}\"
  done
  echo 'Symlinks OK'

  # 安装 ComfyUI requirements
  cd ${REMOTE_DIR}/comfy/ComfyUI
  ${VENV_DIR}/bin/pip install -q -r requirements.txt 2>&1 | tail -1
  echo 'Requirements OK'

  # 验证关键文件
  echo '=== 模型清单 ==='
  du -sh ${REMOTE_DIR}/comfy/ComfyUI/models/text_encoders/H3/ 2>/dev/null
  ls -lh ${REMOTE_DIR}/comfy/ComfyUI/models/diffusion_models/*.safetensors
  ls -lh ${REMOTE_DIR}/comfy/ComfyUI/models/vae/*.safetensors
"
info "  配置 OK"

# ──────────────────────────────────────────────────
# 阶段 5: 启动 ComfyUI
# ──────────────────────────────────────────────────
info "阶段 5/5: 启动 ComfyUI..."

# 先停掉可能存在的旧进程
do_ssh "pkill -f 'main.py.*${COMFY_PORT}' 2>/dev/null; sleep 2; true"

do_ssh "
  cd ${REMOTE_DIR}/comfy/ComfyUI
  nohup ${VENV_DIR}/bin/python main.py \
    --listen 0.0.0.0 --port ${COMFY_PORT} --reserve-vram ${RESERVE_VRAM} \
    > ${REMOTE_DIR}/logs/comfyui.log 2>&1 &
  echo \$! > ${REMOTE_DIR}/logs/comfyui.pid
  echo 'PID:' \$(cat ${REMOTE_DIR}/logs/comfyui.pid)
"

# 等启动
info "  等待 ComfyUI 启动..."
for i in $(seq 1 30); do
    HTTP_CODE=$(do_ssh_mgmt "curl -s -o /dev/null -w '%{http_code}' http://localhost:${COMFY_PORT}/" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        info "  ComfyUI 启动成功! HTTP ${HTTP_CODE}"
        break
    fi
    sleep 2
done

if [ "$HTTP_CODE" != "200" ]; then
    warn "  HTTP 检测超时，查看日志:"
    do_ssh "tail -20 ${REMOTE_DIR}/logs/comfyui.log"
fi

# ──────────────────────────────────────────────────
# 完成
# ──────────────────────────────────────────────────
echo ""
echo "============================================"
echo -e " ${GREEN}部署完成!${NC}"
echo ""
echo "  目标机器:  ${MGMT_IP}"
echo "  ComfyUI:   http://${MGMT_IP}:${COMFY_PORT}"
echo "  部署目录:  ${REMOTE_DIR}"
echo "  Python:    ${VENV_DIR}/bin/python"
echo ""
echo "  远程操作:"
echo "    ssh root@${MGMT_IP}                    # 登录"
echo "    tail -f ${REMOTE_DIR}/logs/comfyui.log # 日志"
echo "    kill \$(cat ${REMOTE_DIR}/logs/comfyui.pid) # 关闭"
echo ""
echo "  重启 ComfyUI:"
echo "    cd ${REMOTE_DIR}/comfy/ComfyUI"
echo "    nohup ${VENV_DIR}/bin/python main.py --listen 0.0.0.0 --port ${COMFY_PORT} --reserve-vram ${RESERVE_VRAM} > ${REMOTE_DIR}/logs/comfyui.log 2>&1 &"
echo "============================================"
