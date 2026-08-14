#!/bin/bash
# ============================================================
# MiniMax H3 + keys-heretic 从零部署脚本 v2
# DGX Spark (GB10) — 不需要任何本地缓存或主节点
# 所有内容从 GitHub / HuggingFace / ModelScope 下载
#
# 用法:
#   bash deploy_from_scratch.sh
#   PROXY=http://your-proxy:port bash deploy_from_scratch.sh   # 如需要
#
# 下载总量: ~165GB
#   - HF 权重一体包:  ~91GB  (drowzeys/keys-heretic-...-weights)
#   - ModelScope TE:   ~74GB  (INT8-ConvRot + BF16)
#   - Git repos:        ~1GB
# ============================================================
set -euo pipefail

# ── 可覆盖配置 ────────────────────────────────────
INSTALL_DIR="${INSTALL_DIR:-/root/minnimax-h3}"
VENV_DIR="${VENV_DIR:-/opt/minnimax-h3-venv}"
COMFY_PORT="${COMFY_PORT:-8188}"
RESERVE_VRAM="${RESERVE_VRAM:-8}"
PROXY="${PROXY:-}"
if [ -n "$PROXY" ]; then
    export http_proxy="$PROXY" https_proxy="$PROXY"
    export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
fi

# ── 颜色 ──────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ── 前置检查 ──────────────────────────────────────
check() {
    [ "$(id -u)" = "0" ] || error "需要 root 权限 (sudo su -)"
    python3 --version >/dev/null 2>&1 || error "需要 Python 3"
    nvidia-smi >/dev/null 2>&1 || warn "nvidia-smi 未检测到，可能不是 GPU 机器"
    local free_gb=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    [ "$free_gb" -ge 200 ] || warn "磁盘剩余仅 ${free_gb}GB，建议 ≥200GB"
    info "前置检查通过 — root:✓ Python3:✓ 磁盘:${free_gb}GB"
}

# ── 主流程 ────────────────────────────────────────
main() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║   MiniMax H3 从零部署 v2                     ║"
    echo "║   安装目录: ${INSTALL_DIR}                   ║"
    echo "║   ComfyUI:   http://\$(hostname -I | awk '{print \$1}'):${COMFY_PORT}"
    echo "║   代理:      ${PROXY:-无}                    ║"
    echo "╚══════════════════════════════════════════════╝"
    check

    # ── 目录初始化 ──
    mkdir -p "${INSTALL_DIR}/logs"
    COMFY="${INSTALL_DIR}/comfy/ComfyUI"
    MODEL_DIR="${COMFY}/models"
    CN="${COMFY}/custom_nodes"

    # ── 阶段 1: 系统依赖 ──
    step "阶段 1/6: 系统依赖"
    apt-get update -qq
    apt-get install -y -qq git ffmpeg wget ca-certificates 2>&1 | tail -2
    info "git $(git --version | awk '{print $3}')"
    info "ffmpeg $(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')"

    # ── 阶段 2: Python 虚拟环境 ──
    step "阶段 2/6: Python 环境"
    python3 -m venv "${VENV_DIR}" 2>/dev/null || true
    PY="${VENV_DIR}/bin/python"

    info "安装 PyTorch CUDA 13..."
    $PY -m pip install -q --no-cache-dir \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu130 2>&1 | tail -1
    $PY -c "import torch; print(f'  PyTorch {torch.__version__} CUDA {torch.version.cuda}')" || \
        error "PyTorch CUDA 13 安装失败"

    info "安装 sageattention + database + 辅助库..."
    $PY -m pip install -q --no-cache-dir \
        sageattention==1.0.6 \
        sqlalchemy alembic \
        pillow mss opencv-python-headless \
        huggingface_hub modelscope 2>&1 | tail -1
    $PY -c "import sageattention, sqlalchemy, modelscope" && info "核心依赖 OK" || \
        error "核心依赖安装失败"

    # ── 阶段 3: ComfyUI + 自定义节点 ──
    step "阶段 3/6: ComfyUI + 自定义节点"

    if [ ! -d "${COMFY}/.git" ]; then
        info "克隆 ComfyUI..."
        git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "${COMFY}" 2>&1 | tail -1
        cd "${COMFY}" && git fetch --tags && git checkout v0.30.1 2>/dev/null || true
    fi
    info "ComfyUI: $(cd ${COMFY} && git describe --tags 2>/dev/null || echo 'latest')"

    info "克隆自定义节点..."
    mkdir -p "${CN}"

    clone_node() {
        local url="$1" dir="$2"
        if [ ! -d "${CN}/${dir}/.git" ]; then
            git clone --depth 1 "$url" "${CN}/${dir}" 2>&1 | tail -1
        else
            echo "    ${dir} ✓"
        fi
    }

    clone_node https://github.com/kijai/ComfyUI-SolAttn_triton.git        ComfyUI-SolAttn_triton
    clone_node https://github.com/kijai/ComfyUI-KJNodes.git               ComfyUI-KJNodes
    clone_node https://github.com/xmarre/ComfyUI-Spectrum-MiniMax-H3.git  ComfyUI-Spectrum-MiniMax-H3
    clone_node https://github.com/jlucasmcrell/ComfyUI-H3-Multishot.git   ComfyUI-H3-Multishot
    clone_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ComfyUI-VideoHelperSuite

    # Sol-Attn Blackwell + H3 引擎端口 (从 keys-heretic 仓库取)
    info "设置 Sol-Attn Blackwell + H3 引擎..."
    TMP="/tmp/keys-heretic-tmp"
    [ -d "$TMP" ] || git clone --depth 1 \
        https://github.com/drowzeys/keys-heretic-MiniMax-H3-sol-engine-more-speed-upgrades-upscaler-finish-Single-DGX-Spark.git \
        "$TMP" 2>&1 | tail -1

    mkdir -p "${CN}/ComfyUI_sol-attn_Blackwell" "${CN}/h3_sol_engine_ports"
    cp -a "$TMP/vendor/ComfyUI_sol-attn_Blackwell/"* "${CN}/ComfyUI_sol-attn_Blackwell/" 2>/dev/null || true
    cp -a "$TMP/nodes/h3_fbc_node.py" "$TMP/nodes/h3_vae_batch.py" "${CN}/ComfyUI_sol-attn_Blackwell/" 2>/dev/null || true
    cp -a "$TMP/nodes/h3_fbc_node.py" "$TMP/nodes/h3_vae_batch.py" "${CN}/h3_sol_engine_ports/" 2>/dev/null || true

    cat > "${CN}/h3_sol_engine_ports/__init__.py" << 'PYEOF'
from .h3_fbc_node import NODE_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS
try:
    from .h3_vae_batch import install as _install_vae_batch
    _install_vae_batch()
except Exception as e:
    import logging
    logging.getLogger(__name__).warning("H3 batched VAE not installed: %s", e)
__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS"]
PYEOF
    info "Sol-Attn Blackwell + H3 端口 OK"

    # 安装 ComfyUI requirements
    info "安装 ComfyUI requirements..."
    $PY -m pip install -q --no-cache-dir -r "${COMFY}/requirements.txt" 2>&1 | tail -1

    # 工作流
    WORKFLOWS="${INSTALL_DIR}/comfy/workflows"
    mkdir -p "${WORKFLOWS}"
    cp -a "$TMP/workflows/"*.json "${WORKFLOWS}/" 2>/dev/null || true
    info "工作流: $(ls ${WORKFLOWS}/*.json 2>/dev/null | wc -l) 个"
    rm -rf "$TMP"

    # ── 阶段 4: HF 权重一体包 ──
    step "阶段 4/6: 下载权重 — HuggingFace 一体包 (~91GB)"
    mkdir -p "${MODEL_DIR}"  # 创建 models 目录以接收 hf download

    HF_WEIGHTS="drowzeys/keys-heretic-MiniMax-H3-sol-engine-more-DGX-Spark-weights"
    FLAG_FILE="${MODEL_DIR}/.weights_downloaded"

    if [ -f "$FLAG_FILE" ]; then
        info "HF 权重已下载，跳过"
    else
        info "下载中...（约 91GB，请耐心等待，可 Ctrl+C 中断后重新运行续传）"
        echo ""
        echo "  ┌──────────────────────────────────────────┐"
        echo "  │  下载内容：                                │"
        echo "  │  • diffusion_models (fl2va+ref2va)  ~40 GB  │"
        echo "  │  • text_encoders (nvFP4)      ~15 GB       │"
        echo "  │  • text_encoders/H3 (Heretic)  ~32 GB      │"
        echo "  │  • vae (video + audio)         ~5.5 GB     │"
        echo "  │  • upscale_models (ESRGAN)     ~0.1 GB     │"
        echo "  │  • 其他辅助文件                ~13 GB      │"
        echo "  └──────────────────────────────────────────┘"
        echo ""
        info "提示：扩散模型 + VAE（fl2va/ref2va 各 20GB、video/audio VAE）"
        info "      也可从 ModelScope 直连下载（国内更快、无需代理），见 I2V.md 第 4 节。"

        $PY -m huggingface_hub.cli.hf download "${HF_WEIGHTS}" \
            --repo-type model \
            --local-dir "${MODEL_DIR}" \
            --local-dir-use-symlinks False 2>&1 && \
            touch "$FLAG_FILE" || error "HF 权重下载失败，请检查网络或设置 PROXY=... 后重试"
    fi

    # 展平可能的目录嵌套 (hf download 有时会造出 xxx/xxx/)
    for sub in diffusion_models text_encoders vae upscale_models; do
        if [ -d "${MODEL_DIR}/${sub}/${sub}" ]; then
            mv "${MODEL_DIR}/${sub}/${sub}/"* "${MODEL_DIR}/${sub}/" 2>/dev/null || true
            rmdir "${MODEL_DIR}/${sub}/${sub}" 2>/dev/null || true
        fi
    done
    info "HF 权重一体包 OK"
    find "${MODEL_DIR}" -name "*.safetensors" -o -name "*.pth" | \
        while read f; do echo "    $(du -h "$f" | cut -f1) $f"; done

    # ── 阶段 5: ModelScope 补充文本编码器 ──
    step "阶段 5/6: 下载补充文本编码器 — ModelScope (~74GB)"

    MSC_ROOT="/root/.cache/modelscope/hub/models/Comfy-Org/MiniMax-H3"
    MSC_FLAG="${MSC_ROOT}/.done"

    if [ -f "$MSC_FLAG" ]; then
        info "ModelScope 文本编码器已下载，跳过"
    else
        info "下载中...（约 74GB: INT8-ConvRot 26GB + BF16 48GB）"
        $PY << 'PYEOF'
from modelscope.hub.snapshot_download import snapshot_download
import os

dst = "/root/.cache/modelscope/hub/models/Comfy-Org/MiniMax-H3"
os.makedirs(dst, exist_ok=True)

print("Downloading INT8-ConvRot text encoder (26 GB)...")
snapshot_download(
    "Comfy-Org/MiniMax-H3",
    cache_dir="/root/.cache/modelscope",
    allow_patterns=["text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"],
)

print("Downloading BF16 text encoder (48 GB)...")
snapshot_download(
    "Comfy-Org/MiniMax-H3",
    cache_dir="/root/.cache/modelscope",
    allow_patterns=["text_encoders/qwen3vl_32b_minimax_h3_bf16.safetensors"],
)

open(os.path.join(dst, ".done"), "w").close()
print("ModelScope text encoders download complete")
PYEOF
    fi

    # 创建 symlink
    info "创建 symlink..."
    # ModelScope 实际存储路径
    MSC_FILES=$(find /root/.cache/modelscope -name "qwen3vl_32b_minimax_h3_int8_convrot.safetensors" \
                                        -o -name "qwen3vl_32b_minimax_h3_bf16.safetensors" 2>/dev/null)
    TEXT_ENC_DIR="${MODEL_DIR}/text_encoders"
    mkdir -p "$TEXT_ENC_DIR"

    for f in $MSC_FILES; do
        base=$(basename "$f")
        if [ ! -e "${TEXT_ENC_DIR}/${base}" ]; then
            ln -sf "$f" "${TEXT_ENC_DIR}/${base}"
            info "  ${base} → symlink"
        fi
    done
    info "ModelScope 文本编码器 OK"

    # ── 阶段 6: 启动 ComfyUI ──
    step "阶段 6/6: 启动 ComfyUI"

    LOG_FILE="${INSTALL_DIR}/logs/comfyui.log"

    # 先停掉可能已经在跑的旧实例
    pkill -f "main.py.*${COMFY_PORT}" 2>/dev/null || true
    sleep 1

    cd "${COMFY}"
    nohup $PY main.py --listen 0.0.0.0 --port ${COMFY_PORT} --reserve-vram ${RESERVE_VRAM} \
        > "$LOG_FILE" 2>&1 &
    echo $! > "${INSTALL_DIR}/logs/comfyui.pid"
    PID=$(cat "${INSTALL_DIR}/logs/comfyui.pid")
    info "PID: $PID"

    info "等待启动 (最多 90 秒)..."
    STARTED=false
    for i in $(seq 1 45); do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${COMFY_PORT}/" 2>/dev/null | grep -q 200; then
            info "ComfyUI 已就绪! HTTP 200 (${i}x2 秒)"
            STARTED=true
            break
        fi
        sleep 2
    done

    if ! $STARTED; then
        warn "ComfyUI 可能仍在加载模型，请稍候查看日志:"
        echo "    tail -20 $LOG_FILE"
    fi

    # 生成重启脚本
    cat > "${INSTALL_DIR}/restart.sh" << RESTARTEOF
#!/bin/bash
kill \$(cat ${INSTALL_DIR}/logs/comfyui.pid 2>/dev/null) 2>/dev/null
sleep 2
cd ${COMFY}
nohup ${PY} main.py --listen 0.0.0.0 --port ${COMFY_PORT} --reserve-vram ${RESERVE_VRAM} \\
    > ${INSTALL_DIR}/logs/comfyui.log 2>&1 &
echo \$! > ${INSTALL_DIR}/logs/comfyui.pid
echo "ComfyUI restarted, PID: \$(cat ${INSTALL_DIR}/logs/comfyui.pid)"
RESTARTEOF
    chmod +x "${INSTALL_DIR}/restart.sh"

    # 生成 status 脚本
    cat > "${INSTALL_DIR}/status.sh" << STATUSEOP
#!/bin/bash
echo "ComfyUI PID: \$(cat ${INSTALL_DIR}/logs/comfyui.pid 2>/dev/null || echo 'N/A')"
echo "HTTP: \$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${COMFY_PORT}/ 2>/dev/null || echo 'DOWN')"
echo "磁盘: \$(df -h / | awk 'NR==2{print \$3" / "\$2" ("\$5" used)"}')"
echo "模型数: \$(find ${MODEL_DIR} -name '*.safetensors' -o -name '*.pth' 2>/dev/null | wc -l)"
STATUSEOP
    chmod +x "${INSTALL_DIR}/status.sh"

    # ── 完成 ──
    local IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║           🎉 部署完成!                       ║"
    echo "╠══════════════════════════════════════════════╣"
    echo "║  地址:     http://${IP}:${COMFY_PORT}"
    echo "║  安装目录: ${INSTALL_DIR}"
    echo "║  Python:   ${PY}"
    echo "║                                              ║"
    echo "║  管理命令:                                    ║"
    echo "║    bash ${INSTALL_DIR}/restart.sh          ║"
    echo "║    bash ${INSTALL_DIR}/status.sh           ║"
    echo "║    tail -f ${LOG_FILE}"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    echo "  快速使用:"
    echo "    1. 浏览器打开 http://${IP}:${COMFY_PORT}"
    echo "    2. 拖入工作流 JSON: ${WORKFLOWS}/"
    echo "    3. 推荐从 h3-dense-baseline.json 开始"
    echo "    4. 修改 Node #104 prompt → Queue Prompt"
}

main
