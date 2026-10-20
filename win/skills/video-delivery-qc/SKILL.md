---
name: video-delivery-qc
description: Use when assembling, rendering, or running quality control (QC) on short videos (WeChat Channels 视频号, Douyin 抖音, Xiaohongshu 小红书) to enforce audio/video technical gates, platform UI safe zones, and visual inspection.
---

# 短视频合成、平台 UI 安全区与双层质检门禁（2026-10 满血版）

任何短视频在合成与交付给用户前，**必须通过本技能规定的平台 UI 安全区校验与 `video-qc` 双层质检门禁**。严禁未质检直接向用户宣称“成片已就绪”。

---

## 📱 1. 各短视频平台 UI 布局与引导组件坐标铁律（1080×1920 竖屏基准）

不同平台的头像、关注按钮、互动栏位置截然不同，**画引导箭头（如“点个关注”）或排布字幕时严禁张冠李戴**！

### 🟢 微信视频号（WeChat Channels）—— 1080×1920
- **账号头像 + 昵称 +「关注」按钮位置**：位于屏幕 **左下角**（进度条与文案区上方）！
  - **头像 + 昵称区**：`x: 36 ~ 320`, `y: 1460 ~ 1560`
  - **「关注」按钮核心落点**：**左下角 `x ≈ 180 ~ 260, y ≈ 1500 ~ 1540`**
  - ⛔ **绝对禁忌**：视频号的关注按钮**不在右上角、也不在右侧边栏**！凡是文案有“左下方点个关注 / 点亮关注”，引导箭头与动效框必须指向 **左下角 `(x=190, y=1510)`** 区域！
- **右侧互动栏（点赞/转发/爱心/评论四连）**：位于右侧偏下 `x: 920 ~ 1060, y: 1220 ~ 1680`。
- **底部文案、商品小黄车与进度条禁区**：`y: 1560 ~ 1920`（底部 `360px`）。
- **主字幕安全区（ASS `MarginV`）**：
  - 视频号主字幕必须放在 **`y: 1320 ~ 1440`**（对应 `PlayResY: 1920` 下 ASS 样式的 **`MarginV: 460 ~ 520`**），这样既不会压住左下角的头像/关注按钮，也不会掉进底部评论区！

### 🔴 抖音（Douyin）—— 1080×1920
- **头像 +「+关注」按钮位置**：位于 **右侧边栏上方**（`x ≈ 980, y ≈ 960 ~ 1060`）。
- **左下角文案与音乐滚动区**：`x: 30 ~ 820, y: 1500 ~ 1820`。
- **主字幕安全区**：`y: 1340 ~ 1460`（ASS `MarginV: 440 ~ 500`）。

### 📕 小红书（Xiaohongshu 视频流）—— 1080×1920
- **作者头像 +「关注」按钮**：全屏视频流中位于 **左下角昵称旁**（`x ≈ 240 ~ 340, y ≈ 1520 ~ 1580`）或顶部导航栏。
- **主字幕安全区**：`y: 1320 ~ 1440`（ASS `MarginV: 460 ~ 520`）。

---

## 🛠️ 2. FFmpeg 合成四大硬坑与标准写法（踩坑实录）

1. **时间区间表达式禁用 `and(...)`，一律用 `between(t,a,b)` 或乘法**：
   - 容器内 Debian FFmpeg 5.1+ 的 `drawbox` / `drawtext` / `overlay` 中写 `enable='and(gte(t,21),lt(t,24))'` 会直接报错：`Unknown function in 'and(gte(t,21),lt(t,24))'`！
   - **正确写法**：`enable='between(t,21.0,24.0)'` 或 `enable='gte(t,21.0)*lt(t,24.0)'`。
2. **`amix` / `sidechaincompress` 混音后必须强制转立体声（`stereo`）**：
   - 若 BGM `.wav` 或 `edge-tts` 生成的 `.mp3` 为单声道（`1 channels`），经过 `amix` 后整条成片音轨会降级为 `1 ch (mono)`。
   - **正确写法**：在音频滤镜链末尾必须加上 `aformat=sample_rates=44100:channel_layouts=stereo`（或在输出参数加 `-ac 2 -ar 44100`）。
3. **画幅等比原则（严禁 `scale=W:H` 硬拉伸）**：
   - 先用 `ffprobe -show_streams` 检查 `rotation`；若源视频与目标画幅不一致，只能用：
     - 等比裁切铺满：`scale=1080:1920:force_original_aspect_ratio=increase:flags=lanczos,crop=1080:1920,setsar=1`
     - 或背景高斯模糊填充，**任何情况下禁止直接 `scale=1080:1920` 造成人物变形**。
4. **多路 `-loop 1` 图片叠加必须加 `-framerate 30 -t <时长>`**：
   - 否则多路无限流互等会导致 FFmpeg 编码死锁。

---

## 🔍 3. 双层硬质检门禁（一键调用内置 `video-qc`）

在容器内，任何分镜或成片生成后，**直接运行内置 `/usr/local/bin/video-qc`**：

```bash
# 1. 基础技术 + 声学响度/静音 + Faster-Whisper 语音转写 + OpenCV 人脸/黑场质检
video-qc /data/michelle_output/<项目>/out/final.mp4

# 2. 带多模态视觉大模型（qwen3-vl-plus）抽帧审查字幕、UI 箭头指向与画面崩坏
video-qc /data/michelle_output/<项目>/out/final.mp4 \
  --vision-prompt "这是微信视频号9:16成片的2x2抽帧网格。请检查：1. 画面是否有黑屏或文字乱码；2. 字幕是否清晰位于中下部且未遮挡底部UI；3. 最后一帧的『左下方点个关注』引导框与箭头是否准确指向左下角。"
```

### 质检合格硬指标（Gate Checklist）
| 检查维度 | 合格标准 | 不合格处理 |
| :--- | :--- | :--- |
| **容器与编码** | `H.264 (yuv420p)` + `AAC LC`, `SAR 1:1`, `faststart` | 重新封包转码 |
| **声道与采样率** | **`channels == 2` (立体声)**, `44100 Hz` 或 `48000 Hz` | 补 `aformat=channel_layouts=stereo` |
| **综合响度 (LUFS)** | 综合响度 `I` 落在 **`-18.0 ~ -13.0 LUFS`**（标准 `-16 ± 2 LUFS`） | 调整 `loudnorm=I=-16:TP=-1.5:LRA=11` |
| **台词完整性** | `whisper_asr.text` 与预期台词一致，尾部无多余胡言乱语，无截断 | A-roll 裁掉尾部碎语或重出；B-roll 延长画面垫底时长 |
| **视觉与 UI 安全区** | `min_brightness >= 15`（无黑场），字幕不压边，视频号关注箭头指向左下角 | 调整 ASS `MarginV` 或叠加层坐标后重渲 |

> 💡 **注意**：由于主对话模型 `deepseek-v4-flash` 是纯文本模型，直接调 `read` 工具读 `.png` 会被网关忽略（提示 `Current model does not support images`）。需要看图验片时，**一律使用 `video-qc --vision-prompt "..."`**（内部自动调用已配置好的 `qwen3-vl-plus` 视觉模型）！
