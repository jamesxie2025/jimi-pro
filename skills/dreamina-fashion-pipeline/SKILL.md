---
name: dreamina-fashion-pipeline
description: 即梦(Dreamina)时尚视频生产流水线。用真人模特+服装图通过全能参考模式生成，后用FFmpeg加Logo/BGM/TTS/字幕。
---

# Dreamina Fashion Pipeline（即梦时尚视频生产流水线）

## 核心原则

### 原则 1：真人模特优先
- 即梦支持上传**真人照片**（火山引擎 Seedance API 会拦截真实人脸，Dreamina 不会）
- 优先使用 `multimodal2video`（全能参考模式）传入**模特图 + 衣服图 + 视频(可选) + 音频(可选)**
- 模特图作为主体参考，衣服图作为服装参考，模型会融合两者生成

### 原则 2：禁止画面凝固
- 时长在生成时通过 `--duration` 直接指定，不做 FFmpeg setpts 拉伸

### 原则 3：强制正面面向镜头
- Prompt 必须包含 `face front-facing, looking at camera`

### 原则 4：后期统一流水线
- TTS 使用火山引擎 Seed Speech 2.0（与 fashion-video-pipeline 共用配置）
- 字幕使用 ASS 格式精确控制边界和大小
- Logo/BGM/TTS/字幕一次合成

---

## 🎬 视频生成场景体系

### 方式 1：全能参考模式（推荐）— multimodal2video
```
用法：模特图 + 衣服图 → 直接生成视频
特点：最强质量，支持真人，支持音频/视频参考

命令示例：
dreamina multimodal2video \
  --image 模特.jpg \
  --image 衣服.jpg \
  --prompt "详细描述" \
  --duration 15 \
  --ratio "9:16" \
  --video_resolution 1080p \
  --model_version seedance2.0_vip \
  --poll 600
```

| 参数 | 值 |
|------|------|
| 输入图片 | 最多9张 (模特+衣服+场景) |
| 输入视频 | 最多3个 |
| 输入音频 | 最多3个 |
| 时长 | 4-15s |
| 分辨率 | seedance2.0_vip → 720p/1080p |
| 模型 | seedance2.0, seedance2.0fast, seedance2.0_vip, seedance2.0fast_vip |
| 宽高比 | 1:1, 3:4, 16:9, 4:3, 9:16, 21:9 |

### 方式 2：图生视频首帧 — image2video
```
用法：一张关键图片 + Prompt
适合：已有精确首帧图

命令示例：
dreamina image2video \
  --image 首帧.jpg \
  --prompt "描述" \
  --duration 15 \
  --video_resolution 1080p \
  --model_version seedance2.0_vip \
  --poll 600
```

### 方式 3：多帧故事 — multiframe2video
```
用法：多张图片 → 连贯故事视频
适合：需要过渡变化的场景
```

### 方式 4：纯文生视频 — text2video
```
用法：只有文字描述，无参考图
适合：不需要特定人物/服装的场景
```

---

## 📝 质量档位

| 档位 | 模型 | 时长 | 分辨率 | 成本 | 用途 |
|------|------|------|--------|------|------|
| 🚀 极速 | seedance2.0fast | 5s | 720p | 低 | 快速测试 |
| ⚡ 标准 | seedance2.0 | 8s | 720p | 中 | 日常使用 |
| 💎 高品质 | seedance2.0_vip | 12-15s | 1080p | 高 | 客户交付 |

---

## ✅ 字幕标准（Jim 确认）
```
格式:   ASS (Advanced SubStation Alpha)
字号:   FontSize=28 (1080p视频基准)
字体:   WenQuanYi Micro Hei
对齐:   Alignment=2 (底部居中)
边界:   MarginL=150, MarginR=150, MarginV=30
精度:   像素级定位，不跑出屏幕
```

### ASS 字幕模板
```
[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920

[V4+ Styles]
Format: Name,Fontname,Fontsize,PrimaryColour,SecondaryColour,OutlineColour,BackColour,Bold,Italic,BorderStyle,Outline,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding
Style: Sub,WenQuanYi Micro Hei,28,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,1,1,1,2,150,150,30,1

[Events]
Format: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text
Dialogue: 0,00:00:00,00,00:00:04,00,Sub,,0,0,0,,字幕内容
```

---

## 🔧 后期装配（FFmpeg 合成）

### ASS 字幕格式参数说明

ASS (Advanced SubStation Alpha) 支持精确的字幕定位，**不会跑出边界**：

```
[Script Info]
PlayResX: 1920     ← 参考分辨率宽
PlayResY: 1080     ← 参考分辨率高

[V4+ Styles]
Fontsize: 22       ← 字幕字号
MarginL: 100       ← 左边界 (px)
MarginR: 100       ← 右边界 (px)
MarginV: 30        ← 下边界 (px)
Alignment: 2       ← 底部居中
```

**字号参考（1080p 视频）：**

| 说明 | FontSize |
|------|----------|
| 极小 | 11 |
| 适中 | 22 |
| 较大 | 32 |
| 大标题 | 44 |

### 合成命令
```bash
ffmpeg -y \
  -i raw_video.mp4 \
  -i logo.png \
  -i bgm.mp3 \
  -i tts.mp3 \
  -filter_complex \
  "[1:v]scale=240:-1,format=rgba,colorchannelmixer=aa=0.85[logo];\
   [0:v][logo]overlay=W-w-15:15[vid_logo];\
   [vid_logo]ass=subtitle.ass[vid_final];\
   [2:a]volume=0.25[bgm];[3:a]volume=1.0[tts];\
   [bgm][tts]amix=inputs=2:duration=first:dropout_transition=2[aout]" \
  -map "[vid_final]" -map "[aout]" \
  -c:v libx264 -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  final.mp4
```

---

## 🎤 TTS 语音合成

复用 `fashion-video-pipeline` 的 `volcengine_client.py` TTS 功能（Seed Speech 2.0）：

```python
from scripts.volcengine_client import VolcengineClient
client = VolcengineClient("client_demo.json")
client.submit_tts_task("文本内容", "输出路径.mp3")
```

### 可用音色
| 音色 ID | 描述 |
|---------|------|
| `zh_female_vv_uranus_bigtts` | VV 2.0 (女生, 推荐) |
| `zh_female_xiaohe_uranus_bigtts` | 小何 2.0 (女生) |
| `zh_male_m191_uranus_bigtts` | 云舟 2.0 (男生) |

---

## ⚙️ 完整工作流示例

### 客户交付流程
```bash
# 1. 生成视频（全能参考模式）
dreamina multimodal2video \
  --image 模特照片.jpg \
  --image 服装照片.jpg \
  --prompt "模特描述。服装描述。场景描述。Face front-facing, looking at camera." \
  --duration 15 \
  --ratio "9:16" \
  --video_resolution 1080p \
  --model_version seedance2.0_vip \
  --poll 600

# 2. TTS 配音
python3 -c "
from scripts.volcengine_client import VolcengineClient
client = VolcengineClient('client_demo.json')
client.submit_tts_task('配音文案...', 'tts.mp3')
"

# 3. ASS 字幕（精确控制边界和字号）

# 4. FFmpeg 合成（Logo + BGM + TTS + 字幕）
```

---

## 📁 配置体系

```
skills/dreamina-fashion-pipeline/
├── SKILL.md                    ← 本文档
├── scripts/
│   └── compose.py              ← FFmpeg 合成脚本
└── resources/bgm/              ← BGM 音频
```

> TTS 和 FFmpeg 合成复用 `fashion-video-pipeline/scripts/` 目录下的 `volcengine_client.py` 和 `ffmpeg_composer.py`

---

## ⚡ 火山引擎模型配置清单

| Endpoint ID | 模型 | 用途 |
|-------------|------|------|
| `ep-xxxxxx-xxxxxx` (从 VOLC_VIDEO_GEN_ENDPOINT 读取) | Seedance 2.0 标准 | 主力视频生成 |
| `ep-xxxxxx-xxxxxx` (从 VOLC_VIDEO_GEN_MINI_ENDPOINT 读取) | Seedance 2.0 Mini | 快速剪辑/批量测试 |
| `ep-xxxxxx-xxxxxx` (从 VOLC_IMAGE_GEN_ENDPOINT 读取) | Seedream 5.0 | 图片生成/图生图 |
| `ep-xxxxxx-xxxxxx` (从 VOLC_VISION_ENDPOINT 读取) | Doubao 1.5 Vision | 质量反关/看图 |
| `ep-xxxxxx-xxxxxx` (从 VOLC_EMBEDDING_VISION_ENDPOINT 读取) | Doubao Embedding Vision | 向量嵌入/RAG检索 |

## 🚫 已知限制
1. Dreamina 每次任务消耗积分，seedance2.0_vip 15s 约消耗 495 积分
2. `multimodal2video` 上传大图较慢，需耐心等待
3. TTS 配音的文案需与字幕一致
4. 建议先用 Mini 模型测试 Prompt 效果，再跑最终长视频
