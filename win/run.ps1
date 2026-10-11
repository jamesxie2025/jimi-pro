# =========================================================================
# run.ps1 - 吉米·智驱 (Jimi Agent) Windows 一键启动与更新脚本
# =========================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   吉米·智驱 (Jimi Agent) Windows 启动与更新助手" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. 检查并生成 .env 配置文件
if (!(Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Write-Host "🌱 未检测到 .env 配置文件，正在从 .env.example 复制模板..." -ForegroundColor Yellow
        Copy-Item ".env.example" ".env"
        Write-Host "🚨 已生成 .env 配置文件！请先用记事本打开 .env 填写 DEEPSEEK_API_KEY 后再重新运行。" -ForegroundColor Red
        pause
        Exit 1
    }
}

# 2. 检查 Docker 状态
if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "❌ 未检测到 Docker！请先安装并启动 Docker Desktop。"
    pause
    Exit 1
}

# 3. 创建本地持久化挂载目录
if (!(Test-Path ".openclaw")) { New-Item -ItemType Directory -Path ".openclaw" | Out-Null }
if (!(Test-Path ".openclaw\ssh")) { New-Item -ItemType Directory -Path ".openclaw\ssh" | Out-Null }
if (!(Test-Path "Materials")) { New-Item -ItemType Directory -Path "Materials" | Out-Null }

# 4. 拉取最新镜像并启动容器
Write-Host "🔄 正在从 GitHub (ghcr.io/jamesxie2025/jimi-pro) 拉取最新镜像..." -ForegroundColor Cyan
docker compose pull

Write-Host "🚀 正在启动吉米·智驱容器..." -ForegroundColor Green
docker compose up -d

if ($LASTEXITCODE -eq 0) {
    Write-Host -NoNewline "⏳ 正在等待网关引擎完成数据库自检与 HTTP 服务就绪 (约需 30~40 秒)" -ForegroundColor Cyan
    for ($i = 0; $i -lt 45; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($resp.StatusCode -eq 200) { break }
        } catch {}
        Start-Sleep -Seconds 2
        Write-Host -NoNewline "." -ForegroundColor Cyan
    }
    Write-Host " ✅ 已就绪！" -ForegroundColor Green
    Write-Host ""
    Write-Host "✅ 吉米·智驱 (Jimi Agent) 启动成功！" -ForegroundColor Green
    Write-Host "🌐 控制台访问地址: http://localhost:18789" -ForegroundColor Yellow
    Write-Host "🔑 默认网关令牌 (Gateway Token): Jimi_Agent_2026" -ForegroundColor Yellow
    Write-Host "📂 持久化数据与授权目录: .\.openclaw" -ForegroundColor Gray
    Write-Host "📂 客户素材输入目录:     .\Materials" -ForegroundColor Gray
    Write-Host "📜 查看实时日志命令:     docker compose logs -f" -ForegroundColor Gray
} else {
    Write-Error "❌ 启动失败，请检查 Docker Desktop 是否正常运行。"
}
