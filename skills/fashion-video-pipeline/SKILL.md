---
name: fashion-video-pipeline
description: A professional fashion video generation pipeline. Uses Volcengine Seedance API for AI video generation + FFmpeg post-processing (Logo, BGM, subtitles, TTS). Client-customizable.
---

# Fashion Video Pipeline（服装视频生产流水线）

## 🚫 核心准则（强制性）

### 原则 1：禁止画面凝固
- **绝对不允许**用 FFmpeg `setpts` 拉伸视频时长
- 视频时长必须在**生成阶段直接指定**（通过 API `duration` 参数或 Dreamina `--duration` 参数）
- 如果生成的视频时长略短于目标，只可接受此差异，**不做后期拉伸**

### 原则 2：强制正面面向镜头
- 所有场景的 Prompt **必须包含**面向镜头的约束
- 标准约束语：`"保持正脸面向镜头，头部不要转动，facing directly at camera, head stays still front-facing"`
- 走秀场景额外加：`"慢速行走，幅度小，确保面部始终可见"`

### 原则 3：多租户配置隔离
- 执行前必须确认 `client_name`，加载对应的 `client_<name>.json`
- 严禁混用 API Keys、Logo 素材、BGM 资源

### 原则 4：质量优先于速度
- 默认使用 `seedance2.0_vip` 模型（最高质量）
- 仅在明确要求"快速出片"时切换到 `3.5pro` 或 `3.0fast`

---

## 🎬 场景体系（8 种专业工作流）

```
用户: "给这张服装照做一个视频"
            │
    ┌───────┴───────┐
    │ 选择场景        │
    ├────────────────┤
    │ A - 正面走秀   │  → 正面迎镜走来，展示全身
    │ B - 街拍通勤   │  → 都市街景，大步行走
    │ C - 生活方式   │  → 咖啡馆/家居/度假氛围
    │ D - 产品特写   │  → 多角度展示面料/细节
    │ E - 换装连穿   │  → 连续多套衣物切换
    │ F - 促销切片   │  → 强势视觉+信息叠加
    │ G - 度假氛围   │  → 海滩/古城/度假酒店
    │ H - 品牌大片   │  → 电影级高定质感
    │ I - 已有视频   │  → 直接进入后期加工模式
    └────────────────┘
            │
    ┌───────┴───────┐
    │ 选择质量档      │
    ├────────────────┤
    │ 🚀 极速 (1-2m) │  → 720p / 4-6s / 模型 3.0fast
    │ ⚡ 标准 (3-5m)  │  → 720p / 6-10s / 模型 seedance2.0fast
    │ 💎 高质 (8-15m) │  → 1080p / 10-15s / 模型 seedance2.0_vip
    └────────────────┘
            │
    ┌───────┴───────┐
    │ 自动流水线      │
    │ ① 生成视频     │
    │ ② 下载素材     │
    │ ③ 加Logo       │
    │ ④ 混BGM        │
    │ ⑤ TTS配音      │
    │ ⑥ SRT字幕对齐  │
    └────────────────┘
```

### 场景说明（简略版，详见原 SKILL.md）

| 场景 | 适用 | 时长 |
|------|------|------|
| A 正面走秀 | 新品首发、单品展示 | 8-12s |
| B 街拍通勤 | 日常穿搭、都市时尚 | 8s |
| C 生活方式 | 种草内容、品牌调性 | 8s |
| D 产品特写 | 卖点展示 | 6s |
| E 换装连穿 | 系列产品展示 | 4-6s/段 |
| F 促销切片 | 打折促销 | 6s |
| G 度假氛围 | 度假系列 | 8s |
| H 品牌大片 | 品牌宣传片 | 10-15s |

---

## 🎤 TTS 语音合成（新版）

### 接口
```
Endpoint:   https://openspeech.bytedance.com/api/v3/tts/unidirectional
Auth:       X-Api-Key (Seed Speech API Key, 非 ark_api_key)
Resource:   seed-tts-2.0
Format:     JSON request → MP3 audio response
```

### 配置（client 配置中增加 `tts` 段）
```json
{
  "volcengine": {
    "tts": {
      "api_key": "YOUR_TTS_API_KEY_HERE",
      "voice": "zh_female_vv_uranus_bigtts",
      "resource_id": "seed-tts-2.0",
      "base_url": "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
    }
  }
}
```

### 可用音色（已实测）
| 音色 ID | 名称 | 描述 |
|---------|------|------|
| `zh_female_vv_uranus_bigtts` | VV 2.0 | 女生，官方推荐 |
| `zh_female_xiaohe_uranus_bigtts` | 小何 2.0 | 女生，通用 |
| `zh_male_m191_uranus_bigtts` | 云舟 2.0 | 男生，通用 |
| `zh_male_taocheng_uranus_bigtts` | 小天 2.0 | 男生 |
| `zh_male_liufei_uranus_bigtts` | 刘飞 2.0 | 男生 |

> 完整音色列表：[控制台音色库](https://console.volcengine.com/speech/new/voices)

### 测试命令
```bash
# 单独测试 TTS
python3 scripts/run_test.py --tts-only client_demo.json "你好，这是一段测试。" zh_female_vv_uranus_bigtts

# 列出可用音色
python3 scripts/run_test.py --list-voices
```

---

## ✅ 字幕标准（Jim 确认）
```
格式:   ASS (Advanced SubStation Alpha)
字号:   FontSize=28
字体:   WenQuanYi Micro Hei
对齐:   Alignment=2 (底部居中)
边界:   MarginL=150, MarginR=150, MarginV=30
精度:   像素级定位，不跑出屏幕
```

### ASS 字幕模板（直接可用）
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
Dialogue: 0,00:00:00,00,00:00:04,00,Sub,,0,0,0,,第一行字幕
Dialogue: 0,00:00:04,00,00:00:08,00,Sub,,0,0,0,,第二行字幕
```

### 合成命令中的 ASS 用法
```bash
# 在 FFmpeg filter_complex 中使用
[vid_logo]ass=/path/to/subtitle.ass[vid_final]
```

---

## 📝 字幕系统

支持两种字幕模式，**自动根据 TTS 文本生成 SRT 时间轴字幕**：

### 模式 1：自动 SRT 字幕（推荐）
- 提供 TTS 文本 → 自动估算每句话的时间戳
- 生成 `.srt` 文件 → FFmpeg 的 `subtitles` filter 渲染
- 逐句拆分，单行超过 40 字符自动换行

### 模式 2：简单固定文字（无 TTS 时用）
- 单行固定文字，底部居中，半透明背景框
- 通过 `drawtext` filter 渲染

### SRT 时间轴估算逻辑
- 按 `。！？.!?` 拆分为句子
- 按字符数比例分配总时长
- 中文语速基准约 3-4 字/秒
- 每段最短 0.8s
- 最终段自动对齐总时长

### 后期配置模板
```json
{
  "logo": {
    "enabled": true,
    "path": "client_logo.png",
    "position": "top-right",
    "scale": 150,
    "opacity": 0.85
  },
  "bgm": {
    "enabled": true,
    "path": "resources/bgm/xxx.mp3",
    "volume": 0.3
  },
  "tts": {
    "enabled": true,
    "text": "旁白文案",
    "voice": "zh_female_vv_uranus_bigtts"
  },
  "subtitle": {
    "enabled": true,
    "mode": "auto-srt",
    "text": "（自动从 TTS 文本生成）"
  }
}
```

---

## 🧪 测试验证

```bash
# 全链路测试 (生成 + TTS + 字幕 + Logo + BGM)
python3 scripts/run_test.py client_demo.jpg A_front_walk standard

# 禁用 TTS
python3 scripts/run_test.py client_demo.jpg A_front_walk standard --no-tts

# 仅测试 TTS
python3 scripts/run_test.py --tts-only client_demo.json "语音测试"
```

## 📁 配置体系

### 文件结构
```
skills/fashion-video-pipeline/
├── SKILL.md                ← 本文档
├── client_demo.json        ← 示例客户配置
├── config_template.json    ← 配置模板
├── resources/
│   └── bgm/                ← BGM 音频资源
└── scripts/
    ├── volcengine_client.py ← 火山引擎 API 客户端 (v3)
    ├── ffmpeg_composer.py   ← FFmpeg 后期合成器 (v3)
    └── run_test.py          ← 测试框架 (v3)
```

### 客户配置 (`client_<name>.json`)
```json
{
  "client_name": "客户名称",
  "volcengine": {
    "ark_api_key": "YOUR_ARK_KEY",
    "tts": {
      "api_key": "YOUR_TTS_KEY",
      "voice": "zh_female_vv_uranus_bigtts",
      "resource_id": "seed-tts-2.0"
    },
    "endpoints": {
      "video_gen": "ep-xxxxxxxx",
      "image_gen": "ep-xxxxxxxx"
    }
  },
  "branding": {
    "logo_path": "path/to/logo.png",
    "logo_position": "top-right",
    "font_path": "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"
  }
}
```

---

## ⚡ 火山引擎模型配置一览

```json
{
  "endpoints": {
    "video_gen": "ep-xxxxxx-xxxxxx",        // Seedance 2.0 主力视频 (对应 .env 中的 VOLC_VIDEO_GEN_ENDPOINT)
    "video_gen_mini": "ep-xxxxxx-xxxxxx",   // Seedance 2.0 Mini 快速剪辑 (对应 .env 中的 VOLC_VIDEO_GEN_MINI_ENDPOINT)
    "image_gen": "ep-xxxxxx-xxxxxx",         // Seedream 5.0 图生图 (对应 .env 中的 VOLC_IMAGE_GEN_ENDPOINT)
    "vision": "ep-xxxxxx-xxxxxx",           // Doubao 1.5 Vision 质量反关 (对应 .env 中的 VOLC_VISION_ENDPOINT)
    "embedding_vision": "ep-xxxxxx-xxxxxx"  // Doubao Embedding Vision 向量 (对应 .env 中的 VOLC_EMBEDDING_VISION_ENDPOINT)
  }
}
```

### 三模型补充说明

**① Seedance 2.0 Mini（快速剪辑）**
- 比标准版快约 2-3 倍（2-3 分钟 vs 5-8 分钟）
- 适合快速出片、批量预览、Prompt 调试
- 生成后若效果满意，可用标准版同 Prompt 跑最终视频

**② Doubao-embedding-vision（向量嵌入）**
- 多模态向量嵌入（图片+文本）
- 用于 ChromaDB/LanceDB 素材库检索
- 可按款式/颜色/风格相似度搜索

**③ Seedance 2.0 标准（主力）**
- 支持 1080p/60fps/15s
- 支持 API + Dreamina CLI 双通道
- 最终交付级质量

---

## 🔄 TTS 故障排查

| 症状 | 原因 | 解决 |
|------|------|------|
| 401/403 `invalid auth token` | X-Api-Key 不对或格式错误 | 检查 `tts.api_key` 配置 |
| `resource ID is mismatched` | 音色不属于当前 Resource-Id | 用 `_uranus_bigtts` 系列音色 |
| `requested resource not granted` | 未购买该音色 | 控制台下单或换免费音色 |
| 422/400 | Body 格式错误 | 检查 `req_params` 结构是否正确 |
