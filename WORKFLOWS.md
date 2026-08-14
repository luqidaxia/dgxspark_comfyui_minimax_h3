# MiniMax H3 工作流说明

本文档详细介绍 `workflows/` 目录下的 12 个 ComfyUI 工作流 JSON 文件。

---

## 目录

- [工作流总览](#工作流总览)
- [通用操作说明](#通用操作说明)
- [一、文生视频 (T2V/I2V)](#一文生视频-t2vi2v)
  - [h3-dense-baseline.json](#h3-dense-baselinejson)
  - [h3-fullstack.json](#h3-fullstackjson)
  - [h3-enhanced-fullstack.json](#h3-enhanced-fullstackjson)
  - [h3-enhanced-fullstack-stockte.json](#h3-enhanced-fullstack-stocktejson)
  - [h3-heretic-unbox-test.json](#h3-heretic-unbox-testjson)
- [二、参考图生视频 (R2V)](#二参考图生视频-r2v)
  - [h3-r2v-heretic-enhanced.json](#h3-r2v-heretic-enhancedjson)
  - [h3-r2v-stockte-enhanced.json](#h3-r2v-stockte-enhancedjson)
- [三、多镜头视频 (Multishot)](#三多镜头视频-multishot)
  - [h3-multishot-enhanced.json](#h3-multishot-enhancedjson)
  - [h3-multishot-enhanced-stockte.json](#h3-multishot-enhanced-stocktejson)
  - [H3_Multishot_AIO.json](#h3_multishot_aiojson)
  - [H3_Multishot_MEMORY.json](#h3_multishot_memoryjson)
- [四、关键帧视频 (Keyframes)](#四关键帧视频-keyframes)
  - [H3_Keyframes.json](#h3_keyframesjson)
- [文本编码器选择指南](#文本编码器选择指南)
- [节点类型速查](#节点类型速查)

---

## 工作流总览

| 工作流 | 类型 | 节点数 | 文本编码器 | 超分 | 推荐场景 |
|--------|------|--------|-----------|------|----------|
| `h3-dense-baseline.json` | T2V/I2V | 14 | Heretic INT8 | ❌ | ⭐ **入门首选** |
| `h3-i2v-firstframe-enhanced.json` | I2V | 21 | Heretic INT8 | ✅ | ⭐ **首帧驱动图生视频** |
| `h3-fullstack.json` | T2V/I2V | 16 | Heretic INT8 | ❌ | 完整管线基础版 |
| `h3-enhanced-fullstack.json` | T2V/I2V | 20 | Heretic INT8 | ✅ | 高质量图生视频 |
| `h3-enhanced-fullstack-stockte.json` | T2V/I2V | 20 | 官方 nvFP4 | ✅ | 同上，用官方编码器 |
| `h3-heretic-unbox-test.json` | T2V/I2V | 20 | Heretic INT8 | ✅ | Heretic 能力验证 |
| `h3-r2v-heretic-enhanced.json` | R2V | 22 | Heretic INT8 | ✅ | 参考图→视频 |
| `h3-r2v-stockte-enhanced.json` | R2V | 22 | 官方 nvFP4 | ✅ | 同上，用官方编码器 |
| `h3-multishot-enhanced.json` | 多镜头 | 13 | Heretic INT8 | ✅ | 多场景连续生成 |
| `h3-multishot-enhanced-stockte.json` | 多镜头 | 13 | 官方 nvFP4 | ✅ | 同上，用官方编码器 |
| `H3_Multishot_AIO.json` | 多镜头 | 11 | (旧格式) | ❌ | 多镜头演示 |
| `H3_Multishot_MEMORY.json` | 多镜头+记忆 | 12 | (旧格式) | ❌ | 长视频连续性 |
| `H3_Keyframes.json` | 关键帧 | 19 | (旧格式) | ❌ | 指定帧引导 |

> **新格式**: 节点 ID 作为 JSON key（推荐）。**旧格式**: `nodes` 数组（兼容旧 ComfyUI），使用 GGUF 量化模型。标记为"旧格式"的工作流在新版 ComfyUI 加载后会自动升级格式。

---

## 通用操作说明

### 加载工作流

1. 浏览器打开 `http://<服务器IP>:8188`
2. 直接把 `.json` 文件**拖入** ComfyUI 画布，或点击菜单 `Workflow → Open`
3. 确认右下角 Queue 区域显示 "Queue size: 0"

### 生成视频

1. 找到标注 Prompt 的节点（通常是画布中间的 `MiniMaxH3ImageToVideo` 或 `H3MultishotSampler`）
2. 修改 prompt 文本和参数
3. 点击右上角 **Queue Prompt**（快捷键 `Ctrl+Enter`）

### 修改分辨率

默认 864×480 (480p)。修改生成节点中的 `width` 和 `height`：

| 画质 | 分辨率 | 帧数推荐 | 预估耗时* |
|------|--------|----------|-----------|
| 480p | 864×480 | 124 | ~6 分钟 |
| 720p | 1280×720 | 124 | ~12 分钟 |
| 1080p | 1920×1080 | 124 | ~25 分钟 |

> *基于 DGX Spark (GB10) 单卡实测，Heretic 文本编码器 + INT8 扩散模型。

### 输出位置

```
/root/minnimax-h3/comfy/ComfyUI/output/
```

文件格式为 MP4 (H.264)，含视频轨和音频轨。

---

## 一、文生视频 (T2V/I2V)

所有文生视频工作流都以 `MiniMaxH3ImageToVideo` (Node #104) 为核心节点。

---

### h3-i2v-firstframe-enhanced.json

```
⭐ I2V 首帧驱动 — 完整加速栈 + 2× 超分 (640×360 → 720p)
```

| 属性 | 值 |
|------|-----|
| 类型 | 图生视频（I2V 首帧驱动） |
| 节点数 | 21 |
| 文本编码器 | Heretic INT8 ConvRot |
| 核心节点 | `MiniMaxH3ImageToVideo` (Node #104) + `LoadImage` (Node #137) |
| 扩散模型 | `minimax_h3_fl2va_pruned_int8_convrot`（fl2va） |
| 默认分辨率 | 640×360 → 2× 超分 → 1280×720 |

**结构**:

```
LoadImage #137 (首帧图) ──→ MiniMaxH3ImageToVideo #104 → Spectrum → 超分 → 输出
                                 ↑
H3ModelLoader ──────────────────→ |  (fl2va 扩散模型)
H3CLIPLoader (Heretic) ─────────→ |
                              (first_frame 锚定第 0 帧)
```

**使用方法**:

1. 把首帧图放到 `ComfyUI/input/first_frame.png`
2. 加载工作流，替换 Node #137 的图片名
3. 修改 Node #104 的 `prompt`（描述从首帧演化的画面）
4. 可选：再连一张图到 `last_frame` 实现「首尾帧中间过渡」
5. Queue Prompt

**与 T2V 的关系**: 不接 `first_frame`/`last_frame` 时，该节点即退化为纯文生视频（T2V）。

**与 R2V 的区别**: I2V 把图当作「关键帧」锚定第 0 帧（fl2va 模型）；R2V 把图当作「参考」用 `<Picture i>` 标签引用（ref2va 模型）。详见 [I2V.md](I2V.md)。

---

### h3-dense-baseline.json

```
⭐ 入门首选 — 最简洁的基线工作流
```

| 属性 | 值 |
|------|-----|
| 类型 | 文生视频 / 图生视频 |
| 节点数 | 14 |
| 文本编码器 | Heretic INT8 ConvRot |
| 核心节点 | `MiniMaxH3ImageToVideo` (Node #104) |
| 默认分辨率 | 864×480, 124帧 |
| 默认 prompt | 咖啡杯在雨窗前的蒸汽特写 |

**结构**:

```
H3ModelLoader → MiniMaxH3ImageToVideo → 视频输出
H3CLIPLoader ↗          ↑
                    (prompt文本)
```

最简管线，不包含 Spectrum 优化或超分。适合：
- 第一次测试部署是否正常
- 快速验证 prompt 效果
- 了解最基础的节点连接方式

**如何使用图生视频模式（I2V 首帧驱动）**:
- 加载 `LoadImage` 节点（右键画布 → Add Node → image → LoadImage）
- 将图片输出连接到 Node #104 的 `first_frame` 输入（首帧锚定第 0 帧）
- 可选：再连一张图到 `last_frame` 输入（尾帧锚定末帧，中间自动过渡）
- 无需在 prompt 中用 `<Picture>` 标签（那是 R2V 参考图的用法，见下文）
- 完整说明见 [I2V.md](I2V.md)

---

### h3-fullstack.json

```
完整基础管线 — 含 H3FirstBlockCache 加速
```

| 属性 | 值 |
|------|-----|
| 类型 | 文生视频 / 图生视频 |
| 节点数 | 16 |
| 文本编码器 | Heretic INT8 ConvRot |
| 核心节点 | `MiniMaxH3ImageToVideo` (Node #104) |
| 特色 | `H3FirstBlockCache` 性能优化 |

**相比 baseline 的增强**:

| 节点 | 类型 | 作用 |
|------|------|------|
| Node #8 | `H3FirstBlockCache` | 缓存扩散首块结果，大幅加速多帧生成 |

适合需要更稳定性能的生产使用。

---

### h3-enhanced-fullstack.json

```
增强完整管线 — Heretic TE + Spectrum + 超分
```

| 属性 | 值 |
|------|-----|
| 类型 | 文生视频 / 图生视频 |
| 节点数 | 20 |
| 文本编码器 | Heretic INT8 ConvRot |
| 核心节点 | `MiniMaxH3ImageToVideo` (Node #104) |
| 特色 | `SpectrumApplyMiniMaxH3` 频域优化 + ESRGAN 2× 超分 |

**增强节点**:

| 节点 | 类型 | 作用 |
|------|------|------|
| Node #8 | `H3FirstBlockCache` | 首块缓存加速 |
| Node #51 | `SpectrumApplyMiniMaxH3` | 频域噪声调度优化，提升画质和速度 |
| 超分链 | `UpscaleModelLoader` + `ImageUpscaleWithModel` | ESRGAN 2× 超分，将 480p 升到 960p |

适合追求最高画质的生成场景。注意超分会增加额外 ~2 分钟处理时间。

---

### h3-enhanced-fullstack-stockte.json

```
增强完整管线 — 官方文本编码器版
```

| 属性 | 值 |
|------|-----|
| 类型 | 文生视频 / 图生视频 |
| 节点数 | 20 |
| 文本编码器 | 官方 nvFP4 AWQ |
| 核心节点 | `MiniMaxH3ImageToVideo` (Node #104) |
| 特色 | 同 `h3-enhanced-fullstack.json`，仅编码器不同 |

和 `h3-enhanced-fullstack.json` 结构完全一样，区别在于使用 Comfy-Org 官方发布的 nvFP4 文本编码器而非 Heretic。适合：
- 需要官方推荐的稳定配置
- 对比 Heretic 和官方编码器的画质差异
- Heretic 在某些场景下输出不可用时回退

---

### h3-heretic-unbox-test.json

```
Heretic 文本编码器能力验证
```

| 属性 | 值 |
|------|-----|
| 类型 | 文生视频 / 图生视频 |
| 节点数 | 20 |
| 文本编码器 | Heretic INT8 ConvRot |
| 核心节点 | `MiniMaxH3ImageToVideo` (Node #104) |
| 默认 prompt | 类产品测评风格的内容展示 |

结构和 `h3-enhanced-fullstack.json` 相同，但 prompt 设计用于测试 Heretic 编码器对特定内容风格的处理能力。部署后可用此工作流验证 Heretic TE 是否正常工作：

1. 加载后直接 Queue Prompt
2. 观察生成视频的内容质量和风格
3. 确认没有报错（特别是 CLIPLoader 加载 Heretic 模型时）

---

## 二、参考图生视频 (R2V)

R2V (Reference-to-Video) 以 `MiniMaxH3ReferenceToVideo` 为核心，支持用参考图控制视频中的角色/物体外观。

---

### h3-r2v-heretic-enhanced.json

```
R2V 增强版 — 2 张参考图 + Heretic TE + 超分
```

| 属性 | 值 |
|------|-----|
| 类型 | 参考图生视频 |
| 节点数 | 22 |
| 文本编码器 | Heretic INT8 ConvRot |
| 核心节点 | `MiniMaxH3ReferenceToVideo` (Node #136) |
| 参考图 | 2 张 (`LoadImage` Node #137, #139) |
| 默认分辨率 | 864×480, 124帧 |

**结构**:

```
LoadImage #137 (参考图1) ──→ MiniMaxH3ReferenceToVideo → Spectrum → 超分 → 输出
LoadImage #139 (参考图2) ──→      ↑
H3ModelLoader ──────────────────→  |
H3CLIPLoader (Heretic) ─────────→  |
                              (prompt 含 <Picture 1> <Picture 2>)
```

**默认参考图**: `red_superboy_on_city_roof.png` + `mecha_dragon_lightning.png`

**使用方法**:

1. 加载工作流
2. 替换 Node #137 和 #139 的图片为你的参考图
3. 修改 Node #136 中的 prompt，用 `<Picture 1>`、`<Picture 2>` 引用对应图片
4. 设置 `ref_image_size`: `match`（保持原图比例）或 `crop`（裁切到生成分辨率）
5. Queue Prompt

**prompt 模板**:

```
[风格描述]。Use <Picture 1> as [角色A] and <Picture 2> as [角色B/风格]。
CUT 1: [场景和镜头描述]。Audio: [声音描述]。
TRANSITION: [转场方式]。
CUT 2: [第二个场景描述]。Audio: [声音描述]。
```

---

### h3-r2v-stockte-enhanced.json

```
R2V 增强版 — 官方文本编码器版
```

| 属性 | 值 |
|------|-----|
| 类型 | 参考图生视频 |
| 节点数 | 22 |
| 文本编码器 | 官方 nvFP4 AWQ |
| 核心节点 | `MiniMaxH3ReferenceToVideo` (Node #136) |

与 `h3-r2v-heretic-enhanced.json` 结构相同，仅编码器不同。适合需要官方稳定编码器的场景。

---

## 三、多镜头视频 (Multishot)

多镜头工作流以 `H3MultishotSampler` 为核心，一个 prompt 脚本即可生成多个连续镜头，镜头之间自然过渡。

---

### h3-multishot-enhanced.json

```
多镜头增强版 — 3 镜头 + Heretic TE + 超分
```

| 属性 | 值 |
|------|-----|
| 类型 | 多镜头视频 |
| 节点数 | 13 |
| 文本编码器 | Heretic INT8 ConvRot |
| 核心节点 | `H3MultishotSampler` (Node #200) |
| 镜头数 | 3 个 |
| 每镜头帧数 | 124 |
| 步数 | 20 |

**script 格式**（在 Node #200 的 `script` 字段中）:

```
[镜头1的描述。Camera: 镜头运动。Audio: 声音。]
---
[镜头2的描述。Camera: 镜头运动。Audio: 声音。]
---
[镜头3的描述。Camera: 镜头运动。Audio: 声音。]
```

三个镜头用 `---` 分隔。每个镜头的 prompt 格式与单镜头完全相同。

**默认 script**: 雨夜霓虹灯街道 → 侦探特写 → 照片特写，三镜头连续叙事。

**关键参数**:

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `script` | 3 段文本 | 镜头描述，`---` 分隔 |
| `width × height` | 864×480 | 每个镜头的分辨率 |
| `frames_per_shot` | 124 | 每个镜头的帧数 |
| `steps` | 20 | 采样步数 |
| `seed` | 42 | 随机种子 |
| `seed_per_shot` | True | 每个镜头使用独立种子（确保多样性） |

**输出**: 单个 MP4 文件，包含 3 个连续镜头，镜头间有自然转场。

---

### h3-multishot-enhanced-stockte.json

```
多镜头增强版 — 官方文本编码器版
```

| 属性 | 值 |
|------|-----|
| 类型 | 多镜头视频 |
| 节点数 | 13 |
| 文本编码器 | 官方 nvFP4 AWQ |

与 `h3-multishot-enhanced.json` 相同，用官方编码器。适合需要稳定、可预测输出的场景。

---

### H3_Multishot_AIO.json

```
多镜头 All-in-One (旧格式)
```

| 属性 | 值 |
|------|-----|
| 类型 | 多镜头视频 |
| 格式 | 旧格式（自动升级） |
| 节点数 | 11 |
| 模型 | GGUF 量化 (Q5_1) |

使用旧版 ComfyUI 格式，包含一个完整的演示 prompt（3 镜头产品演示视频）。加载到新版 ComfyUI 后会自动转换格式。

**特色**: `H3OptionalImage` 节点允许设置起始画面图片，适合需要从指定画面开始的场景。

---

### H3_Multishot_MEMORY.json

```
多镜头 + 记忆连续性 (旧格式)
```

| 属性 | 值 |
|------|-----|
| 类型 | 多镜头 + 记忆 |
| 格式 | 旧格式 |
| 节点数 | 12 |
| 核心节点 | `H3MultishotMemorySampler` |

相比普通 `H3MultishotSampler`，Memory 版本在镜头间传递视觉记忆，确保：
- 角色外观保持一致性
- 场景元素持续存在
- 适合较长叙事（5+ 镜头）

**适用场景**: 短视频剧情、产品系列展示、角色驱动的叙事。

---

## 四、关键帧视频 (Keyframes)

---

### H3_Keyframes.json

```
关键帧引导视频 (旧格式)
```

| 属性 | 值 |
|------|-----|
| 类型 | 关键帧视频 |
| 格式 | 旧格式 |
| 节点数 | 19 |
| 核心节点 | `H3Keyframes` |
| 关键帧位置 | 0%, 50%, 100% |
| 默认分辨率 | 544×960 (9:16 竖屏) |

**结构**:

```
H3ModelLoader (GGUF) ──→ H3Keyframes (含3个关键帧描述) → 输出
H3CLIPLoader (GGUF) ──→     ↑
                    (Anchor strength 控制)
```

三个关键帧各有一组独立描述：
- **position 0** (0%): 开场帧 — 后院秋千的广角黄昏镜头
- **position 0.5** (50%): 中间帧 — (默认与开场相同)
- **position 1** (100%): 结束帧 — (默认与开场相同)

**关键参数**:

| 参数 | 说明 |
|------|------|
| `keyframe position` | 0–1，该关键帧在视频时间轴中的位置 |
| `Anchor strength` | 0–1，关键帧约束力度。1.0 = 严格匹配，0 = 自由生成 |
| `width × height` | 分辨率 |
| `frames` | 总帧数 |

**使用场景**:
- 指定视频开头和结尾的精确画面
- 中间过程由 AI 自动过渡
- 竖屏格式适合社交媒体短视频

> 修改每个关键帧的 prompt 来控制不同时间点的画面内容。减小 Anchor strength 可以给 AI 更多自由发挥空间。

---

## 文本编码器选择指南

| 编码器 | 文件 | 大小 | 优势 | 劣势 |
|--------|------|------|------|------|
| **Heretic INT8 ConvRot** | `H3/qwen3vl_32b_h3_ultra_uncensored_heretic_int8_convrot.safetensors` | 25 GB | 画质更丰富，内容限制少 | 偶尔输出不稳定 |
| **官方 nvFP4 AWQ** | `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | 15 GB | 官方推荐，稳定可靠 | 有内容过滤 |
| **官方 INT8 ConvRot** | `qwen3vl_32b_minimax_h3_int8_convrot.safetensors` | 26 GB | 质量与速度平衡 | 需从 ModelScope 单独下载 |
| **官方 BF16** | `qwen3vl_32b_minimax_h3_bf16.safetensors` | 48 GB | 最高精度 | 最慢，占内存大 |

**命名规律**:
- 文件名含 `heretic` → Heretic 编码器
- 文件名含 `stockte` / `nvfp4` → 官方编码器
- 无特殊标记的工作流 → 默认使用 Heretic

---

## 节点类型速查

> 以下为各工作流中涉及的关键节点说明。在 ComfyUI 画布中右键可搜索添加。

| 节点类型 | 功能 | 所在工作流 |
|----------|------|-----------|
| `MiniMaxH3ImageToVideo` | H3 核心生成节点，文生视频/图生视频 | T2V 系列 |
| `MiniMaxH3ReferenceToVideo` | H3 参考图生视频，用图片控制画面 | R2V 系列 |
| `H3MultishotSampler` | 多镜头批量生成 | Multishot 系列 |
| `H3MultishotMemorySampler` | 多镜头 + 视觉记忆连续性 | `H3_Multishot_MEMORY` |
| `H3Keyframes` | 关键帧引导生成 | `H3_Keyframes` |
| `H3ModelLoaderAny` | 加载扩散模型（safetensors 或 GGUF） | 所有工作流 |
| `H3CLIPLoader` | 加载文本编码器 | 所有工作流 |
| `H3FirstBlockCache` | 扩散首块缓存加速 | Enhanced / Fullstack |
| `SpectrumApplyMiniMaxH3` | 频域噪声调度优化 | Enhanced 系列 |
| `H3OptionalImage` | 可选的起始图片节点 | Multishot 旧格式 |
| `ImageUpscaleWithModel` | ESRGAN 图像超分 | Enhanced 系列 |

---

## 工作流选择决策树

```
需要生成什么？
│
├── 单段视频 (文生视频)
│   ├── 快速测试/入门 ──→ h3-dense-baseline.json
│   ├── 追求质量 ──→ h3-enhanced-fullstack.json
│   └── 用官方编码器 ──→ h3-enhanced-fullstack-stockte.json
│
├── 用参考图控制画面
│   ├── Heretic 编码器 ──→ h3-r2v-heretic-enhanced.json
│   └── 官方编码器 ──→ h3-r2v-stockte-enhanced.json
│
├── 多个连续镜头
│   ├── 新格式 + 超分 ──→ h3-multishot-enhanced.json
│   ├── 新格式 + 官方编码器 ──→ h3-multishot-enhanced-stockte.json
│   └── 长视频需要连续性 ──→ H3_Multishot_MEMORY.json
│
└── 精确控制视频首尾帧
    └── H3_Keyframes.json
```
