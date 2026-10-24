# ==============================================================================
# 吉米·智驱 Ultra Pro - Windows (AMD64) 极速增量热升级 Dockerfile
# ==============================================================================
# 架构设计说明：
# 1. Stage 1 (openclaw-upstream): 拉取指定新版官方 OpenClaw 镜像 (linux/amd64)，仅提取其 /app 核心引擎。
# 2. Stage 2 (base-env-amd64): 直接复用 GitHub (ghcr.io) 已固化的 Windows 算力底座 (:base-env-amd64)，
#    内含全部 Debian 系统库、100+ Python AI/科学计算包、纯 CPU PyTorch、Manim、Playwright 与预置插件种子。
# 3. 仅将新版 OpenClaw 核心 (/app) 注入底座，并同步最新 skills/ 与 entrypoint.sh。
#    ✨ 优势：全程 0 apt 下载、0 pip 编译，几十秒即可完成 Windows 版本升级！
#    （注：首次构建或需修改底层 Python/Debian 依赖库时，release.ps1 会自动调用 Dockerfile.base）
# ==============================================================================

ARG OPENCLAW_VER=2026.10.6
ARG UPSTREAM_REGISTRY=ghcr.io
ARG BASE_IMAGE=ghcr.io/jamesxie2025/jimi-pro:base-env-amd64
FROM ${UPSTREAM_REGISTRY}/openclaw/openclaw:${OPENCLAW_VER} AS openclaw-upstream

FROM ${BASE_IMAGE}

USER root

# 开启 OpenClaw 2026.10.x+ 原生 Linux 文件安全与监听加速模块
ENV FS_SAFE_NATIVE_MODE=auto \
    OPENCLAW_FS_SAFE_NATIVE_MODE=auto

# 1. 原地保留底座中已预装好的插件种子包 (/app/plugins-seed)，仅清理旧版核心文件
RUN find /app -mindepth 1 -maxdepth 1 ! -name 'plugins-seed' -exec rm -rf {} +

# 2. 从官方新版镜像中精准注入最新版本的 Node.js 运行时 (Node >=24.22.1) 与 OpenClaw 核心引擎 (/app)
COPY --from=openclaw-upstream /usr/local/bin/node /usr/local/bin/node
COPY --from=openclaw-upstream /usr/local/include/node/ /usr/local/include/node/
COPY --from=openclaw-upstream /usr/local/lib/node_modules/ /usr/local/lib/node_modules/
COPY --from=openclaw-upstream /app/ /app/

# 3. 对齐 openclaw 全局命令软链接与目录权限
RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw && \
    chmod +x /app/openclaw.mjs /usr/local/bin/openclaw && \
    mkdir -p /root/.openclaw /data && \
    chmod -R 777 /data && \
    chmod 1777 /tmp

# 4. 注入最新本地自定义技能包与启动补丁程序
COPY skills/ /app/workspace/skills/
RUN chmod -R 777 /app/workspace/skills

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    sed -n '/^# BEGIN_DIST_PATCH/,/^# END_DIST_PATCH/p' /usr/local/bin/entrypoint.sh | bash && \
    touch /app/.jimi_dist_patched

USER root
ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
