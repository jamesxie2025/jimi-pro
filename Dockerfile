# ==============================================================================
# 吉米·智驱 Ultra Pro - 极速增量热升级 Dockerfile (秒级版本迭代架构)
# ==============================================================================
# 架构设计说明：
# 1. Stage 1 (openclaw-upstream): 拉取指定新版官方 OpenClaw 镜像 (如 2026.10.1)，仅提取其 /app 核心引擎。
# 2. Stage 2 (base-env): 直接复用阿里云已固化的满血算力底座 (:base-env)，内含全部 350+ Debian 系统库、
#    100+ Python AI/科学计算包、PyTorch、Manim、Playwright 浏览器、DuckDB、即梦 CLI 与预置插件种子。
# 3. 仅将新版 OpenClaw 核心 (/app) 注入底座，并同步最新 skills/ 与 entrypoint.sh。
#    ✨ 优势：全程 0 apt 下载、0 pip 编译、100% 免疫网络波动与 429 限流，几十秒即可完成版本升级！
#
# （注：若未来需要增删底层 Python/Debian 依赖库，请使用同目录下的 Dockerfile.base）
# ==============================================================================

ARG OPENCLAW_VER=2026.10.1
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VER} AS openclaw-upstream

FROM crpi-wwpcz74kapvboxgq.cn-shenzhen.personal.cr.aliyuncs.com/jimi-pro/jimi-agent:base-env

USER root

# 开启 OpenClaw 2026.10.x+ 原生 Linux 文件安全与监听加速模块（消除 doctor 与 watcher 轮询告警）
ENV FS_SAFE_NATIVE_MODE=auto \
    OPENCLAW_FS_SAFE_NATIVE_MODE=auto

# 1. 原地保留底座中已预装好的插件种子包 (/app/plugins-seed)，仅清理旧版核心文件（避免 OverlayFS 重复拷贝层）
RUN find /app -mindepth 1 -maxdepth 1 ! -name 'plugins-seed' -exec rm -rf {} +

# 2. 从官方新版镜像中精准注入最新版本的 OpenClaw 核心引擎 (/app)
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
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]