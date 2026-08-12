# DGX Spark ComfyUI + MiniMax H3 — One-Click Deploy

[🇨🇳 中文版](#中文版) | [📊 Benchmark](BENCHMARK.md) | [🔄 Gitee Mirror](https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3) | [🐙 GitHub](https://github.com/luqidaxia/dgxspark_comfyui_minimax_h3)

One-click deploy MiniMax H3 video generation on a single NVIDIA DGX Spark (GB10).

---

## ⚡ Speed Benchmark

Single DGX Spark (GB10), ComfyUI v0.30.1, 20 steps, 124 frames (~5.17s @24fps).

| Configuration | Resolution | Time | Speedup |
|---|---|---|---|
| Baseline (dense, no acceleration) | 480p (864×480) | **4 m 45 s** | 1.00× |
| Baseline (dense, no acceleration) | 720p (1280×720) | **14 m 35 s** | 1.00× |
| Sol Engine (SageAttn + SolAttn + Spectrum + FBC) | 480p | **3 m 30 s** | 1.36× |
| Sol Engine (same stack) | 720p | **9 m 00 s** | 1.62× |
| 🔥 **Sol Engine + 2× Upscale** (half-res gen) | 360p → 720p | **2 m 25 s** 🚀 | **6.03×** |

> 💡 **Key insight**: Generate at 640×360 then RealESRGAN 2× upscale to 720p — **6× faster** than direct 720p generation, exceeding the reference article's 3.92×.

📊 [Full report → BENCHMARK.md](BENCHMARK.md)

---

## Deployment Options

| Plan | Script | When to use | Data source | Time |
|---|---|---|---|---|
| **A: From scratch** | `install_wizard.py` | Fresh machine, no master | Internet download (~165 GB) | Depends on network |
| | `deploy_from_scratch.sh` | Same, non-interactive | Same | Same |
| **B: Clone from master** | `deploy_to_new_spark.sh` | Already have a master node | RoCE direct transfer | ~5 min |

> 📖 [WORKFLOWS.md](WORKFLOWS.md) — 12 workflow details.

---

## Plan A: Deploy from Scratch

For a fresh DGX Spark with nothing installed.

### Quick Start

```bash
wget https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3/raw/master/deploy_from_scratch.sh
bash deploy_from_scratch.sh
```

### Interactive Installer (Recommended)

```bash
wget https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3/raw/master/install_wizard.py
python3 install_wizard.py
```

Both plans in one wizard:

```
Welcome
  └─→ Choose plan:
       [A] From scratch — download all from HF / ModelScope (~165 GB)
       [B] Clone from master — copy from existing node (~5 min)

Shared stages:
  System deps → Python env → ComfyUI + custom nodes →
  ├─ [A] HF weights (~91 GB) → ModelScope (~74 GB)
  └─ [B] rsync models (~145 GB, RoCE 5 min)
  → Launch ComfyUI → Done
```

CLI shortcuts:

```bash
python3 install_wizard.py --yes                           # Auto, still need to choose plan
python3 install_wizard.py --proxy http://your-proxy:port  # With proxy
```

### With Proxy

```bash
PROXY=http://your-proxy:port bash deploy_from_scratch.sh
```

### Customizable Variables

| Variable | Default | Description |
|---|---|---|
| `INSTALL_DIR` | `/root/minnimax-h3` | Install root directory |
| `VENV_DIR` | `/opt/minnimax-h3-venv` | Python venv path |
| `COMFY_PORT` | `8188` | ComfyUI web port |
| `RESERVE_VRAM` | `8` | Reserved VRAM (GB), GB10 unified memory |
| `PROXY` | (empty) | HTTP proxy for HuggingFace downloads |

### Pipeline (6 Stages)

| Stage | Content | Size |
|---|---|---|
| 1. System deps | git, ffmpeg, wget, ca-certificates | ~200 MB |
| 2. Python env | venv + PyTorch 2.11+cu130 + sageattention + sqlalchemy | ~5 GB |
| 3. ComfyUI + nodes | v0.30.1 + 8 custom nodes + 12 workflows | ~1 GB |
| 4. HF weights | Diffusion + VAE + upscaler + Heretic TE + nvFP4 TE | ~91 GB |
| 5. ModelScope | INT8 + BF16 text encoders | ~74 GB |
| 6. Launch & verify | Start ComfyUI, wait HTTP 200, generate scripts | — |
| **Total** | | **~171 GB** |

### Download Sources

| Source | Contents | Size |
|---|---|---|
| HuggingFace `drowzeys/keys-heretic-...-weights` | All model weights | ~91 GB |
| ModelScope `Comfy-Org/MiniMax-H3` | INT8 + BF16 text encoders | ~74 GB |
| GitHub repos | ComfyUI + custom nodes | ~1 GB |
| PyPI | Python dependencies | ~5 GB |

### Resumable

Auto-skips completed stages on re-run:

- `models/.weights_downloaded` → skip HF download
- `~/.cache/modelscope/.../MiniMax-H3/.done` → skip ModelScope
- Existing `.git/` → skip git clone

### Post-Deploy Management

```bash
bash /root/minnimax-h3/status.sh                # Check status
bash /root/minnimax-h3/restart.sh               # Restart ComfyUI
tail -f /root/minnimax-h3/logs/comfyui.log      # Live logs
kill $(cat /root/minnimax-h3/logs/comfyui.pid)  # Stop
```

---

## Plan B: Clone from Master

Already deployed a master node? Clone to new machines in ~5 min over RoCE.

```bash
bash deploy_to_new_spark.sh <mgmt-IP> <roce-IP> [password]

# Example
bash deploy_to_new_spark.sh 10.0.0.101 10.10.0.101 your_password
```

Pipeline: probe → install deps → RoCE transfer ~145 GB → config symlinks → launch & verify.

---

## Model Inventory

| Model | Size | Directory | Purpose |
|---|---|---|---|
| `minimax_h3_fl2va_pruned_int8_convrot.safetensors` | 20 GB | `diffusion_models/` | T2V / I2V |
| `minimax_h3_ref2va_pruned_int8_convrot.safetensors` | 5 GB | `diffusion_models/` | Reference I2V |
| `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | 15 GB | `text_encoders/` | nvFP4 quantized (default) |
| `qwen3vl_32b_minimax_h3_int8_convrot.safetensors` | 26 GB | `text_encoders/` | INT8 ConvRot |
| `qwen3vl_32b_minimax_h3_bf16.safetensors` | 48 GB | `text_encoders/` | BF16 full precision |
| `qwen3vl_32b_h3_ultra_..._heretic_int8_convrot.safetensors` | 25 GB | `text_encoders/H3/` | Heretic uncensored TE |
| `qwen3vl_32b_h3_generation_tail_..._int8_convrot.safetensors` | 7 GB | `text_encoders/H3/` | Generation tail attention |
| `minimax_h3_video_vae_fp16.safetensors` | 5 GB | `vae/` | Video VAE decoder |
| `minimax_h3_audio_vae_fp32.safetensors` | 578 MB | `vae/` | Audio VAE decoder |
| `RealESRGAN_x2plus.pth` | 64 MB | `upscale_models/` | Video 2× upscale |
| `RealESRGAN_x4plus.pth` | 67 MB | `upscale_models/` | Video 4× upscale |

---

## Usage

### Quickstart

1. Open ComfyUI: `http://<machine-IP>:8188`
2. Drag a workflow JSON onto the canvas
3. Find **Node #104 (MiniMaxH3ImageToVideo)**, edit `prompt`, `width`, `height`, `length`
4. Click **Queue Prompt** (Ctrl+Enter)

### Recommended Workflows

| JSON | Type | Notes |
|---|---|---|
| `h3-dense-baseline.json` | Text-to-Video | ⭐ Simplest, start here |
| `h3-enhanced-fullstack.json` | Image-to-Video + upscale | Full pipeline |
| `h3-multishot-enhanced.json` | Multi-shot video | Multiple clips at once |
| `h3-r2v-heretic-enhanced.json` | Reference → Video | Needs reference image |
| `h3-heretic-unbox-test.json` | Heretic TE test | Verify Heretic encoder |

### Prompt Format

```
Scene description. Camera: motion. Audio: sound.

Example:
A futuristic city at sunset, neon lights reflecting off wet streets.
Camera: Slow dolly forward. Audio: ambient city hum, distant sirens.
```

### Output

```bash
/root/minnimax-h3/comfy/ComfyUI/output/
```

MP4 (H.264) or WebM, with audio track.

---

## Hardware Requirements

| Item | Requirement |
|---|---|
| GPU | NVIDIA GB10 (sm_121, Grace-Blackwell) |
| OS | Ubuntu 24.04 aarch64 |
| CUDA | 13.0+ |
| PyTorch | 2.11+ cu130 |
| Memory | ≥ 96 GB unified memory |
| Disk | ≥ 200 GB free |
| Network | GitHub, HuggingFace, ModelScope (or HTTP proxy) |

---

## FAQ

**Q: HuggingFace download slow or blocked?**

```bash
PROXY=http://your-proxy:port bash deploy_from_scratch.sh
```

**Q: Download interrupted?** → Just re-run — it auto-skips completed stages.

**Q: `ModuleNotFoundError`?** → Use the venv Python: `/opt/minnimax-h3-venv/bin/python3`

**Q: Port in use?** → `pkill -f "main.py.*8188"` then restart.

**Q: Database lock?** → `rm -f /root/minnimax-h3/comfy/ComfyUI/user/comfyui.db`

**Q: `ffmpeg not found`?** → `apt-get install -y ffmpeg`

**Q: Not enough disk?** → Point to a bigger disk:
```bash
INSTALL_DIR=/mnt/bigdisk/minnimax-h3 bash deploy_from_scratch.sh
```

---

## Directory Structure

```
/root/minnimax-h3/
├── restart.sh, status.sh          # Management scripts
├── logs/
│   ├── comfyui.log
│   └── comfyui.pid
└── comfy/
    ├── ComfyUI/
    │   ├── models/
    │   │   ├── diffusion_models/  # 2 files
    │   │   ├── text_encoders/     # + H3/ symlink
    │   │   ├── vae/               # 2 files
    │   │   └── upscale_models/    # 2 files
    │   ├── custom_nodes/          # 8 nodes
    │   └── output/                # Generated videos
    └── workflows/                 # 12 JSON files
```

---

## References

- [keys-heretic project](https://github.com/drowzeys/keys-heretic-MiniMax-H3-sol-engine-more-speed-upgrades-upscaler-finish-Single-DGX-Spark)
- [HF weights pack](https://huggingface.co/drowzeys/keys-heretic-MiniMax-H3-sol-engine-more-DGX-Spark-weights)
- [MiniMax H3 ComfyUI](https://github.com/Comfy-Org/MiniMax-H3)
- [ModelScope: Comfy-Org/MiniMax-H3](https://modelscope.cn/models/Comfy-Org/MiniMax-H3)
- [NVIDIA DGX Spark](https://www.nvidia.com/en-us/products/workstations/dgx-spark/)
- [NVIDIA Forum Discussion](https://forums.developer.nvidia.com/t/it-takes-6-minutes-for-minimax-h3-to-generate-a-5-second-480p-video-on-dgx-spark-how-long-does-it-take-for-yours/379139)

---

*Maintained by [@alexlu0912_admin](https://gitee.com/alexlu0912_admin) · MIT License*

---

---

---

# 中文版

# DGX Spark 一键部署 ComfyUI + MiniMax H3

[English](#dgx-spark-comfyui--minimax-h3--one-click-deploy) | [📊 测速报告](BENCHMARK.md) | [🌐 GitHub Mirror](https://github.com/luqidaxia/dgxspark_comfyui_minimax_h3) | [Gitee 仓库](https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3)

在单台 NVIDIA DGX Spark (GB10) 上一键部署 MiniMax H3 视频生成环境。

---

## ⚡ 生成速度基准

单 DGX Spark (GB10)，ComfyUI v0.30.1，20 steps，124 帧 (~5.17s @24fps)。

| 方案 | 分辨率 | 耗时 | 加速比 |
|---|---|---|---|
| Baseline（纯 dense，无加速） | 480p (864×480) | **4 分 45 秒** | 1.00× |
| Baseline（纯 dense，无加速） | 720p (1280×720) | **14 分 35 秒** | 1.00× |
| Sol Engine（SageAttn + SolAttn + Spectrum + FBC） | 480p | **3 分 30 秒** | 1.36× |
| Sol Engine（同上） | 720p | **9 分 00 秒** | 1.62× |
| 🔥 **Sol Engine + 2× 超分**（半分辨率生成） | 360p → 720p | **2 分 25 秒** 🚀 | **6.03×** |

> 💡 **关键发现**：以 640×360 半分辨率生成，再用 RealESRGAN 2× 超分到 720p，比直接 720p 生成快 **6 倍**，超越参考文章的 3.92×。

📊 [完整报告 → BENCHMARK.md](BENCHMARK.md)

---

## 部署方案

| 方案 | 脚本 | 适用场景 | 数据来源 | 耗时 |
|---|---|---|---|---|
| **A: 从零部署** | `install_wizard.py` | 全新机器，无主节点 | 互联网下载 (~165 GB) | 取决于网速 |
| | `deploy_from_scratch.sh` | 同上，非交互式 | 同上 | 同上 |
| **B: 主节点克隆** | `deploy_to_new_spark.sh` | 已有主节点 | RoCE 内网直传 | ~5 分钟 |

> 📖 [WORKFLOWS.md](WORKFLOWS.md) — 12 个工作流详细说明。

---

## 方案 A：从零部署

适用于全新 DGX Spark，所有文件从互联网下载。

### 快速开始

```bash
wget https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3/raw/master/deploy_from_scratch.sh
bash deploy_from_scratch.sh
```

### 交互式安装（推荐）

```bash
wget https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3/raw/master/install_wizard.py
python3 install_wizard.py
```

双方案在同一向导中：

```
欢迎页
  └─→ 选择方案:
       [A] 从零部署 — 全部从 HF / ModelScope 下载 (~165 GB)
       [B] 主节点克隆 — 从已有节点高速复制 (~5 分钟)

共用阶段:
  系统依赖 → Python 环境 → ComfyUI + 自定义节点 →
  ├─ [A] HF 权重 (~91 GB) → ModelScope (~74 GB)
  └─ [B] rsync 模型 (~145 GB, RoCE 5 分钟)
  → 启动 ComfyUI → 完成
```

命令行快捷：

```bash
python3 install_wizard.py --yes                           # 全自动，仍需选方案
python3 install_wizard.py --proxy http://你的代理:端口      # 带代理
```

### 带代理

```bash
PROXY=http://你的代理:端口 bash deploy_from_scratch.sh
```

### 可覆盖变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `INSTALL_DIR` | `/root/minnimax-h3` | 安装根目录 |
| `VENV_DIR` | `/opt/minnimax-h3-venv` | Python 虚拟环境路径 |
| `COMFY_PORT` | `8188` | ComfyUI Web 端口 |
| `RESERVE_VRAM` | `8` | 预留 VRAM (GB)，GB10 统一内存架构 |
| `PROXY` | (空) | HTTP 代理地址 |

### 流程（6 阶段）

| 阶段 | 内容 | 大小 |
|---|---|---|
| 1. 系统依赖 | git、ffmpeg、wget、ca-certificates | ~200 MB |
| 2. Python 环境 | venv + PyTorch 2.11+cu130 + sageattention + sqlalchemy | ~5 GB |
| 3. ComfyUI + 节点 | v0.30.1 + 8 个自定义节点 + 12 个工作流 | ~1 GB |
| 4. HF 权重 | Diffusion + VAE + upscaler + Heretic TE + nvFP4 TE | ~91 GB |
| 5. ModelScope | INT8 + BF16 文本编码器 | ~74 GB |
| 6. 启动验证 | 启动 ComfyUI，等待 HTTP 200，生成管理脚本 | — |
| **总计** | | **~171 GB** |

### 下载来源

| 来源 | 内容 | 大小 |
|---|---|---|
| HuggingFace `drowzeys/keys-heretic-...-weights` | 全部模型权重 | ~91 GB |
| ModelScope `Comfy-Org/MiniMax-H3` | INT8 + BF16 文本编码器 | ~74 GB |
| GitHub 仓库 | ComfyUI + 自定义节点 | ~1 GB |
| PyPI | Python 依赖 | ~5 GB |

### 断点续传

重新运行自动跳过已完成步骤：

- `models/.weights_downloaded` → 跳过 HF 下载
- `~/.cache/modelscope/.../MiniMax-H3/.done` → 跳过 ModelScope
- 已有 `.git/` → 跳过 git clone

### 部署后管理

```bash
bash /root/minnimax-h3/status.sh                # 状态检查
bash /root/minnimax-h3/restart.sh               # 重启 ComfyUI
tail -f /root/minnimax-h3/logs/comfyui.log      # 实时日志
kill $(cat /root/minnimax-h3/logs/comfyui.pid)  # 停止
```

---

## 方案 B：主节点克隆

已有一台部署好的主节点？通过 RoCE ~5 分钟克隆到新机器。

```bash
bash deploy_to_new_spark.sh <管理IP> <RoCE_IP> [密码]

# 示例
bash deploy_to_new_spark.sh 192.168.22.161 10.10.12.21 你的密码
```

流程：探路 → 装依赖 → RoCE 传 ~145 GB → 配置 symlink → 启动验证。

---

## 模型清单

| 模型文件 | 大小 | 目录 | 用途 |
|---|---|---|---|
| `minimax_h3_fl2va_pruned_int8_convrot.safetensors` | 20 GB | `diffusion_models/` | 文生视频 / 图生视频 |
| `minimax_h3_ref2va_pruned_int8_convrot.safetensors` | 5 GB | `diffusion_models/` | 参考图生视频 |
| `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | 15 GB | `text_encoders/` | nvFP4 量化（默认） |
| `qwen3vl_32b_minimax_h3_int8_convrot.safetensors` | 26 GB | `text_encoders/` | INT8 ConvRot |
| `qwen3vl_32b_minimax_h3_bf16.safetensors` | 48 GB | `text_encoders/` | BF16 全精度 |
| `qwen3vl_32b_h3_ultra_..._heretic_int8_convrot.safetensors` | 25 GB | `text_encoders/H3/` | Heretic 无审查 TE |
| `qwen3vl_32b_h3_generation_tail_..._int8_convrot.safetensors` | 7 GB | `text_encoders/H3/` | 生成尾部注意力层 |
| `minimax_h3_video_vae_fp16.safetensors` | 5 GB | `vae/` | 视频 VAE 解码器 |
| `minimax_h3_audio_vae_fp32.safetensors` | 578 MB | `vae/` | 音频 VAE 解码器 |
| `RealESRGAN_x2plus.pth` | 64 MB | `upscale_models/` | 视频 2× 超分 |
| `RealESRGAN_x4plus.pth` | 67 MB | `upscale_models/` | 视频 4× 超分 |

---

## 使用说明

### 快速上手

1. 打开 ComfyUI：`http://<机器IP>:8188`
2. 把工作流 JSON 拖入画布
3. 找到 **Node #104 (MiniMaxH3ImageToVideo)**，修改 `prompt`、`width`、`height`、`length`
4. 点 **Queue Prompt** (Ctrl+Enter)

### 推荐工作流

| JSON 文件 | 类型 | 说明 |
|---|---|---|
| `h3-dense-baseline.json` | 文生视频 | ⭐ 入门首选，最简单 |
| `h3-enhanced-fullstack.json` | 图生视频 + 超分 | 完整管线 |
| `h3-multishot-enhanced.json` | 多镜头视频 | 一次生成多个片段 |
| `h3-r2v-heretic-enhanced.json` | 参考图 → 视频 | 需要参考图 |
| `h3-heretic-unbox-test.json` | Heretic TE 测试 | 验证 Heretic 编码器 |

### 提示词格式

```
场景描述。Camera: 镜头运动。Audio: 声音描述。

示例：
A futuristic city at sunset, neon lights reflecting off wet streets.
Camera: Slow dolly forward. Audio: ambient city hum, distant sirens.
```

### 输出位置

```bash
/root/minnimax-h3/comfy/ComfyUI/output/
```

视频格式：MP4 (H.264) 或 WebM，带音频轨。

---

## 硬件要求

| 项目 | 要求 |
|---|---|
| GPU | NVIDIA GB10 (sm_121, Grace-Blackwell) |
| 系统 | Ubuntu 24.04 aarch64 |
| CUDA | 13.0+ |
| PyTorch | 2.11+ cu130 |
| 内存 | ≥ 96 GB 统一内存 |
| 磁盘 | ≥ 200 GB 剩余空间 |
| 网络 | 需访问 GitHub、HuggingFace、ModelScope（或用 HTTP 代理） |

---

## 常见问题

**Q: HuggingFace 下载慢或不通？**

```bash
PROXY=http://你的代理:端口 bash deploy_from_scratch.sh
```

**Q: 下载中断了？** → 重跑即可，自动跳过已完成的步骤。

**Q: `ModuleNotFoundError`？** → 用虚拟环境 Python：`/opt/minnimax-h3-venv/bin/python3`

**Q: 端口占用？** → `pkill -f "main.py.*8188"` 后重启。

**Q: 数据库锁？** → `rm -f /root/minnimax-h3/comfy/ComfyUI/user/comfyui.db`

**Q: `ffmpeg not found`？** → `apt-get install -y ffmpeg`

**Q: 磁盘不够？** → 指向大磁盘：
```bash
INSTALL_DIR=/mnt/bigdisk/minnimax-h3 bash deploy_from_scratch.sh
```

---

## 目录结构

```
/root/minnimax-h3/
├── restart.sh, status.sh          # 管理脚本
├── logs/
│   ├── comfyui.log                # 运行日志
│   └── comfyui.pid                # 进程 PID
└── comfy/
    ├── ComfyUI/
    │   ├── models/
    │   │   ├── diffusion_models/  # 2 个文件
    │   │   ├── text_encoders/     # + H3/ 软链接
    │   │   ├── vae/               # 2 个文件
    │   │   └── upscale_models/    # 2 个文件
    │   ├── custom_nodes/          # 8 个节点
    │   └── output/                # 生成的视频
    └── workflows/                 # 12 个 JSON 文件
```

---

## 参考链接

- [keys-heretic 项目](https://github.com/drowzeys/keys-heretic-MiniMax-H3-sol-engine-more-speed-upgrades-upscaler-finish-Single-DGX-Spark)
- [HF 权重一体包](https://huggingface.co/drowzeys/keys-heretic-MiniMax-H3-sol-engine-more-DGX-Spark-weights)
- [MiniMax H3 ComfyUI](https://github.com/Comfy-Org/MiniMax-H3)
- [ModelScope: Comfy-Org/MiniMax-H3](https://modelscope.cn/models/Comfy-Org/MiniMax-H3)
- [NVIDIA DGX Spark](https://www.nvidia.com/en-us/products/workstations/dgx-spark/)
- [NVIDIA 论坛讨论](https://forums.developer.nvidia.com/t/it-takes-6-minutes-for-minimax-h3-to-generate-a-5-second-480p-video-on-dgx-spark-how-long-does-it-take-for-yours/379139)

---

*维护者 [@alexlu0912_admin](https://gitee.com/alexlu0912_admin) · MIT License*
