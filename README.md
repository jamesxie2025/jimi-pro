# 吉米·智驱 (Jimi Agent Dual) 部署与构建指南

本项目已适配为**构建阿里云镜像**与**本地拉取镜像验证**的双向支持架构。

---

## 📂 项目文件架构说明

项目中的文件已划分为以下两大职责清晰的“家系/一派”：

### 1. 构建与发布派 (Release Files)
这组文件负责将源码与环境打包并构建为支持多架构 (`linux/amd64`, `linux/arm64`) 的 Docker 镜像，并自动推送到阿里云私有镜像仓库。
* **[Dockerfile](file:///Users/xwxie/Public/jimi-agent-dual/Dockerfile)**: 基于基础镜像安装高算力组件（DuckDB、Python 技能包、Playwright 浏览器、Torch 等）。
* **[release.sh](file:///Users/xwxie/Public/jimi-agent-dual/release.sh)**: 自动化多架构 Docker 构建与推送脚本。
* **[entrypoint.sh](file:///Users/xwxie/Public/jimi-agent-dual/entrypoint.sh)**: 容器启动入口，内置商业授权校验和 `openclaw.json` 自动播种/基因修复逻辑。
* **[license.sh](file:///Users/xwxie/Public/jimi-agent-dual/license.sh)**: 离线授权激活码生成工具（供管理员为客户电脑生成 LICENSE_KEY）。

### 2. 本地拉取与运行派 (Local Verification & Run Files)
这组文件用于在本机（或客户部署机）直接拉取阿里云镜像并运行验证，确保容器开箱即用。
* **[docker-compose.yml](file:///Users/xwxie/Public/jimi-agent-dual/docker-compose.yml)**: 定义了服务容器配置，默认从阿里云拉取最新的 `jimi-agent:latest` 镜像。
* **[run.sh](file:///Users/xwxie/Public/jimi-agent-dual/run.sh)**: 本地一键验证脚本。会自动检查/生成 `.env`，执行镜像 pull 并后台启动服务。
* **[.env.example](file:///Users/xwxie/Public/jimi-agent-dual/.env.example)**: 本地配置环境变量模板。

---

## 🚀 阿里云多架构镜像构建与发布

当需要重新打包并发布新镜像时，直接执行：
```bash
./release.sh
```

> **💡 避坑与网络优化设计：**
> * **默认构建器：** 脚本自动使用 Docker Desktop 默认构建器 (`desktop-linux` / `default`)，使用宿主机网络栈，避免 BuildKit 虚拟网关（`vpnkit`）在大量并发连接下崩溃。
> * **阿里云 HTTPS 源：** 构建过程中 APT 安装和 Python pip 直连阿里云 HTTPS 镜像站，走代理直连规则，速度极快且极度稳定；针对国外依赖包（如 DuckDB、Playwright）则会通过宿主机代理进行下载，互不干扰。

---

## 💻 本地验证与客户部署运行

### 1. 快速启动（一键运行）
在终端中执行以下命令即可启动本地验证：
```bash
./run.sh
```
* 如果是首次运行，脚本会自动从 `.env.example` 复制生成 `.env` 配置文件，并提示你填写 `DEEPSEEK_API_KEY`。
* 填写好配置后重新运行 `./run.sh`，脚本将自动拉取阿里云镜像并以后台容器启动。

### 2. 手动启动
如果不想使用脚本，可以直接使用标准的 Docker Compose 命令：
```bash
# 复制配置文件
cp .env.example .env
# (编辑 .env 填写必要的 API Key)

# 拉取最新的阿里云镜像
docker compose pull

# 后台启动服务
docker compose up -d
```

---

## 🔑 商业授权码激活 (管理员使用)

当需要给客户授权时，在终端运行：
```bash
./license.sh
```
根据提示输入客户机器生成的 **Machine ID (设备识别码)** 以及 **到期日期** (如 `20270513`)，即可生成 `LICENSE_KEY`。客户将该行配置填入其 `.env` 文件即可完成授权。
