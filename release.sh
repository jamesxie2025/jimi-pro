#!/bin/bash
set -e

# 0. 自动同步本地沙箱技能到发布目录，防止遗漏更新
if [ -d ".openclaw/workspace/skills" ]; then
    echo "🔄 检测到本地沙箱技能，正在自动同步至发布目录 skills/ ..."
    cp -rp .openclaw/workspace/skills/. skills/
fi

# 1. 检查 Docker 守护进程状态与自动唤醒
if ! docker info >/dev/null 2>&1; then
    echo "⚠️  检测到 Docker 守护进程未运行，正在尝试启动 Docker Desktop..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open -a Docker
    fi
    echo -n "⏳ 等待 Docker 启动中"
    retry=0
    while ! docker info >/dev/null 2>&1; do
        sleep 2
        echo -n "."
        retry=$((retry + 1))
        if [ $retry -ge 30 ]; then
            echo ""
            echo "❌ Docker 启动超时，请确认 Docker Desktop 已启动后再试！"
            exit 1
        fi
    done
    echo " ✅ Docker 守护进程已就绪！"
fi

# 2. 定义变量（支持命令行传参 ./release.sh 2026.10.2，否则使用默认 VERSION）
REGISTRY="crpi-wwpcz74kapvboxgq.cn-shenzhen.personal.cr.aliyuncs.com/jimi-pro"
IMAGE_NAME="jimi-agent"
VERSION="${1:-2026.10.1}"

# 自动同步版本号到 Dockerfile 与 .env，免去手动修改多处文件
sed -i '' "s/^ARG OPENCLAW_VER=.*/ARG OPENCLAW_VER=${VERSION}/" Dockerfile 2>/dev/null || true
if [ -f .env ]; then
    sed -i '' "s/^IMAGE_TAG=.*/IMAGE_TAG=${VERSION}/" .env 2>/dev/null || true
fi

# 拼接完整的镜像引用
ARM64_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}-arm64"
AMD64_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}-amd64"
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
LATEST_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:latest"

# 3. 设置 Docker 内部网关代理（兼容自定义 PROXY_PORT）
PROXY_PORT="${PROXY_PORT:-7890}"
PROXY_URL="http://host.docker.internal:${PROXY_PORT}"
echo "🔌 使用 Docker 内部网关代理: ${PROXY_URL}"

if nc -z 127.0.0.1 "${PROXY_PORT}" 2>/dev/null; then
    echo "✅ 宿主机代理端口 ${PROXY_PORT} (Stash/Clash) 监听正常"
else
    echo "⚠️  警告: 本机端口 ${PROXY_PORT} 未监听，请确认 Stash/Clash 代理是否正常开启"
fi

echo "🔄 使用 Docker Desktop 默认构建器..."
docker buildx use desktop-linux || docker buildx use default

# ============================================================
# 架构平台配置说明：
# - Mac (Apple Silicon M1/M2/M3/M4): linux/arm64 （基于 :base-env 极速增量构建，仅需 15~30 秒）
# - Windows / Linux PC (Intel/AMD x86_64): linux/amd64
# - 双架构合一: linux/amd64,linux/arm64
# ============================================================
TARGET_PLATFORM="${BUILD_PLATFORM:-linux/arm64}"

echo "🚀 [核心构建] 正在启动极速增量镜像构建..."
echo "   目标版本: ${VERSION}"
echo "   目标平台: ${TARGET_PLATFORM}"

# 4. 核心构建（直接复用本地/阿里云 :base-env 算力底座，仅注入新版 OpenClaw /app）
docker buildx build \
  --platform ${TARGET_PLATFORM} \
  --provenance=false \
  --sbom=false \
  --build-arg OPENCLAW_VER=${VERSION} \
  --build-arg HTTP_PROXY=${PROXY_URL} \
  --build-arg HTTPS_PROXY=${PROXY_URL} \
  -f Dockerfile \
  -t ${ARM64_IMAGE} \
  -t ${FULL_IMAGE_NAME} \
  -t ${LATEST_IMAGE_NAME} \
  --push .

# 如果云端已存在同版本的 Windows (amd64) 镜像，则自动融合为双架构二合一镜像
if docker buildx imagetools inspect "${AMD64_IMAGE}" >/dev/null 2>&1; then
    echo "🔗 检测到云端已有 Windows (${AMD64_IMAGE})，正在自动融合为 Mac+Win 双架构镜像..."
    docker buildx imagetools create -t "${FULL_IMAGE_NAME}" -t "${LATEST_IMAGE_NAME}" "${ARM64_IMAGE}" "${AMD64_IMAGE}"
fi

# 5. 构建后自动清理构建缓存与 Builds 历史记录，保持 Docker Desktop 零垃圾堆积
echo "🧹 正在自动清理构建临时缓存与 Builds 历史记录..."
docker rmi "ghcr.io/openclaw/openclaw:${VERSION}" "${ARM64_IMAGE}" "${LATEST_IMAGE_NAME}" 2>/dev/null || true
docker buildx prune --all -f >/dev/null 2>&1 || true
docker buildx history rm --all >/dev/null 2>&1 || true

echo ""
echo "✅ 构建、推送与清理全部完成:"
echo "   1. ${FULL_IMAGE_NAME}"
echo "   2. ${LATEST_IMAGE_NAME}"
echo "   👉 现在可直接运行 ./run.sh 启动新版本！"