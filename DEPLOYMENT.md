# MiniMax H3 + keys-heretic 完整部署文档

## 1. 目标硬件 / 系统环境

| 项目 | 值 |
|------|-----|
| 硬件 | NVIDIA DGX Spark (GB10, Grace-Hopper, sm_121) |
| OS | Ubuntu 24.04, Linux 6.17, aarch64 |
| GPU | NVIDIA GB10 (统一内存架构) |
| Python | 3.12.3 (venv) |
| PyTorch | 2.11.0+cu130, CUDA 13.0 |
| 磁盘 | /dev/nvme0n1p2 3.6TB |
| 部署根目录 | `/root/minnimax-h3/` |

---

## 2. 目录结构总览

```
/root/minnimax-h3/
├── comfy/                          # ComfyUI 完整安装
│   ├── ComfyUI/                    # ComfyUI v0.30.1 本体
│   │   ├── main.py                 # 启动入口
│   │   ├── models/                 # 模型权重
│   │   │   ├── diffusion_models/   # 扩散模型
│   │   │   ├── text_encoders/      # 文本编码器 (含 H3/)
│   │   │   ├── vae/                # VAE 模型
│   │   │   └── upscale_models/     # 超分模型
│   │   ├── custom_nodes/           # 自定义节点 (8个)
│   │   └── output/                 # 生成输出目录
│   └── workflows/                  # 工作流 JSON 文件 (12个)
├── logs/                           # 运行日志
```

---

## 3. 所有模型文件清单

### 3.1 HuggingFace 下载（直接落盘，wget + 代理）

| 文件 | 大小 | 来源 | 目录 |
|------|------|------|------|
| `qwen3vl_32b_h3_ultra_uncensored_heretic_int8_convrot.safetensors` | 25 GB | HF: `ethanfel/Qwen3-VL-32B-Ultra-Heretic-H3-ComfyUI-INT8-ConvRot` | `models/text_encoders/H3/` |
| `qwen3vl_32b_h3_generation_tail_50_63_int8_convrot.safetensors` | 7.1 GB | 同上 | `models/text_encoders/H3/` |

**下载命令**:
```bash
# 如需代理: export http_proxy=http://your-proxy:port; export https_proxy=$http_proxy
wget --tries=3 --timeout=60 --progress=dot:giga \
  -O models/text_encoders/H3/{filename} \
  https://huggingface.co/ethanfel/Qwen3-VL-32B-Ultra-Heretic-H3-ComfyUI-INT8-ConvRot/resolve/main/{filename}
```

### 3.2 ModelScope 下载（symlink）

| 文件 | 来源 | 目录 |
|------|------|------|
| `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | ModelScope: `Comfy-Org/MiniMax-H3` | `models/text_encoders/` |
| `qwen3vl_32b_minimax_h3_int8_convrot.safetensors` | 同上 | `models/text_encoders/` |
| `qwen3vl_32b_minimax_h3_bf16.safetensors` | 同上 | `models/text_encoders/` |

> 这三个文件通过 modelscope CLI 下载至 `/root/.cache/modelscope/`，
> 然后在 models 目录下创建 symlink。如果在新机器部署可直接从 ModelScope 重新下载。

### 3.3 扩散模型 + VAE（从 HF 权重包 / ModelScope 下载）

| 文件 | 大小 | 目录 | 用途 |
|------|------|------|------|
| `minimax_h3_fl2va_pruned_int8_convrot.safetensors` | 20 GB | `models/diffusion_models/` | T2V / I2V（首尾帧驱动） |
| `minimax_h3_ref2va_pruned_int8_convrot.safetensors` | 20 GB | `models/diffusion_models/` | R2V（参考图驱动） |
| `minimax_h3_video_vae_fp16.safetensors` | 4.9 GB | `models/vae/` | 视频编解码（三种模式共用） |
| `minimax_h3_audio_vae_fp32.safetensors` | 578 MB | `models/vae/` | 音频编解码（R2V 必需） |
| `RealESRGAN_x2plus.pth` | 64 MB | `models/upscale_models/` | 视频 2× 超分 |

> I2V（图生视频）能力的完整说明、依赖与下载方式见 **[I2V.md](I2V.md)**。

---

## 4. 自定义节点 (Custom Nodes)

| 节点 | 用途 | 来源 |
|------|------|------|
| `ComfyUI-SolAttn_triton` | Sol-Attention 加速 (Triton) | `kijai/ComfyUI-SolAttn_triton` |
| `ComfyUI-KJNodes` | 通用工具节点 | `kijai/ComfyUI-KJNodes` |
| `ComfyUI-Spectrum-MiniMax-H3` | MiniMax H3 频谱优化 | `xmarre/ComfyUI-Spectrum-MiniMax-H3` |
| `ComfyUI-H3-Multishot` | 多镜头视频生成 | `jlucasmcrell/ComfyUI-H3-Multishot` |
| `ComfyUI-VideoHelperSuite` | 视频输出封装 (需 ffmpeg) | `Kosinkadink/ComfyUI-VideoHelperSuite` |
| `ComfyUI_sol-attn_Blackwell` | Sol-Attn Blackwell 预打补丁版 | keys-heretic vendor/ |
| `h3_sol_engine_ports` | H3 FBC + 批量 VAE 节点 | keys-heretic nodes/ |

---

## 5. 环境依赖

### 5.1 系统工具
```bash
apt-get install -y git ffmpeg wget ca-certificates
```

### 5.2 Python 依赖
```bash
# ComfyUI 基础依赖
pip install -r ComfyUI/requirements.txt

# 关键加速库
pip install sageattention==1.0.6

# 辅助库
pip install pillow color-matcher matplotlib mss opencv-python-headless huggingface_hub

# 数据库（ComfyUI >= 0.30）
pip install sqlalchemy alembic
```

### 5.3 网络代理（如果 HF 直连不通）
```bash
export http_proxy=http://your-proxy:port
export https_proxy=$http_proxy
```

---

## 6. 关键启动参数说明

```bash
python3 main.py \
  --listen 0.0.0.0 \    # 监听所有网络接口
  --port 8188 \          # Web UI 端口
  --reserve-vram 8       # 预留 8GB VRAM 给系统 (GB10 统一内存)
```

> **注意**：
> - **不要加 `--use-sage-attention`**，项目用 Sol-Attn 替代，加了这个会冲突
> - **EasyCache 保持关闭**（R2V 模式不兼容）
> - GB10 是统一内存架构，`--reserve-vram` 用于给非 GPU 任务预留内存

---

## 7. 启动 / 关闭 ComfyUI

### 启动
```bash
cd /root/minnimax-h3/comfy/ComfyUI

# 前台运行（调试用）
python3 main.py --listen 0.0.0.0 --port 8188 --reserve-vram 8

# 后台运行
nohup python3 main.py --listen 0.0.0.0 --port 8188 --reserve-vram 8 \
  > /root/minnimax-h3/logs/comfyui.log 2>&1 &
echo $! > /root/minnimax-h3/logs/comfyui.pid
```

### 关闭
```bash
kill $(cat /root/minnimax-h3/logs/comfyui.pid)
# 或
pkill -f "main.py.*8188"
```

### 查看状态
```bash
# 进程状态
ps aux | grep "main.py.*8188"

# 实时日志
tail -f /root/minnimax-h3/logs/comfyui.log

# Web 探测
curl -s -o /dev/null -w "%{http_code}" http://localhost:8188/
```

### 访问
浏览器打开 `http://<服务器IP>:8188`

---

## 8. 快速部署流程（新机器）

### 前置条件
- Ubuntu 24.04 aarch64, NVIDIA GPU (GB10 / sm_121+)
- Python 3.12+, CUDA 13.0+, PyTorch 2.11+cu130
- 磁盘剩余 ≥ 100GB

### 步骤

```bash
# 1. 克隆 keys-heretic 仓库
git clone https://github.com/drowzeys/keys-heretic-MiniMax-H3-sol-engine-more-speed-upgrades-upscaler-finish-Single-DGX-Spark.git
cd keys-heretic-MiniMax-H3-*/

# 2. 克隆 ComfyUI v0.30.1
git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI && git checkout v0.30.1 && cd ..

# 3. 克隆自定义节点 (全部深度1)
cd ComfyUI/custom_nodes
git clone --depth 1 https://github.com/kijai/ComfyUI-SolAttn_triton.git
git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git
git clone --depth 1 https://github.com/xmarre/ComfyUI-Spectrum-MiniMax-H3.git
git clone --depth 1 https://github.com/jlucasmcrell/ComfyUI-H3-Multishot.git
git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
cd ../..

# 4. 复制 vendor 节点（Sol-Attn Blackwell + H3 端口）
cp -a vendor/ComfyUI_sol-attn_Blackwell ComfyUI/custom_nodes/
cp -a nodes/h3_fbc_node.py nodes/h3_vae_batch.py ComfyUI/custom_nodes/ComfyUI_sol-attn_Blackwell/

mkdir -p ComfyUI/custom_nodes/h3_sol_engine_ports
cp nodes/h3_fbc_node.py nodes/h3_vae_batch.py ComfyUI/custom_nodes/h3_sol_engine_ports/
# 创建 __init__.py (见下方 附录A)

# 5. 安装系统依赖
apt-get install -y ffmpeg

# 6. 安装 Python 依赖
pip install -r ComfyUI/requirements.txt
pip install sageattention==1.0.6 sqlalchemy alembic
pip install pillow color-matcher matplotlib mss opencv-python-headless huggingface_hub

# 7. 下载模型权重（三部分）
#   a) ModelScope: qwen3vl_32b_minimax_h3 的三个 text encoder
modelscope download Comfy-Org/MiniMax-H3 --local_dir /path/to/cache
ln -s /path/to/cache/text_encoders/qwen3vl_32b_minimax_h3_*.safetensors ComfyUI/models/text_encoders/

#   b) HuggingFace Heretic TE (两个文件，用代理):
export http_proxy=http://PROXY_IP:PORT; export https_proxy=$http_proxy
wget -O ComfyUI/models/text_encoders/H3/{file} https://huggingface.co/ethanfel/Qwen3-VL-32B-Ultra-Heretic-H3-ComfyUI-INT8-ConvRot/resolve/main/{file}

#   c) keys-heretic 权重 (从 HuggingFace 一体包下载):
#      huggingface-cli download drowzeys/keys-heretic-MiniMax-H3-sol-engine-more-DGX-Spark-weights \
#        --local-dir ComfyUI/models/
#      包含以下文件:
#      diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors
#      diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors
#      vae/minimax_h3_video_vae_fp16.safetensors
#      vae/minimax_h3_audio_vae_fp32.safetensors
#      upscale_models/RealESRGAN_x2plus.pth
#      upscale_models/RealESRGAN_x4plus.pth
#   d) 备选：扩散模型 + VAE 也可从 ModelScope 直连下载（国内更快，无需代理），
#      详见 I2V.md 第 4 节。fl2va(20GB) + ref2va(20GB) + video_vae + audio_vae
#      均可在 modelscope.cn/models/Comfy-Org/MiniMax-H3 找到。

# 8. 创建工作流目录，复制 JSON
mkdir -p workflows
cp repo/workflows/*.json workflows/

# 9. 启动
cd ComfyUI
python3 main.py --listen 0.0.0.0 --port 8188 --reserve-vram 8
```

---

## 9. 使用说明

### 加载工作流
1. 浏览器打开 `http://<IP>:8188`
2. 把 `workflows/` 下的 JSON 拖到画布上

### 推荐工作流

| 工作流 | 用途 |
|--------|------|
| `h3-dense-baseline.json` | ✅ 文生视频（最简单，最推荐入门） |
| `h3-i2v-firstframe-enhanced.json` | ✅ I2V 首帧驱动图生视频 + 超分（720p） |
| `h3-enhanced-fullstack.json` | 图生视频 + 超分 |
| `h3-multishot-enhanced.json` | 多镜头视频 |
| `h3-r2v-heretic-enhanced.json` | 参考图 → 视频 |
| `h3-heretic-unbox-test.json` | Heretic TE 验证测试 |

### 文生视频操作
1. 加载 `h3-dense-baseline.json`
2. 找到 **Node #104 (MiniMaxH3ImageToVideo)**
3. 修改参数：
   - `prompt`: 英文提示词（格式：场景 + Camera: 镜头 + Audio: 声音）
   - `width` / `height`: 分辨率（720p = 1280×720）
   - `length`: 帧数（~124 = 5秒@24fps）
4. 点 **Queue Prompt** (Ctrl+Enter)

### 输出位置
```
/root/minnimax-h3/comfy/ComfyUI/output/
```

---

## 10. 常见问题

### Q: 下载从 HuggingFace 不落盘？
A: 禁用 Xet 并使用 wget 直接下载：
```bash
export HF_HUB_DISABLE_XET=1
wget --tries=3 -O 目标路径 HF下载URL
```

### Q: 网络不通？
A: 使用 HTTP 代理：`export http_proxy=http://your-proxy:port`

### Q: 启动报 `ModuleNotFoundError`？
A: 确保使用部署脚本创建的 venv：`/opt/minnimax-h3-venv/bin/python3`

### Q: 启动报端口占用？
A: 先 `pkill -f "main.py.*8188"` 关闭旧进程

### Q: 启动报数据库锁？
A: 删除 `user/comfyui.db` 或加 `--database-url` 指定新路径

### Q: VideoHelperSuite 报 no ffmpeg？
A: `apt-get install -y ffmpeg`

---

## 附录 A: h3_sol_engine_ports/__init__.py

```python
from .h3_fbc_node import NODE_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS
try:
    from .h3_vae_batch import install as _install_vae_batch
    _install_vae_batch()
except Exception as e:
    import logging
    logging.getLogger(__name__).warning("H3 batched VAE not installed: %s", e)
__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS"]
```

## 附录 B: 模型总大小

| 类别 | 总大小 |
|------|--------|
| HF 权重一体包 | ~91 GB |
| ModelScope 补充编码器 | ~74 GB |
| ComfyUI + Custom Nodes | ~500 MB |
| **总计下载** | **~165 GB** |
