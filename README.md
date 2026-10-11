# 吉米·智驱 (Jimi Agent Pro) 部署与构建指南

本项目为 **吉米·智驱 (Jimi Agent Pro - OpenClaw `2026.10.1` 商业增强版)** 的官方构建与部署仓库，采用**平台架构物理隔离**设计，分别为 **Windows (`linux/amd64`)** 与 **macOS Apple Silicon (`linux/arm64`)** 提供原生独立镜像与一键启动脚本。

---

## 📦 官方预构建镜像（Windows 版 · 免登录直接拉取）

Windows (`linux/amd64`) 镜像由 GitHub Actions 自动编译并发布至 GitHub Container Registry (`ghcr.io`)，全球用户可直接免登录拉取：

| 标签说明 | 镜像地址 (`docker pull`) |
| :--- | :--- |
| **当前稳定版（推荐）** | `ghcr.io/jamesxie2025/jimi-pro:2026.10.1` |
| **最新版本** | `ghcr.io/jamesxie2025/jimi-pro:latest` |
| **Windows 架构显式标签** | `ghcr.io/jamesxie2025/jimi-pro:2026.10.1-amd64` |
| **Windows 算力底座镜像** | `ghcr.io/jamesxie2025/jimi-pro:base-env-amd64` |

---

## 📂 仓库目录结构说明

仓库按操作系统与硬件架构分为两个独立部分：

### 1. Windows 专享版（[`win/`](./win) 目录 — `linux/amd64` 架构）
专为 Windows 10/11 PC（WSL2 + Docker Desktop）打造，针对 Windows 跨系统文件挂载（virtiofs / NTFS / 9p）进行了深度兼容与防死锁优化：
* **[`win/docker-compose.yml`](./win/docker-compose.yml)**：Windows 容器编排配置，默认拉取 `ghcr.io/jamesxie2025/jimi-pro:2026.10.1`。
* **[`win/run.bat`](./win/run.bat) / [`win/run.ps1`](./win/run.ps1)**：Windows 一键启动与更新脚本（自动检查 `.env`、拉取最新镜像、后台启动并等待网关就绪）。
* **[`win/.env.example`](./win/.env.example)**：Windows 环境变量与硬件内存配额配置模板。
* **[`win/Dockerfile.base`](./win/Dockerfile.base)**：Windows 全量算力底座构建文件（内置 Debian 系统库、Python 科学计算/AI 依赖、CPU 版 PyTorch、LibreOffice、Playwright Chromium、预置插件种子等）。
* **[`win/Dockerfile`](./win/Dockerfile)**：Windows 极速增量热升级构建文件（复用 `:base-env-amd64` 底座，秒级完成 OpenClaw 核心与技能包升级）。
* **[`win/entrypoint.sh`](./win/entrypoint.sh)**：Windows 容器启动入口（内置商业授权校验、`openclaw.json` 基因播种、SQLite 路径自适应修复及 Windows 文件系统兼容补丁）。
* **[`.github/workflows/build-win-image.yml`](./.github/workflows/build-win-image.yml)**：GitHub Actions 云端自动化构建流水线，自动编译 `win/` 目录并发布至 `ghcr.io/jamesxie2025/jimi-pro`。

### 2. macOS Apple Silicon 专享版（仓库根目录 — `linux/arm64` 架构）
专为搭载 Apple M 系列芯片（M1/M2/M3/M4）的 Mac 打造：
* **[`docker-compose.yml`](./docker-compose.yml)**：macOS 容器编排配置。
* **[`run.sh`](./run.sh)**：macOS 本地一键启动与更新脚本。
* **[`.env.example`](./.env.example)**：macOS 环境变量与硬件内存配额配置模板。
* **[`Dockerfile.base`](./Dockerfile.base) & [`Dockerfile`](./Dockerfile)**：macOS (`linux/arm64`) 全量算力底座与极速增量构建文件。
* **[`release.sh`](./release.sh)**：macOS 本地构建与发布脚本。
* **[`entrypoint.sh`](./entrypoint.sh)**：macOS 容器启动入口与自愈引擎。

---

## 💻 Windows 用户快速安装与启动指南

### 1. 环境准备
1. 安装并启动 **Docker Desktop for Windows**（确保启用 WSL2 后端）。
2. 下载本仓库（或仅下载 `win/` 目录下的全部文件）。

### 2. 一键启动
1. 进入 `win` 文件夹，双击运行 **`run.bat`**（或在 PowerShell 中执行 `.\run.ps1`）。
2. 首次运行时，脚本会自动从 `.env.example` 生成 `.env` 配置文件。请打开 `win/.env` 填写必要的 `DEEPSEEK_API_KEY`（及授权码 `LICENSE_KEY`）。
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

## 🍎 macOS (Apple Silicon) 用户快速安装与启动指南

### 1. 一键启动
在仓库根目录下打开终端执行：
```bash
./run.sh
```
* 首次运行会自动从 `.env.example` 生成 `.env`，填写 `DEEPSEEK_API_KEY` 后再次运行 `./run.sh` 即可自动拉取镜像并启动服务。

### 2. 本地构建与发布更新（维护者使用）
* **macOS 镜像构建**：在根目录执行 `./release.sh [版本号]`（自动检测 `:base-env` 底座并执行秒级增量热升级）。
* **Windows 镜像构建**：推送代码至 GitHub `main` 分支（或在 GitHub Actions 页面手动触发 `Build Windows (AMD64) OpenClaw Image` 工作流），即可在 GitHub 云端自动构建并发布至 `ghcr.io/jamesxie2025/jimi-pro`。

