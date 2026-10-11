# 吉米·智驱 (Jimi Agent) Windows / PC 专用构建与运行指南

本目录（`win/`）是专门为 **Windows 电脑（x86_64 / Intel / AMD 架构，16G 内存，无独立显卡）** 独立定制的全套构建与运行配置。

---

## 💡 为什么在 Windows 本机创建 AMD64 镜像更好？

1. **避免 Mac 跨架构模拟缺陷（QEMU 陷阱）**：
   - 苹果 Mac 是 ARM64 芯片，在 Mac 上构建 Windows（AMD64）镜像必须使用 QEMU 软模拟指令。
   - 模拟运行不仅速度极慢（原本 3 分钟的构建可能膨胀到 30~50 分钟），且在多线程编译 C 扩展、Python 轮子时容易发生 QEMU 指令翻译段错误（Segmentation fault / exit code 139）。
2. **Windows 原生 CPU 极速构建**：
   - Windows 电脑本身就是 AMD64 原生架构，在 Windows 上通过 Docker Desktop 构建，所有 C 扩展与 Python 库均以纯 CPU 原生硬件速度运行，**稳定可靠，零指令转换损耗**。

---

## 🛠️ 专为 16G 内存 + 纯 CPU（无 GPU）做的深度调优

| 优化维度 | 具体调优策略 | 带来的保障 |
| :--- | :--- | :--- |
| **内存防爆控** | 限制 Node.js 堆内存至 `4096MB` (`NODE_MEM_LIMIT=4096`) | 避免容器抢占导致 Windows 宿主机 16G 内存 OOM 卡死 |
| **CPU 线程温控** | `FFMPEG_THREADS=4`、`OPENBLAS_NUM_THREADS=4` | 避免多核满载打死 Windows 笔记本 CPU |
| **PyTorch 纯 CPU 化** | 强制走官方 `https://download.pytorch.org/whl/cpu` | 彻底剔除 3.5GB 无效的 NVIDIA CUDA 驱动，安装体积减少 95% |
| **Windows 文件系统治愈** | 内置 10 项 VirtioFS / NTFS 原子替换与锁文件补丁 | 根除 Windows 卷挂载引发的 `file identity changed` 与文件锁崩溃 |
| **跨容器与宿主机调度** | 默认挂载 `//var/run/docker.sock` | 赋予 OpenClaw 直接调度 Windows 宿主机及所有同机容器的最高特权 |

---

## 🚀 部署与使用步骤

### 第一步：将文件复制到 Windows 电脑
直接将整个 `win/` 文件夹复制或通过压缩包传输到 Windows 电脑的任意位置（例如 `D:\jimi-agent\`）。

> **目录结构应包含**：
> ```text
> 📁 win/
>  ├── Dockerfile            # Windows AMD64 专用构建清单
>  ├── entrypoint.sh         # 启动防御与文件系统自愈引擎
>  ├── release.ps1           # Windows PowerShell 原生构建发布脚本
>  ├── release.bat           # Windows CMD 双击构建脚本
>  ├── release.sh            # Git Bash / WSL 构建脚本
>  ├── docker-compose.yml    # Windows 容器运行编排
>  ├── run.ps1               # Windows 一键启动脚本
>  ├── .env.example          # 环境变量示例
>  └── skills/               # 内置预装技能库
> ```

---

### 第二步：在 Windows 上构建镜像（两种方式任选）

确保 Windows 电脑已安装并启动 **Docker Desktop**（推荐使用 WSL2 引擎）。

#### 方式 A：使用 PowerShell 构建（推荐）
在 `win/` 目录下按住 `Shift` + 鼠标右键，点击 **“在此处打开 PowerShell 窗口”**，执行：
```powershell
.\release.ps1
```
*脚本会自动探测本地代理端口（7890 / 10808 / 10809），并启动 x86_64 原生硬件编译与自动推送。*

#### 方式 B：双击批处理文件
直接双击运行 `release.bat` 即可开始构建。

---

### 第三步：在 Windows 上一键启动运行

构建完成后（或直接拉取预构建镜像后），运行：
```powershell
.\run.ps1
```
或者直接使用 Docker Compose：
```bash
docker compose up -d
```

启动完成后：
- **Web 控制台地址**：`http://127.0.0.1:18789`
- **查看运行日志**：
  ```powershell
  docker logs -f jimi-pro
  ```
- **数据存储位置**：`win/data/` 目录（在 Windows 资源管理器中可直接查看与备份）。
