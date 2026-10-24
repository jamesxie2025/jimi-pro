# 吉米·智驱 (Jimi Agent Pro) — Windows 专享版部署指南

本目录 (`win/`) 为 **吉米·智驱 (Jimi Agent Pro - OpenClaw `2026.10.1`)** 的 **Windows (`linux/amd64`) 独立架构版本**，针对 Windows 10/11 (WSL2 + Docker Desktop) 及跨系统文件挂载（virtiofs / NTFS / 9p）进行了深度兼容与防死锁优化。

---

## 📦 官方预构建镜像（GitHub Container Registry · 免登录直接拉取）

| 标签说明 | 镜像地址 (`docker pull`) |
| :--- | :--- |
| **当前稳定版（推荐）** | `ghcr.io/jamesxie2025/jimi-pro:2026.10.1` |
| **最新版本** | `ghcr.io/jamesxie2025/jimi-pro:latest` |
| **Windows 架构显式标签** | `ghcr.io/jamesxie2025/jimi-pro:2026.10.1-amd64` |
| **Windows 算力底座镜像** | `ghcr.io/jamesxie2025/jimi-pro:base-env-amd64` |

---

## 🚀 Windows 一键安装与启动步骤

### 1. 准备 Docker Desktop
1. 安装并启动 **Docker Desktop for Windows**（确保在 Settings -> General 中勾选 `Use the WSL 2 based engine`）。
2. 将本 `win` 文件夹下载到本地电脑（例如 `D:\jimi-pro\win`）。

### 2. 配置 `.env` 并一键启动
1. 双击运行 **`run.bat`**（或在 PowerShell 中运行 `.\run.ps1`）。
2. 首次运行时会自动从 `.env.example` 生成 `.env` 配置文件。用记事本打开 `.env`：
   * 填写 `DEEPSEEK_API_KEY`（必填）
   * 填写 `EMBEDDING_API_KEY`（硅基流动向量检索 Key，推荐）
   * 根据电脑物理内存（8G / 16G / 32G）核对 `MEM_LIMIT` 与 `NODE_MEM_LIMIT`
3. 保存 `.env` 后，再次双击运行 **`run.bat`**。
4. 脚本会自动从 `ghcr.io/jamesxie2025/jimi-pro:2026.10.1` 拉取镜像、启动容器并等待网关就绪。

### 3. 访问控制台
* **控制台地址**：`http://localhost:18789`
* **默认网关令牌 (Gateway Token)**：`Jimi_Agent_2026`
* **持久化配置与记忆目录**：`.\.openclaw`（请勿删除）
* **素材输入目录**：`.\Materials`（容器内映射为 `/data`）
* **查看实时日志**：在 PowerShell 中执行 `docker compose logs -f`
