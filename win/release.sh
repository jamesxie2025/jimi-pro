#!/bin/bash
set -e

REGISTRY="ghcr.io/jamesxie2025"
IMAGE_NAME="jimi-pro"
VERSION="${1:-2026.10.1}"

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

