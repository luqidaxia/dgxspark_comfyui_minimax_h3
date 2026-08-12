# 🚀 DGX Spark 一键部署 MiniMax H3 视频生成 — 完整开源方案（12 工作流 + Sol-Attn 加速）

## 项目简介

这是一个专为 **NVIDIA DGX Spark (GB10, Grace-Hopper)** 打造的开源部署包，让 MiniMax H3 视频生成模型在 DGX Spark 上一键运行。集成了 keys-heretic 社区的 Sol-Attention 加速优化（Blackwell 架构适配）、Heretic 无审查文本编码器、视频超分、多镜头生成等 12 个预调工作流，开箱即用。

**开源地址**: https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3

## 为什么做这个项目

MiniMax H3 是目前开源最强的视频生成模型之一，官方提供了 ComfyUI 支持。但在 DGX Spark 上部署并非一帆风顺：
- 模型权重分散在 HuggingFace、ModelScope 等多个源，总下载量 ~165GB，逐个找很费劲
- Sol-Attention 在 Blackwell (sm_121) 上需要特殊适配，社区方案散落在多个 fork 中
- GB10 统一内存架构需要合理的 `--reserve-vram` 参数，否则容易 OOM
- 12 个不同场景的工作流（文生视频 / 图生视频 / 多镜头 / 关键帧 / Heretic TE），每个参数调优都要试错

这个项目把以上所有坑都踩过并整理好了。

## 核心特性

### 1️⃣ 两种部署方式，覆盖所有场景

| 方案 | 适用 | 耗时 | 说明 |
|------|------|------|------|
| **A: 从零下载** | 全新 DGX Spark | 取决于网速 | 全部从 HuggingFace + ModelScope 自动下载 ~165GB |
| **B: 主节点克隆** | 已有部署好的机器 | **~5 分钟** | 通过 RoCE 网络 (400Gbps) 直传 ~145GB |

每种方案都提供**交互式向导**（`install_wizard.py`，带进度条、断点续传）和**无人值守脚本**（`deploy_from_scratch.sh` / `deploy_to_new_spark.sh`）。

### 2️⃣ 完整模型包（11 个模型文件）

| 模型 | 大小 | 用途 |
|------|------|------|
| diffusion_models × 2 | ~25 GB | 文生视频 + 图生视频 |
| text_encoders × 5 | ~121 GB | 含 nvFP4/INT8/BF16 三种精度 + Heretic 无审查编码器 |
| vae × 2 | ~5.5 GB | 视频 + 音频 VAE 解码器 |
| upscale_models × 2 | ~130 MB | RealESRGAN 2×/4× 视频超分 |

### 3️⃣ 12 个预调工作流

| 类别 | 工作流 | 说明 |
|------|--------|------|
| ⭐ 入门 | `h3-dense-baseline.json` | 文生视频，14 节点，最简单 |
| 完整管线 | `h3-fullstack.json` | 全流程基础版 |
| 高质量 | `h3-enhanced-fullstack.json` | Heretic TE + 超分 |
| 超分增强 | `h3-enhanced-fullstack-stockte.json` | 官方 TE + 超分 |
| Heretic 测试 | `h3-heretic-unbox-test.json` | Heretic 编码器能力验证 |
| 参考图生视频 | `h3-r2v-heretic-enhanced.json` | 图片 → 视频 |
| 参考图生视频 | `h3-r2v-stockte-enhanced.json` | 同上，官方编码器 |
| 多镜头 | `h3-multishot-enhanced.json` | Heretic TE 多场景 |
| 多镜头 | `h3-multishot-enhanced-stockte.json` | 官方 TE 多场景 |
| 多镜头一体 | `H3_Multishot_AIO.json` | 多镜头演示 |
| 多镜头记忆 | `H3_Multishot_MEMORY.json` | 长视频连续性 |
| 关键帧 | `H3_Keyframes.json` | 指定关键帧引导生成 |

### 4️⃣ Sol-Attention 加速（Blackwell 适配）

集成 keys-heretic 社区的 Sol-Attn Blackwell 预打补丁版本 + Triton 加速 + H3 FBC / 批量 VAE 节点。在 DGX Spark 上实测生成 5 秒 720p 视频约 6 分钟（详见 NVIDIA 论坛原帖讨论）。

### 5️⃣ 开箱即用的管理工具

- `status.sh` — 一键查看运行状态、磁盘、模型数量
- `restart.sh` — 一键重启 ComfyUI
- 自动生成 PID 文件和日志

## 硬件要求

| 项目 | 要求 |
|------|------|
| GPU | NVIDIA GB10 (sm_121, Grace-Hopper) |
| 系统 | Ubuntu 24.04 aarch64 |
| CUDA | 13.0+ |
| PyTorch | 2.11+ cu130 |
| 内存 | ≥ 96 GB 统一内存 |
| 磁盘 | ≥ 200 GB 剩余空间 |
| 网络 | 需访问 GitHub / HuggingFace / ModelScope |

## 快速开始（一行命令）

```bash
# SSH 到你的 DGX Spark，执行：
wget https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3/raw/master/install_wizard.py
python3 install_wizard.py
```

向导会引导你选择方案 A（从零下载）或方案 B（从已有节点克隆），然后自动完成系统依赖安装 → Python 环境 → ComfyUI + 8 个自定义节点 → 下载 165GB 模型 → 启动 ComfyUI。

部署完成后浏览器打开 `http://<机器IP>:8188`，拖入工作流 JSON，修改 prompt 参数（推荐 1280×720, 124 帧 = ~5 秒），点 Queue Prompt 即可生成。

## 提示词格式

```
场景描述。Camera: 镜头运动。Audio: 声音描述。

示例：
A futuristic city at sunset, neon lights reflecting off wet streets.
Camera: Slow dolly forward through the street. Audio: ambient city hum, distant sirens.
```

## 技术细节

- **ComfyUI**: v0.30.1，使用新版 JSON 格式（节点 ID 作为 key）
- **8 个自定义节点**: SolAttn_triton, KJNodes, Spectrum-MiniMax-H3, H3-Multishot, VideoHelperSuite, Sol-Attn Blackwell, H3 引擎端口
- **4 种文本编码器**: 官方 nvFP4 AWQ (15GB) / INT8 ConvRot (26GB) / BF16 全精度 (48GB) / Heretic 无审查 INT8 (25GB + 7GB tail)
- **启动参数**: `--reserve-vram 8` 为 GB10 统一内存预留 8GB 给系统
- **注意**: 不加 `--use-sage-attention`（Sol-Attn 代之，会冲突），EasyCache 保持关闭（R2V 不兼容）

## 相关链接

- 项目仓库: https://gitee.com/alexlu0912_admin/dgxspark_comfyui_minimax_h3
- keys-heretic 社区项目: https://github.com/drowzeys/keys-heretic-MiniMax-H3-sol-engine-more-speed-upgrades-upscaler-finish-Single-DGX-Spark
- MiniMax H3 官方 ComfyUI: https://github.com/Comfy-Org/MiniMax-H3
- NVIDIA 论坛原帖（H3 在 DGX Spark 上的测试讨论）: https://forums.developer.nvidia.com/t/it-takes-6-minutes-for-minimax-h3-to-generate-a-5-second-480p-video-on-dgx-spark-how-long-does-it-take-for-yours/379139

## 反馈

欢迎试用、提 Issue、提 PR。如果你有 DGX Spark，试试看多久能生成 5 秒视频 🎬
