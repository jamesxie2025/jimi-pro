#!/bin/bash
set -e

REGISTRY="ghcr.io/jamesxie2025"
IMAGE_NAME="jimi-pro"

# 优先级策略：命令行指定 $1 > win/.env 中的 IMAGE_TAG > 兜底默认值
CLI_VERSION="$1"
ENV_VERSION=""
if [ -f .env ]; then
    ENV_VERSION=$(grep -E '^[[:space:]]*(IMAGE_TAG|OPENCLAW_VER)=' .env | tail -n 1 | cut -d '=' -f2- | tr -d '\r"' | tr -d "'" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
fi

VERSION="${CLI_VERSION:-${ENV_VERSION:-2026.10.5}}"

# 跨平台 sed 替换辅助函数
safe_sed_replace() {
    local pattern="$1"
    local file="$2"
    if [ -f "$file" ]; then
        if sed --version 2>/dev/null | grep -q GNU; then
            sed -i -E "$pattern" "$file" 2>/dev/null || true
        else
            sed -i '' -E "$pattern" "$file" 2>/dev/null || true
        fi
    fi
}

safe_sed_replace "s/^ARG OPENCLAW_VER=.*/ARG OPENCLAW_VER=${VERSION}/" Dockerfile
safe_sed_replace "s/^ARG OPENCLAW_VER=.*/ARG OPENCLAW_VER=${VERSION}/" Dockerfile.base

if [ -n "$CLI_VERSION" ] && [ -f .env ]; then
    safe_sed_replace "s/^[[:space:]]*IMAGE_TAG=.*/IMAGE_TAG=${VERSION}/" .env
fi

AMD64_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}-amd64"
BASE_AMD64_IMAGE="${REGISTRY}/${IMAGE_NAME}:base-env-amd64"
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
LATEST_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:latest"

PROXY_PORT="${PROXY_PORT:-7890}"
PROXY_URL="http://host.docker.internal:${PROXY_PORT}"
TARGET_PLATFORM="linux/amd64"

echo "============================================================"
echo "   吉米·智驱 (Jimi Agent Pro) Windows/WSL 原生镜像构建助手"
echo "============================================================"
echo "🚀 启动 Windows (AMD64) 原生构建..."
echo "   版本: ${VERSION}"
echo "   目标架构: ${TARGET_PLATFORM}"
echo "   内部代理: ${PROXY_URL}"
echo "============================================================"

if ! docker buildx imagetools inspect "${BASE_AMD64_IMAGE}" >/dev/null 2>&1; then
    echo "🌱 首次构建 Windows 架构：正在使用 Dockerfile.base 构建完整算力底座并固化至云端..."
    docker buildx build \
      --platform ${TARGET_PLATFORM} \
      --provenance=false \
      --sbom=false \
      --build-arg OPENCLAW_VER=${VERSION} \
      --build-arg HTTP_PROXY=${PROXY_URL} \
      --build-arg HTTPS_PROXY=${PROXY_URL} \
      -f Dockerfile.base \
      -t ${BASE_AMD64_IMAGE} \
      -t ${AMD64_IMAGE} \
      -t ${FULL_IMAGE_NAME} \
      -t ${LATEST_IMAGE_NAME} \
      --push .
else
    echo "⚡ 检测到云端已有 :base-env-amd64 底座，启动秒级增量热升级 (Dockerfile)..."
    docker buildx build \
      --platform ${TARGET_PLATFORM} \
      --provenance=false \
      --sbom=false \
      --build-arg OPENCLAW_VER=${VERSION} \
      --build-arg HTTP_PROXY=${PROXY_URL} \
      --build-arg HTTPS_PROXY=${PROXY_URL} \
      -f Dockerfile \
      -t ${AMD64_IMAGE} \
      -t ${FULL_IMAGE_NAME} \
      -t ${LATEST_IMAGE_NAME} \
      --push .
fi

echo "🧹 正在自动清理临时构建缓存与 Builds 记录..."
docker rmi "ghcr.io/openclaw/openclaw:${VERSION}" "${AMD64_IMAGE}" 2>/dev/null || true
docker buildx prune --all -f >/dev/null 2>&1 || true
docker buildx history rm --all >/dev/null 2>&1 || true

echo ""
echo "✅ Windows (linux/amd64) 镜像构建并推送成功！"
echo "   1. ${FULL_IMAGE_NAME}"
echo "   2. ${LATEST_IMAGE_NAME}"

