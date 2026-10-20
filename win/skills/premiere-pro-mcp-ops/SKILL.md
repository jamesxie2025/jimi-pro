---
name: premiere-pro-mcp-ops
description: Use when calling, debugging, or orchestrating the Premiere Pro & After Effects MCP server (port 18999) from inside the OpenClaw Docker container.
---

# Premiere Pro & After Effects MCP 操作与排障规范

容器内的 OpenClaw 已预配置连接宿主机 `http://host.docker.internal:18999/mcp` 的 `premiere-pro` MCP 服务（共暴露 367+ 个 Premiere Pro 与 After Effects 工具，在 `exec` 沙箱中通过 `MCP.premierePro.<toolName>` 调用）。

---

## ⚡ 1. 调用 `MCP.premierePro.*` 前的 1 秒必做探活（防挂起铁律）

**绝对禁止在未检查宿主机 Premiere 状态的情况下盲目调用 `MCP.premierePro.*`！**
如果宿主机 Premiere Pro 未启动或停留在欢迎页（未打开工程），调用任何 `MCP.premierePro.*` 都会挂起等待 CEP 心跳，导致你的回合卡死 10～30 秒（返回 `status=waiting`）。

### 标准三步调用法：
```bash
# 第一步：在 shell 工具中用 1 秒检查宿主机状态
adobe-host status
```
- **情况 A（`mcp_http: true` 且 `pr_running: true` 且 `heartbeat` 正常）**：
  直接调用 `MCP.premierePro.*` 工具。
- **情况 B（`pr_running: false` 或未打开工程，而任务需要用 PR/ME）**：
  先用 `adobe-host warmup /data/.../project.prproj` 唤醒宿主机 Premiere Pro 与 Media Encoder，等待 8～12 秒后再调 `MCP.premierePro.*`。
- **情况 C（纯快速短视频交付，无需交付 `.prproj` 工程）**：
  不必等待 GUI 启动，直接用容器内 **FFmpeg + `adobe-host aerender`（如需 AE 动效）+ `video-qc`** 极速出片。

---

## 📁 2. 容器与宿主机路径转换（必看！）

`MCP.premierePro.*` 运行在 **macOS 宿主机**上，它完全不认识容器内的 `/data/...` 或 `/host/...` 路径！
传给 `MCP.premierePro.*` 的所有参数（如 `project_path`、`file_paths`、`output_path`、`preset_path`）**必须先转成 macOS 路径**：

- `/data/xxx` $\longrightarrow$ `/Users/xwxie/Public/jimi-pro/Materials/xxx`
- `/host/xxx` $\longrightarrow$ `/Users/xwxie/xxx`
- `/root/.openclaw/xxx` $\longrightarrow$ `/Users/xwxie/Public/jimi-pro/.openclaw/xxx`

不确定时，随时调用 `adobe-host to-host-path <容器路径>` 获取精确路径。

---

## 🛠️ 3. 常用核心 MCP 工具与最佳实践

1. **工程创建与重置**：
   - `create_project` 不会覆盖已打开的同路径工程（会报 `A project is already open`）。
   - 若要重建干净工程，必须先调 `close_project` 再调 `create_project`。
2. **批量导入与序列装配**：
   - 导入素材前，确保文件名带有本次迭代 tag（如 `shot_01__r1.mp4`），防止 Premiere 复用旧文件缓存。
   - 使用 `import_media` $\to$ `create_sequence_from_clips` 或 `insert_clip_to_sequence`。
3. **自动字幕与音频分析**：
   - 可先在容器内用 `faster-whisper` 生成带精确时间码的 `.srt` 或词级 JSON，再传给 `build_caption_artifact` / `create_caption_track`。
4. **Media Encoder 导出（`export_sequence`）**：
   - 导出前必须确认 `adobe-host status` 中 `me_running: true`（若为 `false`，执行 `adobe-host warmup`）。
   - `preset_path` 必须传宿主机上的 `.epr` 预设绝对路径。
   - **注意**：`export_sequence` 返回成功仅代表**已加入 Media Encoder 渲染队列**，它是边编边写的异步过程！必须轮询输出文件大小连续 2 次（间隔 3 秒）不再增长，且 `video-qc <导出文件>` 校验通过后，才算真正导出完成！

---

## 🔧 4. 常见故障自愈速查

| 故障现象 | 根因 | 一键修法 |
| :--- | :--- | :--- |
| `MCP.premierePro.*` 返回 `status=waiting` 或 `Command timed out` | 宿主机 Premiere 未打开，或停在欢迎界面未打开 `.prproj` 工程 | 运行 `adobe-host warmup /data/.../proj.prproj` 打开工程后再调 |
| 报 `401 Unauthorized` | 宿主机 `:18999` 重启后更新了 `MCP_AUTH_TOKEN` | 从 `/host/.hermes/config.yaml` 读取最新 Bearer token 更新至 `/root/.openclaw/openclaw.json` |
| `export_sequence` 报成功但目标路径一直没有 mp4 文件 | Media Encoder 未启动，或传了容器路径 `/data/...` 而非宿主机路径 `/Users/xwxie/...` | 运行 `adobe-host warmup` 启动 ME，并用 `adobe-host to-host-path` 修正输出路径 |
| AE 工具报 `Command timed out after 5000ms` | AE CEP 面板需手动点 `Start connector` | **无需走 AE MCP 面板**！直接用 `adobe-host aerender` 无头渲染 `.aep`，7 秒出片且零人工干预 |
