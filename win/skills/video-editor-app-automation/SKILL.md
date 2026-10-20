---
name: video-editor-app-automation
description: Use when scripting or driving Adobe Premiere Pro (PR), After Effects (AE), Media Encoder (ME), or DaVinci Resolve on the macOS host from inside the OpenClaw Docker container.
---

# 跨容器驱动宿主机 PR + AE + ME 与 DaVinci Resolve 黄金指南

你运行在 Linux Docker 容器（`jimi-agent-pro`）内，而 **Premiere Pro 2024 / After Effects 2024 / Media Encoder 2024 / DaVinci Resolve 21** 运行在 **macOS 宿主机（`host.docker.internal`）** 上。
使用本技能可以让你在容器内 **1 秒探活、免密穿透、零超时挂起** 地高效指挥宿主机上的 PR + AE + ME 协同出片。

---

## 🌉 1. 跨容器与宿主机三大穿透通道（核心基石）

### 通道 A：内置桥接命令行 `adobe-host`（首选神器，在容器 bash 内直接运行）
容器已预装 `/usr/local/bin/adobe-host`，封装了 SSH 免密穿透、进程探活、应用唤醒、路径转换与无头渲染：

```bash
# 1. 1秒内检查宿主机 18999 MCP 桥、PR/AE/ME 是否在跑、CEP 心跳是否就绪
adobe-host status

# 2. 将容器内路径 (/data/... 或 /host/...) 转换为 macOS 宿主机绝对路径 (/Users/xwxie/...)
adobe-host to-host-path /data/michelle_output/2026-10-12_视频/out/final.mp4
# 输出: /Users/xwxie/Public/jimi-pro/Materials/michelle_output/2026-10-12_视频/out/final.mp4

# 3. 一键唤醒宿主机 Premiere Pro + Media Encoder（可选传入 .prproj 工程路径直接打开工程，跳过欢迎页！）
adobe-host warmup /data/michelle_output/2026-10-12_视频/pr/project.prproj

# 4. 跨容器直接调用宿主机 After Effects 无头渲染器 (aerender)，自动转换容器路径！
adobe-host aerender \
  -project /data/michelle_output/2026-10-12_视频/ae/gfx.aep \
  -comp "GFX_MAIN" \
  -OMtemplate "具有 Alpha 的高品质" \
  -output /data/michelle_output/2026-10-12_视频/ae/gfx_overlay.mov

# 5. 跨容器直接调用宿主机 Hermes 一键成片管线 (FFmpeg 分镜 -> PR 装配 -> ME 编码 -> 质检)
adobe-host pipeline --spec /data/michelle_output/2026-10-12_视频/spec.json --tag r1
```

### 通道 B：路径映射铁律（100% 避免“文件找不到”）
**凡是传给 Premiere MCP 工具（`MCP.premierePro.*`）、AE `.jsx` 脚本、或 Media Encoder 的路径，必须是 macOS 宿主机绝对路径，严禁直接传容器内的 `/data/...` 或 `/host/...`！**
| 容器内路径 | 对应的 macOS 宿主机真实路径 | 转换命令 |
| :--- | :--- | :--- |
| `/data/<子路径>` | `/Users/xwxie/Public/jimi-pro/Materials/<子路径>` | `adobe-host to-host-path /data/...` |
| `/host/<子路径>` | `/Users/xwxie/<子路径>` | `adobe-host to-host-path /host/...` |
| `/root/.openclaw/<子路径>` | `/Users/xwxie/Public/jimi-pro/.openclaw/<子路径>` | `adobe-host to-host-path /root/.openclaw/...` |

### 通道 C：Premiere Pro MCP (`http://host.docker.internal:18999/mcp`)
- ⛔ **防挂起铁律（为什么直接调 `MCP.premierePro.*` 会卡 20 秒 `status=waiting`？）**：
  - 当宿主机 Premiere Pro **未启动**，或**停留在欢迎页（未打开任何 `.prproj` 工程）**时，CEP 插件没有上下文，所有 `MCP.premierePro.*` 调用都会一直阻塞等待直到超时！
  - **正确姿势**：在调任何 `MCP.premierePro.*` 工具前，**必须先在 shell 中跑一次 `adobe-host status`**：
    - 如果 `pr_running: false`，先跑 `adobe-host warmup` 启动 PR+ME，或直接走容器内 FFmpeg 管线；
    - 确认 `pr_running: true` 且已打开工程后，再调 `MCP.premierePro.*`。

---

## 🎬 2. PR + AE + ME 黄金分工（什么时候用谁？最高效组合）

不要拿 AE 压正片像素，也不要拿 ExtendScript 循环做上千次慢速 DOM 操作。最优工业流水线分工如下：

| 阶段 | 负责工具 | 为什么这样分工最快最好 |
| :--- | :--- | :--- |
| **1. 镜头预处理与粗剪归一化** | **容器内 FFmpeg** | 极速完成镜头裁切、等比缩放（`1080×1920`）、光流补帧、声道与采样率对齐（`44.1kHz stereo`），每个文件带上版本后缀（如 `seg_01__r1.mp4`）。 |
| **2. 高级动态图形 / 花字 / 落版** | **宿主机 After Effects (`aerender`)** | 片头动效、单品卡、丝滑运动图形或落版用 `.jsx` 生成 `.aep` 后，通过 `adobe-host aerender -OMtemplate "具有 Alpha 的高品质"` 渲染出 **ProRes 4444 带透明通道 `.mov`**（90 帧仅需 **7 秒**！）。 |
| **3. 多轨时间线装配与可编辑工程交付** | **Premiere Pro MCP** 或 **Jimi XML Bridge** | 将分镜轨（V1）、AE 透明动效叠加轨（V2）、落版、配音轨（A1）、自动闪避 BGM 轨（A2）装配为标准 `.prproj` 或 FCP XML，既能自动出片，又能留给剪辑师二次精修。 |
| **4. 硬件加速批量编码导出** | **宿主机 Media Encoder (ME)** | 调 `MCP.premierePro.export_sequence`（指定宿主机 `.epr` 预设绝对路径），调用 Apple Silicon M 系列芯片硬件编码器极速导出 H.264 成片。 |

---

## ⚠️ 3. Adobe 三件套避坑铁律（实战血泪总结）

1. **同名素材 / 同名序列不刷新坑（Premiere 必踩）**：
   - Premiere 对已导入的同名文件有缓存，原路径覆盖重渲后 PR 仍拿旧缓存（甚至出黑场）；序列同名会导致工程里堆叠多个同名序列，`export_sequence` 导错序列。
   - **修法**：每次迭代重跑必须换 `--tag`（如 `seg_01__r1.mp4` $\to$ `seg_01__r2.mp4`），并在重新装配前删除旧同名序列。
2. **AE 脚本“静默不写文件”与 `{no current context}`**：
   - `adobe-host warmup` 已自动帮你开启 AE 首选项中的 `Pref_SCRIPTING_FILE_NETWORK_SECURITY = 1` 并关闭欢迎页 `Show Welcome Screen = 00`。
   - 写 `.jsx` 脚本时：**不要用 `app.beginUndoGroup()`**（报错中断会弹出模态框把 AE 彻底卡死），**不要用 `alert()`**，所有 `addSolid` 的宽高参数必须用 `Math.round()` 转为整数！
   - 渲染一律走命令行 `adobe-host aerender`，不要靠脚本里的 `renderQueue.render()`。
   - 本机中文版 AE `aerender` 实测可用的两个输出模块模板名：
     - `-OMtemplate "具有 Alpha 的高品质"`（输出带透明通道的 ProRes 4444 `.mov`，供 PR V2 轨道叠加）
     - `-OMtemplate "无损"`（输出不透明无损 `.mov`）
3. **AE 带 Alpha 的 ProRes 4444 叠加发白坑**：
   - 若把 AE 渲出的 ProRes 4444 直接丢给 FFmpeg `overlay` 滤镜，会因预乘 Alpha 语义导致全片像蒙了一层白纱。
   - **修法**：要么导入 **Premiere Pro 的 V2 轨道**（PR 原生正确识别 Adobe 预乘 Alpha），要么在 FFmpeg 中加 `premultiply=inplace=1` 或直接用黑底走 `blend=all_mode=screen`。
4. **Media Encoder 导出前必须确认 `me_running: true`**：
   - 若 Media Encoder 未启动，`export_sequence` 接口虽然返回成功，但永远不会产出文件。导出前跑一次 `adobe-host warmup` 即可确保 ME 在后台就绪。
