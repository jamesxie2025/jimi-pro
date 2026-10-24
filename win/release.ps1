# =========================================================================
# release.ps1 - 吉米·智驱 (Jimi Agent Pro) Windows (AMD64) 原生镜像构建与发布脚本
# 架构: linux/amd64 | 自动判断全量底座构建或秒级增量构建，并发布至 GitHub (ghcr.io)
# 用法: .\release.ps1 [版本号，默认 2026.10.1]
# =========================================================================
param(
    [string]$Version = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 优先读取命令行传参，次优先读取 .env 中的 IMAGE_TAG，最后兜底默认值
$CLI_PASSED = -not [string]::IsNullOrWhiteSpace($PSBoundParameters['Version'])

if ([string]::IsNullOrWhiteSpace($Version) -and (Test-Path ".env")) {
    $envTag = Get-Content ".env" | Where-Object { $_ -match '^\s*(IMAGE_TAG|OPENCLAW_VER)\s*=\s*(.+)$' } | Select-Object -Last 1
    if ($envTag -match '^\s*(IMAGE_TAG|OPENCLAW_VER)\s*=\s*(.+)$') {
        $Version = $Matches[2].Trim("`"' ")
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = "2026.10.5"
}

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
$BASE_AMD64_IMAGE = "${REGISTRY}/${IMAGE_NAME}:base-env-amd64"
$FULL_IMAGE_NAME = "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
$LATEST_IMAGE_NAME = "${REGISTRY}/${IMAGE_NAME}:latest"

# 自动同步版本号到 Dockerfile 与 Dockerfile.base
if (Test-Path "Dockerfile") {
    (Get-Content "Dockerfile") -replace '^ARG OPENCLAW_VER=.*', "ARG OPENCLAW_VER=$VERSION" | Set-Content "Dockerfile"
}
if (Test-Path "Dockerfile.base") {
    (Get-Content "Dockerfile.base") -replace '^ARG OPENCLAW_VER=.*', "ARG OPENCLAW_VER=$VERSION" | Set-Content "Dockerfile.base"
}
# 仅当显式传入命令行版本时才写回 .env，避免覆盖用户在 .env 中设置的自定义值
if ($CLI_PASSED -and (Test-Path ".env")) {
    (Get-Content ".env") -replace '^\s*IMAGE_TAG=.*', "IMAGE_TAG=$VERSION" | Set-Content ".env"
}

# 检查 Docker 守护进程
if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "❌ 未检测到 Docker！请先安装并启动 Docker Desktop (确保启用 WSL2 引擎)。"
    Exit 1
}

# 自动探测 GHCR 国内高速镜像源 (优先走南大镜像站 ghcr.nju.edu.cn 免代理直连)
$UPSTREAM_REGISTRY = "ghcr.io"
try {
    $resp = Invoke-WebRequest -Uri "https://ghcr.nju.edu.cn/v2/openclaw/openclaw/manifests/$VERSION" -Method Head -TimeoutSec 4 -UseBasicParsing -ErrorAction Stop
    if ($resp.StatusCode -eq 200) {
        $UPSTREAM_REGISTRY = "ghcr.nju.edu.cn"
    }
} catch {}

$TARGET_PLATFORM = "linux/amd64"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   吉米·智驱 (Jimi Agent Pro) Windows 原生镜像构建助手" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   镜像版本: $VERSION" -ForegroundColor Yellow
Write-Host "   目标架构: $TARGET_PLATFORM (x86_64 原生硬件编译)" -ForegroundColor Yellow
Write-Host "   上游源站: $UPSTREAM_REGISTRY" -ForegroundColor Gray

# 检测云端是否已存在 Windows 算力底座 (:base-env-amd64)
Write-Host "🔍 正在检测 GitHub (ghcr.io) 是否已存在 Windows 算力底座 (:base-env-amd64)..." -ForegroundColor Cyan
docker buildx imagetools inspect $BASE_AMD64_IMAGE >$null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "🌱 首次构建 Windows 架构：正在使用 Dockerfile.base 构建完整算力底座并固化至云端..." -ForegroundColor Yellow
    docker buildx build `
      --platform $TARGET_PLATFORM `
      --provenance=false `
      --sbom=false `
      --build-arg OPENCLAW_VER=$VERSION `
      --build-arg UPSTREAM_REGISTRY=$UPSTREAM_REGISTRY `
      -f Dockerfile.base `
      -t $BASE_AMD64_IMAGE `
      -t $AMD64_IMAGE `
      -t $FULL_IMAGE_NAME `
      -t $LATEST_IMAGE_NAME `
      --push .
} else {
    Write-Host "⚡ 检测到云端已有 :base-env-amd64 底座，启动秒级增量热升级 (Dockerfile)..." -ForegroundColor Green
    docker buildx build `
      --platform $TARGET_PLATFORM `
      --provenance=false `
      --sbom=false `
      --build-arg OPENCLAW_VER=$VERSION `
      --build-arg UPSTREAM_REGISTRY=$UPSTREAM_REGISTRY `
      -f Dockerfile `
      -t $AMD64_IMAGE `
      -t $FULL_IMAGE_NAME `
      -t $LATEST_IMAGE_NAME `
      --push .
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ 镜像构建失败，请检查 Docker Desktop 日志或本地网络状态。"
    Exit 1
}

# 自动清理临时标签与 Builds 历史（保留 buildkit 缓存）
Write-Host "🧹 正在自动清理临时标签与 Builds 记录..." -ForegroundColor Gray
docker rmi "${UPSTREAM_REGISTRY}/openclaw/openclaw:${VERSION}" "ghcr.io/openclaw/openclaw:${VERSION}" >$null 2>&1
docker buildx history rm --all >$null 2>&1

Write-Host ""
Write-Host "🎉 全部完成！Windows (linux/amd64) 云端镜像地址：" -ForegroundColor Green
Write-Host "   1. $FULL_IMAGE_NAME" -ForegroundColor Green
Write-Host "   2. $LATEST_IMAGE_NAME" -ForegroundColor Green
Write-Host "   👉 现在可直接运行 .\run.ps1 或双击 run.bat 启动服务！" -ForegroundColor Yellow

