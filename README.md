# 吉米·智驱 (Jimi Agent Pro) — Windows 版部署与构建指南

本仓库为 **吉米·智驱 (Jimi Agent Pro - OpenClaw `2026.10.6` 开源旗舰版)** 的 **Windows (`linux/amd64`) 官方镜像构建与部署仓库**，专为 Windows 10/11 PC（WSL2 + Docker Desktop）打造。

---

## 📦 官方预构建镜像（GitHub Container Registry · 免登录直接拉取）

Windows (`linux/amd64`) 镜像由 GitHub Actions 自动编译并发布至 GitHub Container Registry (`ghcr.io`)，支持免登录直接拉取安装：

| 标签说明 | 镜像地址 (`docker pull`) |
| :--- | :--- |
| **当前稳定版（推荐）** | `ghcr.io/jamesxie2025/jimi-pro:2026.10.1` |
| **最新版本** | `ghcr.io/jamesxie2025/jimi-pro:latest` |
| **Windows 架构显式标签** | `ghcr.io/jamesxie2025/jimi-pro:2026.10.1-amd64` |
| **Windows 算力底座镜像** | `ghcr.io/jamesxie2025/jimi-pro:base-env-amd64` |

---

## 📂 仓库文件说明

* **[`win/docker-compose.yml`](./win/docker-compose.yml)**：Windows 容器编排配置，默认拉取 `ghcr.io/jamesxie2025/jimi-pro:2026.10.1`。
* **[`win/run.bat`](./win/run.bat) / [`win/run.ps1`](./win/run.ps1)**：Windows 一键启动与更新脚本（自动检查 `.env`、拉取最新镜像、后台启动并等待网关就绪）。
* **[`win/.env.example`](./win/.env.example)**：Windows 环境变量与硬件内存配额配置模板。
* **[`win/Dockerfile.base`](./win/Dockerfile.base)**：Windows 全量算力底座构建文件（内置 Debian 系统库、Python 科学计算/AI 依赖、CPU 版 PyTorch、LibreOffice、Playwright Chromium、预置插件种子等）。
* **[`win/Dockerfile`](./win/Dockerfile)**：Windows 极速增量热升级构建文件（复用 `:base-env-amd64` 底座，秒级完成 OpenClaw 核心与技能包升级）。
* **[`win/entrypoint.sh`](./win/entrypoint.sh)**：Windows 容器启动入口（内置 `openclaw.json` 基因播种、SQLite 路径自适应修复及 Windows 文件系统兼容补丁）。
* **[`win/release.ps1`](./win/release.ps1)**：Windows 本地构建与发布辅助脚本。
* **[`.github/workflows/build-win-image.yml`](./.github/workflows/build-win-image.yml)**：GitHub Actions 云端自动化构建流水线，自动编译 `win/` 目录并发布至 `ghcr.io/jamesxie2025/jimi-pro`。

---

## 💻 Windows 快速安装与启动指南

### 1. 环境准备
1. 安装并启动 **Docker Desktop for Windows**（确保启用 WSL2 后端）。
2. 下载本仓库中的 [`win`](./win) 文件夹到本地电脑（例如 `D:\jimi-pro\win`）。

### 2. 一键启动
1. 进入 `win` 文件夹，双击运行 **`run.bat`**（或在 PowerShell 中执行 `.\run.ps1`）。
2. 首次运行时，脚本会自动从 `.env.example` 生成 `.env` 配置文件。请用记事本打开 `win\.env` 填写必要的参数：
   * `DEEPSEEK_API_KEY`（必填）
   * `EMBEDDING_API_KEY`（硅基流动向量检索 Key，推荐）
   * 根据电脑物理内存（8G / 16G / 32G）核对 `MEM_LIMIT` 与 `NODE_MEM_LIMIT`
3. 再次双击 **`run.bat`**，脚本将自动从 GitHub (`ghcr.io/jamesxie2025/jimi-pro`) 拉取最新镜像并启动容器。
4. 启动完成后，在浏览器访问：
   * **控制台地址**：`http://localhost:18789`
   * **默认网关令牌 (Gateway Token)**：`Jimi_Agent_2026`

### 3. 手动命令行启动（可选）
```powershell
cd win
Copy-Item .env.example .env
# 编辑 .env 填写 DEEPSEEK_API_KEY 后执行：
docker compose pull
docker compose up -d
```

---

## 🚀 GitHub 云端自动构建说明

当修改了 `win/` 目录下的构建文件或技能包并推送至 `main` 分支（或在 GitHub Actions 页面手动触发 `Build Windows (AMD64) OpenClaw Image` 工作流）时，GitHub Actions 会自动复用 `:base-env-amd64` 算力底座执行极速增量构建，并将最新镜像发布至 `ghcr.io/jamesxie2025/jimi-pro`。


