---
name: video-pipeline-automation
description: Use when running the end-to-end automated video production pipeline (Dreamina/Footage -> FFmpeg segments -> AE motion graphics -> Premiere assembly -> Media Encoder export -> video-qc).
---

# 全自动视频生产线（FFmpeg 预处理 + AE 动效 + PR 装配 + ME 导出 + 双层质检）

当你需要从零生成或剪辑一条高质量商业短视频（口播片、空镜混剪、企业录屏演示片、时尚穿搭 Lookbook）时，按本技能选择最优管线。

---

## 🚀 1. 两条主力出片管线（按场景自动选择）

### 管线一：极速 AI 短视频管线（容器内闭环 + 可选 AE 动效叠加，适合 3～10 分钟快速出片）
1. **配音先行锁时长（VO-First）**：
   - 用 `edge-tts` 生成逐句配音 `vo_01.mp3 ... vo_05.mp3`；
   - 用 `ffprobe` 量出每句精确时长 $d_i$，设定分镜时长 $T_i = \max(4, \lceil d_i + 0.5 \rceil)$（单镜 $\le 5\text{s}$）。
2. **安全生成镜头（`dreamina-safe`）**：
   - 顺序调用 `dreamina-safe submit --shot-id g1 --out shots/g1.mp4 -- text2video ... --model_version=seedance2.0fast_vip`；
   - 自动记录 `metadata/shot_manifest.json`，免疫网络超时重复扣费。
3. **动态图形与花字/落版（可选 `adobe-host aerender` 或 PIL 逐帧 ProRes 4444）**：
   - 需要高级片头/单品卡/落版时，生成 `.aep` 并调 `adobe-host aerender -project ... -OMtemplate "具有 Alpha 的高品质" -output ...` 极速渲出透明叠加层。
4. **FFmpeg 标准化合成**：
   - 视频：Lanczos 等比升频 `1080×1920` + 电影感微调色（`eq` + `colorbalance` + `unsharp=5:5:0.4`）+ ASS 字幕（视频号 `MarginV >= 480`）+ 平台正确坐标的关注引导动效（视频号关注在**左下角 `(190, 1510)`**）；
   - 音频：配音 `-16 LUFS` + BGM `sidechaincompress` 自动闪避 + **末尾强制 `aformat=sample_rates=44100:channel_layouts=stereo`**。
5. **一键双层质检（`video-qc`）**：
   - 跑 `video-qc out/final.mp4 --vision-prompt "..."` 校验声道、响度、Whisper 台词完整性与画面安全区。

---

### 管线二：PR + AE + ME 工业级多轨工程管线（适合需交付 `.prproj` 工程、复杂多轨剪辑或 Apple Silicon 硬件编码）
宿主机已部署成熟的 `~/.hermes/tools/video-pipeline/pipeline.py`（实测 18 秒竖屏片 **73 秒**跑完 FFmpeg 分镜 $\to$ PR 装配 $\to$ ME 导出 $\to$ 质检）。

#### 在容器内直接一键调用：
1. 在 `/data/michelle_output/<项目目录>/spec.json` 编写项目规格文件（**注意：里面的路径全部写宿主机路径 `/Users/xwxie/Public/jimi-pro/Materials/...`，可用 `adobe-host to-host-path` 转换**）：
   ```json
   {
     "project_dir": "/Users/xwxie/Public/jimi-pro/Materials/michelle_output/2026-10-12_项目名",
     "size": [1080, 1920],
     "fps": 30,
     "shots": [
       {"src": "/Users/xwxie/Public/jimi-pro/Materials/.../shots/g1.mp4", "mode": "portrait", "dur": 5.0, "ss": 0.0},
       {"src": "/Users/xwxie/Public/jimi-pro/Materials/.../shots/g2.mp4", "mode": "portrait", "dur": 5.0, "ss": 0.0}
     ],
     "endcard": {"sec": 2.5, "title": "吉米智驱 JIMI PRO", "sub": "关注左下方 · 获取完整方案", "foot": ""},
     "music": {"src": "/Users/xwxie/Public/jimi-pro/Materials/.../audio/bgm.mp3", "ss": 0, "fade_out": 2.0, "lufs": -22},
     "output": "/Users/xwxie/Public/jimi-pro/Materials/michelle_output/2026-10-12_项目名/out/final_r1.mp4"
   }
   ```
2. 在容器内运行：
   ```bash
   adobe-host pipeline --spec /data/michelle_output/2026-10-12_项目名/spec.json --tag r1
   ```
3. 导出完成后运行容器内双层质检：
   ```bash
   video-qc /data/michelle_output/2026-10-12_项目名/out/final_r1.mp4 --vision-prompt "检查成片字幕与落版"
   ```

---

## ⛔ 2. 永远不能违反的五大铁律

1. **画幅铁律**：先用 `ffprobe -show_streams` 检查 `side_data_list` 中的 `rotation`（iPhone 竖拍常记录为 `3840×2160` + `rotation=-90`，实际显示是 `2160×3840`）。**任何情况下严禁无条件 `scale=W:H` 硬拉伸导致人脸变宽**！
2. **版本 Tag 铁律**：每次重跑必须换 `--tag`（如 `r1` $\to$ `r2`），严禁覆盖同名分镜或叠加层文件（Premiere 会拿旧缓存渲染出黑场或旧字幕）。
3. **PIL 字距铁律**：AE 的字距 `tracking` 单位是 $1/1000\text{ em}$，而 PIL 的字距是像素（`px`）。用 PIL 渲染花字时，字距一律写 `int(font_size * 0.15)`，切勿把 `200` 直接当像素传给 PIL 导致字幕超出屏幕！
4. **ebur128 响度读取铁律**：FFmpeg `ebur128` 滤镜日志开头会打印一行启动值 `I: -70.0 LUFS`，读取综合响度时**必须取最后一个匹配的 `I:` 值**（`video-qc` 已内置此逻辑）。
5. **进程清理铁律**：在容器内清理后台脚本时，**严禁执行宽泛的 `pkill -f python` 或与当前命令行包含相同字符串的 `pkill -f xxx`**（会自杀当前 subshell 导致工具报错），应使用精确的 PID（`kill -15 <pid>`）进行清理。
