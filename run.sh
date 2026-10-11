#!/bin/bash
# ============================================================
# run.sh - 吉米·智驱 (Jimi Agent) 本地运行与验证脚本
# ============================================================
set -e

echo "========================================="
echo "   吉米·智驱 (Jimi Agent) 本地运行与验证"
echo "========================================="

# 1. 检查并生成 .env 配置文件
if [ ! -f .env ]; then
    echo "🌱 未检测到 .env 配置文件，正在从 .env.example 复制模板..."
    cp .env.example .env
    echo "🚨 已自动为您生成 .env 配置文件！"
    echo "   👉 请先编辑当前目录下的 .env 文件，填写您的 DEEPSEEK_API_KEY"
    echo "   👉 填写完成后，重新执行 ./run.sh 即可启动服务。"
    exit 1
fi

# 2. 检测 Docker 状态
if ! command -v docker &> /dev/null; then
    echo "❌ 错误：未检测到 Docker，请先安装并启动 Docker Desktop。"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ 错误：Docker 未在运行中，请先启动 Docker Desktop。"
    exit 1
fi

# 3. 决定 Docker Compose 命令
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif docker-compose version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "❌ 错误：未检测到 Docker Compose。请确认已安装并启用 Docker Compose。"
    exit 1
fi

# 3.5 自动清理宿主机可能抢占 18789 端口的原生 OpenClaw 后台进程 (launchd: ai.openclaw.gateway)
if [[ "$OSTYPE" == "darwin"* ]]; then
    if launchctl list 2>/dev/null | grep -q "ai.openclaw.gateway"; then
        echo "⚠️ 检测到宿主机原生 OpenClaw 守护进程 (ai.openclaw.gateway) 正在抢占 18789 端口，正在自动卸载释放..."
        launchctl bootout "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
        launchctl remove ai.openclaw.gateway 2>/dev/null || true
        echo "✅ 宿主机 18789 端口冲突已解除！"
    fi
fi

# 4. 执行拉取与启动
echo "🔄 正在拉取阿里云最新镜像..."
$DOCKER_COMPOSE pull

echo "🚀 正在启动吉米·智驱容器..."
$DOCKER_COMPOSE up -d

echo -n "⏳ 正在等待网关引擎完成数据库自检与 HTTP 服务就绪 (约需 30~40 秒)"
ready_count=0
while ! curl -s -o /dev/null http://127.0.0.1:18789/ 2>/dev/null; do
    sleep 2
    echo -n "."
    ready_count=$((ready_count + 1))
    if [ $ready_count -ge 45 ]; then
        echo ""
        echo "⚠️ 等待超时，网关可能仍在后台迁移数据库，请使用 docker compose logs -f 查看进度。"
        break
    fi
done
echo " ✅ 已就绪！"

GW_TOKEN=$(grep "^OPENCLAW_GATEWAY_TOKEN=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"'\'' ' || echo "Jimi_Agent_2026")
[ -z "$GW_TOKEN" ] && GW_TOKEN="Jimi_Agent_2026"

echo "========================================="
echo "✅ 吉米·智驱 (Jimi Agent) 启动成功！"
echo "🌐 访问地址: http://localhost:18789"
echo "🔑 网关令牌 (Gateway Token): ${GW_TOKEN}"
echo "📂 挂载数据目录: ./.openclaw"
echo "📂 客户素材目录: ./Materials"
echo "📂 宿主机用户目录映射至容器内: /host"
echo "-----------------------------------------"
echo "🔑 [安全授权：开启宿主机 SSH 穿透与控制]"
echo "   1. 请确保您的 Mac 已开启远程登录：系统设置 -> 通用 -> 共享 -> 启用'远程登录'"
echo "   2. 拷贝本容器公钥到本机授权列表（免密）："
echo "      cat ./.openclaw/ssh/id_rsa.pub >> ~/.ssh/authorized_keys"
echo "-----------------------------------------"
echo "📝 查看实时日志命令:"
echo "   $DOCKER_COMPOSE logs -f"
echo "========================================="
