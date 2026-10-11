# 吉米·智驱 (Jimi Agent Pro) 部署与交付指引

本项目已全面重构，支持**管理员构建发布阿里云镜像**、**Mac/Linux 一键交付部署**与**Windows 专有隔离交付部署**。

---

## 📌 第一部分：构建发布镜像文件（管理员自用）

这组文件用于**管理员构建镜像并推送到阿里云私有镜像仓库**。普通客户不需要构建文件。

### 1. Mac (Apple Silicon ARM64) 发布文件（根目录）
| 文件名 | 职责 | 用途说明 |
| :--- | :--- | :--- |
| **`skills/`** | 技能包源码 | 根目录下 15 个核心技能（`dreamina-cli`, `jimi-ppt-architect`, `jimi-premiere-bridge` 等）。 |
| **`Dockerfile`** | 镜像定义 | 封装完整科学计算/AI 环境、Playwright 浏览器、PyTorch、FFmpeg、中文字体库等。 |
| **`release.sh`** | 自动化发布 | 管理员在 Mac 本机执行 `./release.sh`，自动进行内聚加速与镜像发布。 |
| **`entrypoint.sh`**| 启动入口补丁 | 容器内部启动引导程序（包含 10 项自适应修复、授权校验、自动注入 25+ 网关 RPC 路由白名单与技能增量同步）。 |

### 2. Windows (x86_64 / AMD64) 专有发布文件（`win/` 目录）
所有 Windows 相关的独立构建和发布脚本均严格隔离在 `win/` 目录下，互不干扰：
* **`win/Dockerfile`**：针对 AMD64 平台优化的 PyTorch (CPU-only)、4 线程与 4GB 堆内存控制。
* **`win/entrypoint.sh`**：包含针对 Windows WSL2 / Hyper-V NTFS 文件权限自适应修复、RFC 2544 Fake-IP 穿透修复。
* **`win/release.ps1` / `win/release.bat`**：Windows 管理员一键构建与推送脚本。

---

## 📦 第二部分：给客户安装部署的文件（交付给客户）

当你要把项目打包交付给客户在他们的电脑上安装时，请根据客户操作系统提供对应的独立套件：

> [!WARNING]
> ⚠️ **严禁把 `license.sh` 发给客户！** `license.sh` 是发号器（授权码生成工具），只能由管理员保管，用于根据客户提供的 Device Machine ID 为其生成授权码。

### 🍎 方案 A：交付给 Mac / Linux 客户（使用根目录交付文件）
1. **`docker-compose.yml`**：定义了从阿里云拉取并运行容器（包含 Docker Socket 与宿主机穿透挂载）。
2. **`run.sh`**：本地一键拉取镜像并启动的辅助脚本（会自动检查/复制 `.env`）。
3. **`.env.example`**：配置模板。
4. **`.env`**（首次安装时客户可根据 `.env.example` 复制生成，或由你预设好后直接提供）。
5. **`Materials/`**：客户本地素材与工程文件投放目录（映射至容器 `/data`）。

### 🪟 方案 B：交付给 Windows 客户（整包交付 `win/` 文件夹）
直接把 `win/` 文件夹（或压缩包）交付给 Windows 客户：
1. **`win/docker-compose.yml`**：针对 Windows 盘符路径（`C:\Users\...`）优化的 Compose 配置。
2. **`win/run.ps1`**：PowerShell 一键启动脚本（右键以管理员运行或 PowerShell 直接执行）。
3. **`win/.env.example` / `win/.env`**：Windows 专属性能预设环境变量。
4. **`win/README_WIN.md`**：Windows 客户开箱指引。

---

## 🛠️ 第三部分：外围组件与辅助目录说明

在项目根目录中，有若干特定用途的辅助目录与工具：

### 1. `jimi-bridge/`（视频剪辑宿主机桥接服务）
* **是什么**：这是一个在**宿主机（Mac/PC）本地运行的轻量级 HTTP 服务**（端口 `9099`），对应智能体内置的 `jimi-premiere-bridge` 技能。
* **作用机制**：因为 Adobe Premiere Pro 和 DaVinci Resolve 安装在客户的宿主机操作系统中，容器内的 OpenClaw 在生成多轨道视频剪辑、智能闪避 (Auto-Ducking) 和 Ken Burns 动态关键帧后，会通过 `http://host.docker.internal:9099/api/compile` 调用此桥接服务，在宿主机快速合成标准的 Final Cut Pro XML (`xmeml v5`) 工程文件。
* **是否可删除**：
  * **代码文件不可删除**（保留 `bridge_server.py`, `timeline_compiler.py`, `xml_exporter.py`, `start_bridge.sh` 等）。
  * **`jimi-bridge/output/`** 是历史生成的视频/XML 临时输出目录（约 1.2GB），**里面的临时文件可以随时清空**。
* **启动方式**（需使用剪辑功能时）：
  ```bash
  cd jimi-bridge
  ./start_bridge.sh
  ```

### 2. `output_variants/`（服装生成历史输出目录）
* **是什么**：这是 `skills/dreamina-fashion-pipeline`（即梦 AI 模特换装流水线）默认的输出目录，存放之前测试生成的模特换装图片（如 `summer_conversion/`）。
* **是否可删除**：**完全可以安全删除！** 它仅仅是测试生成的静态图片产物，不影响任何系统核心逻辑。若后续再次运行换装脚本，系统会自动重新生成该目录。

---

## ⚙️ 第四部分：客户环境 `.env` 配置修改指引 (核心)

由于客户**不能使用你的私有 Volcano Engine (火山引擎) API Key 和搜索 API Key**，因此在向客户交付时，需要修改 `.env` 配置文件：

### ❓ 核心问题解答：

#### Q1. 配置文件中的插件和技能是否需要全部装好？客户怎么复制技能？
* **答：全部自动化同步，客户无需任何手动复制。**
  * **核心插件**（本地向量库 `memory-lancedb`、微信渠道 `openclaw-weixin`、画布 `canvas`、文章生成 `open-prose`）已在容器启动时默认绑定并自动后台下载安装，开箱即用。
  * **自定义技能同步**：所有 15 个高级自定义技能已经全部打包在阿里云容器镜像中。容器启动时，`entrypoint.sh` 会**自动检测并把缺少的技能增量同步到挂载卷中**。
  * **增量不覆盖**：若客户以后自己修改了某个技能，脚本采用非覆盖复制，绝对不会覆盖客户自己修改过的代码。

#### Q2. 客户有些 API Key 空着会影响使用吗？
* **Search API (Tavily/Brave Search) 留空：不影响服务运行。** 仅会导致智能体的“联网搜索功能”失效，其余如对话、视频生成、代码编写等所有本地/云端大模型功能均正常。
* **Embedding API (向量嵌入) 留空：会影响记忆功能！** 记忆模块 `memory-lancedb` 需要使用向量嵌入模型（Embedding）来计算记忆相关性，如果此项留空，会导致记忆功能报错甚至智能体长短期记忆失效。因此，**强烈建议为客户配置向量嵌入 API**。

#### Q3. 如何用国内免代理模型替换 OpenAI 的 Embedding 接口？
我们在 `.env` 中预置了 **OpenAI 兼容的国内嵌入通道**，推荐以下方案：

##### 方案 A：硅基流动 (SiliconFlow)（强烈推荐 🌟 默认预置）
* **特点**：国内节点，超低延迟，注册即送免费额度，中文检索友好。
* **配置方式**：
  ```env
  EMBEDDING_PROVIDER=openai
  EMBEDDING_BASE_URL=https://api.siliconflow.cn/v1
  EMBEDDING_API_KEY= (填写客户自备或你提供的硅基流动 API Key)
  EMBEDDING_MODEL=BAAI/bge-large-zh-v1.5
  EMBEDDING_DIMENSIONS=1024
  ```

##### 方案 B：阿里云百炼 (Aliyun DashScope)
* **特点**：阿里企业级通道，速度极快且稳定。
* **配置方式**：
  ```env
  EMBEDDING_PROVIDER=openai
  EMBEDDING_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
  EMBEDDING_API_KEY= (填写客户自备的阿里云百炼 API Key)
  EMBEDDING_MODEL=text-embedding-v3
  EMBEDDING_DIMENSIONS=1536
  ```

---

## 🔌 第五部分：宿主机与 Docker 容器通讯机制说明

智能体不仅仅是一个独立的对话机器人，还具备完整的宿主机与容器交互能力：

1. **管理宿主机其他 Docker 容器**：
   * `docker-compose.yml` 中挂载了宿主机的 `/var/run/docker.sock`。
   * 镜像内部安装了官方 Docker CLI。智能体可以直接在对话中通过终端命令查询、启动、停止、重启宿主机上的其他任何容器（例如 MySQL、Redis、Web 服务等）。
2. **读写宿主机本地文件**：
   * 宿主机的用户主目录（`$HOME`）被挂载到了容器内部的 `/host`。
   * 智能体可以在获得授权后，读取或将生成的文件直接写入到宿主机的 `Downloads/`、`Documents/` 等目录。
3. **与宿主机网络服务通讯**：
   * Compose 配置中加入了 `extra_hosts: host.docker.internal:host-gateway`。
   * 容器内的智能体或脚本可以通过 `http://host.docker.internal:端口` 顺畅访问宿主机上的各种服务（如 Stash/Clash 代理端口 `7890`、剪辑桥接服务 `9099`、本地 Ollama `11434` 等）。

---

## 🔄 第六部分：从旧项目 (jimi-openclaw) 迁移数据指引

如果您希望将旧项目 `jimi-openclaw` 中的 **智能体灵魂 (Soul)、用户账号、对话会话历史、已绑定设备和记忆库** 完整迁移到新项目 `jimi-pro` 中，请按照本指南进行操作。

### 📁 核心数据目录说明
在 OpenClaw 架构中，所有状态数据都保存在映射卷 `.openclaw/` 目录下：
* **`agents/`**：智能体的灵魂（设定、Prompt、知识库）。
* **`state/`** (`openclaw.sqlite`)：用户账号、权限配置、对话历史列表及激活授权码。
* **`identity/`**：网关鉴权证书、API 访问密钥与本地缓存。
* **`devices/`**：已配对并授权的客户端设备（PC 控制端、微信端等）凭证。
* **`openclaw-weixin/`**：微信绑定渠道的运行缓存和设置。
* **`workspace/`** 与 **`memory/`**：长期向量嵌入记忆数据库（LanceDB）和用户的上传文件资产。

### 🚀 数据迁移命令

在 Mac 本机终端执行以下三步，即可安全、精准地完成迁移：

#### 1. 停止当前运行的容器
```bash
cd /Users/xwxie/Public/jimi-pro
docker compose down
```

#### 2. 精准迁移核心状态数据（使用 rsync 自动合并覆盖）
> [!IMPORTANT]
> 此命令**只迁移**状态、灵魂、用户和数据库，**不会**迁移 `openclaw.json`（避免覆盖我们在新版中重构好的 API 映射和插件配置）或旧的 npm 缓存包。

```bash
rsync -a --progress \
  /Users/xwxie/jimi-openclaw/.openclaw/{agents,state,identity,devices,openclaw-weixin,workspace,memory} \
  /Users/xwxie/Public/jimi-pro/.openclaw/
```

#### 3. 重新启动服务
```bash
./run.sh
```

迁移完成后，再次访问控制台（http://localhost:18789），旧有的会话历史记录、提示词配置与微信/控制端绑定状态将会**无缝重现**。
