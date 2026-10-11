# =========================================================================
# release.ps1 - 吉米·智驱 (Jimi Agent) Windows 原生构建与双架构融合发布脚本
# 架构: linux/amd64 | 自动判断全量底座构建或秒级增量构建，并融合至同一云端镜像名
# 用法: .\release.ps1 [版本号，默认 2026.10.1]
# =========================================================================
param(
    [string]$Version = "2026.10.1"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 0. 自动同步本地技能
if (Test-Path "..\.openclaw\workspace\skills") {
    Write-Host "🔄 检测到上级沙箱技能，正在自动同步至 skills/ ..." -ForegroundColor Cyan
    if (!(Test-Path "skills")) { New-Item -ItemType Directory -Path "skills" | Out-Null }
    Copy-Item -Path "..\.openclaw\workspace\skills\*" -Destination "skills\" -Recurse -Force
}

$REGISTRY = "ghcr.io/jamesxie2025"
$IMAGE_NAME = "jimi-pro"
$VERSION = $Version

$AMD64_IMAGE = "${REGISTRY}/${IMAGE_NAME}:${VERSION}-amd64"
$ARM64_IMAGE = "${REGISTRY}/${IMAGE_NAME}:${VERSION}-arm64"
$BASE_AMD64_IMAGE = "${REGISTRY}/${IMAGE_NAME}:base-env-amd64"
$FULL_IMAGE_NAME = "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
$LATEST_IMAGE_NAME = "${REGISTRY}/${IMAGE_NAME}:latest"

# 自动同步版本号到 Dockerfile 与 .env
if (Test-Path "Dockerfile") {
    (Get-Content "Dockerfile") -replace '^ARG OPENCLAW_VER=.*', "ARG OPENCLAW_VER=$VERSION" | Set-Content "Dockerfile"
}
if (Test-Path "Dockerfile.base") {
    (Get-Content "Dockerfile.base") -replace '^ARG OPENCLAW_VER=.*', "ARG OPENCLAW_VER=$VERSION" | Set-Content "Dockerfile.base"
}
if (Test-Path ".env") {
    (Get-Content ".env") -replace '^IMAGE_TAG=.*', "IMAGE_TAG=$VERSION" | Set-Content ".env"
}

# 检查 Docker 守护进程
if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "❌ 未检测到 Docker！请先安装并启动 Docker Desktop (确保启用 WSL2 引擎)。"
    Exit 1
}

# 自动探测 Windows 宿主机代理端口 (Clash/Stash 默认 7890，v2ray 默认 10808/10809)
$PROXY_PORT = "7890"
if ($env:PROXY_PORT) {
    $PROXY_PORT = $env:PROXY_PORT
} else {
    $ports = @(7890, 10808, 10809, 7897)
    foreach ($p in $ports) {
        $test = Test-NetConnection -ComputerName 127.0.0.1 -Port $p -WarningAction SilentlyContinue
        if ($test.TcpTestSucceeded) {
            $PROXY_PORT = "$p"
            break
        }
    }
}

$PROXY_URL = "http://host.docker.internal:${PROXY_PORT}"
$TARGET_PLATFORM = "linux/amd64"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   吉米·智驱 (Jimi Agent) Windows 原生镜像构建助手" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   镜像版本: $VERSION" -ForegroundColor Yellow
Write-Host "   目标架构: $TARGET_PLATFORM (x86_64 原生硬件编译)" -ForegroundColor Yellow
Write-Host "   宿主机代理: $PROXY_URL" -ForegroundColor Gray

# 检测云端是否已存在 Windows 算力底座 (:base-env-amd64)
Write-Host "🔍 正在检测阿里云是否已存在 Windows 算力底座 (:base-env-amd64)..." -ForegroundColor Cyan
docker buildx imagetools inspect $BASE_AMD64_IMAGE >$null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "🌱 首次构建 Windows 架构：正在使用 Dockerfile.base 构建完整算力底座并固化至云端..." -ForegroundColor Yellow
    docker buildx build `
      --platform $TARGET_PLATFORM `
      --provenance=false `
      --sbom=false `
      --build-arg OPENCLAW_VER=$VERSION `
      --build-arg HTTP_PROXY=$PROXY_URL `
      --build-arg HTTPS_PROXY=$PROXY_URL `
      -f Dockerfile.base `
      -t $BASE_AMD64_IMAGE `
      -t $AMD64_IMAGE `
      --push .
} else {
    Write-Host "⚡ 检测到云端已有 :base-env-amd64 底座，启动秒级增量热升级 (Dockerfile)..." -ForegroundColor Green
    docker buildx build `
      --platform $TARGET_PLATFORM `
      --provenance=false `
      --sbom=false `
      --build-arg OPENCLAW_VER=$VERSION `
      --build-arg HTTP_PROXY=$PROXY_URL `
      --build-arg HTTPS_PROXY=$PROXY_URL `
      -f Dockerfile `
      -t $AMD64_IMAGE `
      --push .
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ 镜像构建失败，请检查 Docker Desktop 日志或本地网络代理状态。"
    Exit 1
}

# 将 Windows (amd64) 与 Mac (arm64) 自动融合到同一个镜像名 (:2026.10.1 与 :latest)
Write-Host "🔗 正在将 Windows (amd64) 与 Mac (arm64) 融合为统一双架构镜像..." -ForegroundColor Cyan
docker buildx imagetools inspect $ARM64_IMAGE >$null 2>&1
if ($LASTEXITCODE -eq 0) {
    docker buildx imagetools create -t $FULL_IMAGE_NAME -t $LATEST_IMAGE_NAME $ARM64_IMAGE $AMD64_IMAGE
    Write-Host "✅ 双架构 (Mac ARM64 + Windows AMD64) 二合一镜像融合成功！" -ForegroundColor Green
} else {
    docker buildx imagetools create -t $FULL_IMAGE_NAME -t $LATEST_IMAGE_NAME $AMD64_IMAGE
    Write-Host "✅ Windows AMD64 镜像已推送至主标签！" -ForegroundColor Green
}

# 自动清理构建缓存与 Builds 历史
Write-Host "🧹 正在自动清理临时构建缓存与 Builds 记录..." -ForegroundColor Gray
docker rmi "ghcr.io/openclaw/openclaw:${VERSION}" >$null 2>&1
docker buildx prune --all -f >$null 2>&1
docker buildx history rm --all >$null 2>&1

Write-Host ""
Write-Host "🎉 全部完成！云端统一镜像地址：" -ForegroundColor Green
Write-Host "   1. $FULL_IMAGE_NAME (同时支持 Mac 与 Windows 自动识别)" -ForegroundColor Green
Write-Host "   2. $LATEST_IMAGE_NAME" -ForegroundColor Green
Write-Host "   👉 现在可直接运行 .\run.ps1 或双击 run.bat 启动服务！" -ForegroundColor Yellow
