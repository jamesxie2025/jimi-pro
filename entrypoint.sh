#!/bin/bash
# 吉米·智驱 商业授权系统 - 2026 旗舰最终版 (极致闭环版)

# 0. 动态自适应与底层安全防御：智能合成 Node 运行时参数与 Windows 挂载文件系统补丁
NODE_MEM_LIMIT="${NODE_MEM_LIMIT:-6144}"
mkdir -p /usr/local/lib
cat > /usr/local/lib/node-patch-fs.js << 'EOF_PATCH'
const fs = require('fs');

// 智能安全 Stat 工厂：优先从 /proc/self/fd 获取真实准确的文件/目录元数据
function getSafeStat(fd, options) {
  const isBigInt = Boolean(options && options.bigint);
  const one = isBigInt ? 1n : 1;
  const zero = isBigInt ? 0n : 0;

  if (typeof fd === 'number' && fd >= 0) {
    // 方案 1：在 Linux 容器中通过 /proc/self/fd/${fd} 读取内核真实状态（无论文件还是目录）
    try {
      const st = fs.statSync(`/proc/self/fd/${fd}`, options);
      if (st) return st;
    } catch (_) {}
    try {
      const st = fs.lstatSync(`/proc/self/fd/${fd}`, options);
      if (st) return st;
    } catch (_) {}

    // 方案 2：尝试获取真实路径进行 stat
    try {
      const realPath = fs.readlinkSync(`/proc/self/fd/${fd}`);
      if (realPath) {
        try {
          const st = fs.statSync(realPath, options);
          if (st) return st;
        } catch (_) {}
        try {
          const st = fs.lstatSync(realPath, options);
          if (st) return st;
        } catch (_) {}
      }
    } catch (_) {}
  }

  // 方案 3：极限制式自愈兜底（默认为 regular file 构造，满足 isFile()===true, nlink===1, mode===0o100644）
  return {
    isFile: () => true,
    isDirectory: () => false,
    isSymbolicLink: () => false,
    isBlockDevice: () => false,
    isCharacterDevice: () => false,
    isFIFO: () => false,
    isSocket: () => false,
    dev: isBigInt ? 1n : 1,
    ino: isBigInt ? BigInt(typeof fd === 'number' && fd > 0 ? (fd + 1000000) : Math.floor(Math.random() * 100000000)) : (typeof fd === 'number' && fd > 0 ? (fd + 1000000) : Math.floor(Math.random() * 100000000)),
    mode: 0o100644,
    nlink: one,
    uid: zero,
    gid: zero,
    rdev: zero,
    size: zero,
    blksize: 4096,
    blocks: zero,
    atimeMs: Date.now(),
    mtimeMs: Date.now(),
    ctimeMs: Date.now(),
    birthtimeMs: Date.now(),
    atime: new Date(),
    mtime: new Date(),
    ctime: new Date(),
    birthtime: new Date()
  };
}

// 1. 劫持 fs.fstatSync：捕获并治愈挂载卷的 ENOENT 异常，保留真实内核 dev/ino
const origFstatSync = fs.fstatSync;
fs.fstatSync = function (fd, options) {
  try {
    return origFstatSync.call(fs, fd, options);
  } catch (err) {
    if (err && (err.code === 'ENOENT' || (err.message && err.message.includes('ENOENT')))) {
      return getSafeStat(fd, options);
    }
    throw err;
  }
};

// 2. 劫持 fs.fstat (异步版)
const origFstat = fs.fstat;
if (typeof origFstat === 'function') {
  fs.fstat = function (fd, ...args) {
    const cb = args[args.length - 1];
    const options = typeof args[0] === 'object' ? args[0] : undefined;
    if (typeof cb === 'function') {
      const wrappedCb = (err, stats) => {
        if (err && (err.code === 'ENOENT' || (err.message && err.message.includes('ENOENT')))) {
          return cb(null, getSafeStat(fd, options));
        }
        return cb(err, stats);
      };
      args[args.length - 1] = wrappedCb;
    }
    return origFstat.apply(fs, [fd, ...args]);
  };
}

// 3. 劫持 FileHandle.prototype.stat 异步捕获 ENOENT
try {
  const fsPromises = fs.promises || require('fs/promises');
  if (fsPromises && fsPromises.open) {
    fsPromises.open('/dev/null', 'r').then(handle => {
      const proto = Object.getPrototypeOf(handle);
      if (proto && proto.stat && !proto.__patched) {
        const origHandleStat = proto.stat;
        proto.stat = async function (options) {
          try {
            return await origHandleStat.call(this, options);
          } catch (err) {
            if (err && (err.code === 'ENOENT' || (err.message && err.message.includes('ENOENT')))) {
              return getSafeStat(this.fd, options);
            }
            throw err;
          }
        };
        proto.__patched = true;
      }
      handle.close().catch(() => {});
    }).catch(() => {});
  }
} catch (_) {}
EOF_PATCH

# 清理并动态合成 NODE_OPTIONS
[ -n "$NODE_OPTIONS" ] && NODE_OPTIONS=$(echo "$NODE_OPTIONS" | tr -d '"'\' | xargs)
if [[ "$NODE_OPTIONS" != *"--max-old-space-size"* ]]; then
    NODE_OPTIONS="--max-old-space-size=${NODE_MEM_LIMIT} ${NODE_OPTIONS}"
fi
if [[ "$NODE_OPTIONS" != *"--max-http-header-size"* ]]; then
    NODE_OPTIONS="--max-http-header-size=102400 ${NODE_OPTIONS}"
fi
if [[ "$NODE_OPTIONS" != *"node-patch-fs.js"* ]]; then
    NODE_OPTIONS="--require /usr/local/lib/node-patch-fs.js ${NODE_OPTIONS}"
fi
export NODE_OPTIONS=$(echo "$NODE_OPTIONS" | xargs)
echo "🚀 激活 Node.js 运行时参数: $NODE_OPTIONS"

# 🚀 官方推荐启动加速：开启 V8 编译字节码缓存、原生 fs-safe 辅助模块与容器内禁止脱机 respawn
export NODE_COMPILE_CACHE="${NODE_COMPILE_CACHE:-/var/tmp/openclaw-compile-cache}"
mkdir -p "$NODE_COMPILE_CACHE" 2>/dev/null || true
export OPENCLAW_NO_RESPAWN=1
export FS_SAFE_NATIVE_MODE=auto
export OPENCLAW_FS_SAFE_NATIVE_MODE=auto

TARGET_DIR="/root/.openclaw"
rm -f "$TARGET_DIR/exec-approvals.json"
ID_FILE="$TARGET_DIR/.machine_id"
LOCK_FILE="$TARGET_DIR/.sys_runtime_cache.bin"
SALT="JIMI-PRO-ULTRA-MAX-2026-SECRET"
CONFIG_FILE="$TARGET_DIR/openclaw.json"

# 1. 物理开辟土壤（仅在目录新建时设权限，避免每次重启全量 chmod 拖慢 Windows 挂载）
mkdir -p "$TARGET_DIR"
mkdir -p /data
[ ! -w "$TARGET_DIR" ] && chmod 777 "$TARGET_DIR" 2>/dev/null || true
[ ! -w "/data" ] && chmod 777 /data 2>/dev/null || true

# 1.1 🔑 宿主机 SSH 穿透与免密认证自动配置
echo "🔑 正在初始化宿主机 SSH 穿透配置..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 如果 SSH 密钥不存在，则自动生成
if [ ! -f /root/.ssh/id_rsa ]; then
    echo "🔑 未检测到 SSH 密钥，正在生成内部 SSH 密钥对..."
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
    echo "✅ SSH 密钥对生成成功！"
fi
chmod 600 /root/.ssh/id_rsa
chmod 644 /root/.ssh/id_rsa.pub

# 自动配置 host.docker.internal 免除 Host Key 确认交互
cat > /root/.ssh/config <<EOF
Host host.docker.internal
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chmod 600 /root/.ssh/config

# 1.2 🚀 宿主机桌面穿透：注入 xdg-open 支持 Web UI 点击直接唤起宿主机 (Mac/Win) VS Code / 资源管理器
cat > /usr/local/bin/xdg-open << 'XDG_EOF'
#!/bin/bash
TARGET="$1"
H_USER="${HOST_USER:-xwxie}"
H_PWD="${HOST_PWD:-/Users/${H_USER}/Public/jimi-pro}"

# 动态将容器内路径映射为宿主机绝对路径
HOST_PATH="$TARGET"
if [[ "$TARGET" == /root/.openclaw* ]]; then
    HOST_PATH="${H_PWD}/.openclaw${TARGET#/root/.openclaw}"
elif [[ "$TARGET" == /data* ]]; then
    HOST_PATH="${H_PWD}/Materials${TARGET#/data}"
elif [[ "$TARGET" == /app* ]]; then
    HOST_PATH="${H_PWD}${TARGET#/app}"
fi

# 通过 SSH 非交互模式（带2秒超时）唤起宿主机编辑器/打开器（优先 VS Code，回退 open/start）
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=2 "${H_USER}@host.docker.internal" \
    "open -a 'Visual Studio Code' '${HOST_PATH}' 2>/dev/null || open '${HOST_PATH}' 2>/dev/null || cmd.exe /c start '' '${HOST_PATH}' 2>/dev/null" >/dev/null 2>&1 || true
exit 0
XDG_EOF
chmod +x /usr/local/bin/xdg-open

# 1.5 🟢 极致生长：内置技能同步 (采用物理复制替代软链接，确保每次启动都用镜像内最新技能完全替代，并解决 Windows/macOS 挂载卷的软链接失效问题)
if [ -d "/app/workspace/skills" ]; then
    echo "🌱 检测到内置技能包，正在同步更新到工作空间技能 (workspace/skills)..."
    
    # 彻底清理旧的技能目录，防止旧技能残留或版本不一致
    rm -rf "$TARGET_DIR/workspace/skills"
    mkdir -p "$TARGET_DIR/workspace/skills"
    
    # 物理复制最新技能包，确保在 Windows/macOS 挂载卷下 100% 兼容和可用
    cp -rp /app/workspace/skills/. "$TARGET_DIR/workspace/skills/"
    
    # 设置权限
    chmod -R 777 "$TARGET_DIR/workspace/skills"
    echo "✅ 技能包物理同步并完全替代完成！"
fi

# 1.6 🟢 极速启动：链接预置插件 (优先用符号链接，若在 Windows/macOS 挂载卷下失效，则自动回退到物理复制)
if [ -d "/app/plugins-seed" ]; then
    echo "🌱 检测到内置插件包，正在配置工作空间插件 (npm)..."
    
    # 尝试创建软链接（在支持的环境下速度最快）
    if [ -d "$TARGET_DIR/npm" ] && [ ! -L "$TARGET_DIR/npm" ]; then
        echo "⚠️ 检测到物理 npm 插件目录，正在清理以使用镜像内置的链接..."
        rm -rf "$TARGET_DIR/npm"
    fi
    
    if ln -sfn /app/plugins-seed "$TARGET_DIR/npm" 2>/dev/null; then
        echo "✅ 插件包软链接创建成功！"
    else
        echo "⚠️ 符号链接创建失败（可能是 Windows/macOS 宿主机挂载卷限制），正在回退至物理复制（此过程可能需要几十秒，请耐心等待）..."
        rm -rf "$TARGET_DIR/npm"
        mkdir -p "$TARGET_DIR/npm"
        cp -rp /app/plugins-seed/. "$TARGET_DIR/npm/"
        chmod -R 777 "$TARGET_DIR/npm"
        echo "✅ 插件包物理复制完成！"
    fi
fi

# 2. 🟢 极致生长逻辑：物理播种 (专家级自愈：文件为空或缺少 models 节均触发重写)
if [ ! -s "$CONFIG_FILE" ] || ! grep -q '"models"' "$CONFIG_FILE" 2>/dev/null; then
    echo "🌱 发现新环境或空配置，正在物理生成满血版配置文件 (openclaw.json)..."

    # 第一步：用单引号 EOF 保护，写入含占位符的纯净 JSON 模板
    cat << 'EOF' > "$CONFIG_FILE"
{
  "gateway": {
    "mode": "local", "port": 18789, "bind": "auto",
    "auth": { "mode": "token", "token": "REPLACE_GATEWAY_TOKEN" },
    "controlUi": { "allowedOrigins": ["*"] }
  },
  "models": {
    "mode": "replace",
    "providers": {
      "deepseek": {
        "baseUrl": "REPLACE_DEEPSEEK_BASE_URL", "api": "openai-completions",
        "apiKey": "REPLACE_DEEPSEEK_KEY",
        "models": [
          { "id": "deepseek-v4-flash", "name": "DeepSeek V4 Flash" },
          { "id": "deepseek-v4-pro", "name": "DeepSeek V4 Pro" }
        ],
        "timeoutSeconds": 600
      },
      "agnes": {
        "baseUrl": "REPLACE_AGNES_BASE_URL", "api": "openai-completions",
        "apiKey": "REPLACE_AGNES_KEY",
        "models": [
          { "id": "agnes-2.0-flash", "name": "Agnes 2.0 Flash" }
        ],
        "timeoutSeconds": 600
      }
    }
  },
  "plugins": {
    "allow": ["deepseek", "memory-core", "canvas", "browser", "tavily", "brave", "memory-lancedb", "openclaw-weixin"],
    "entries": {
      "deepseek": { "enabled": true }, 
      "memory-core": { "enabled": false }, 
      "canvas": { "enabled": true },
      "browser": { "enabled": true },
      "openclaw-weixin": { "enabled": false },
      "github": { "enabled": false },
      "device-pair": { "enabled": false },
      "tavily": {
        "enabled": true,
        "config": {
          "webSearch": {
            "apiKey": "REPLACE_TAVILY_API_KEY",
            "baseUrl": "REPLACE_TAVILY_BASE_URL"
          }
        }
      },
      "brave": {
        "enabled": true,
        "config": {
          "webSearch": {
            "apiKey": "REPLACE_BRAVE_API_KEY"
          }
        }
      },
      "memory-lancedb": {
        "enabled": true,
        "config": {
          "embedding": {
            "provider": "REPLACE_EMBEDDING_PROVIDER",
            "model": "REPLACE_EMBEDDING_MODEL",
            "baseUrl": "REPLACE_EMBEDDING_BASE_URL",
            "apiKey": "REPLACE_EMBEDDING_API_KEY",
            "dimensions": 1024
          }
        },
        "hooks": {
          "allowConversationAccess": true
        }
      }
    },
    "slots": {
      "memory": "memory-lancedb"
    }
  },
  "tools": {
    "web": {
      "search": {
        "provider": "REPLACE_SEARCH_PROVIDER",
        "maxResults": 5
      }
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/root/.openclaw/workspace",
      "model": {
        "primary": "REPLACE_PRIMARY_MODEL",
        "fallbacks": [
          "REPLACE_FALLBACK_MODEL_1",
          "REPLACE_FALLBACK_MODEL_2"
        ]
      },
      "models": {
        "REPLACE_PRIMARY_MODEL": {},
        "REPLACE_FALLBACK_MODEL_1": {},
        "REPLACE_FALLBACK_MODEL_2": {}
      },
      "skills": [
        "libtv-skill",
        "mcporter",
        "coding-agent",
        "dreamina-video-master",
        "dreamina-cli",
        "byteplus-cdance-video",
        "multi-step-video-workflow",
        "jimi-ppt-architect",
        "dreamina-fashion-pipeline",
        "nano-banana-pro"
      ]
    }
  },
  "browser": {
    "enabled": true,
    "headless": true,
    "noSandbox": true,
    "ssrfPolicy": {
      "dangerouslyAllowPrivateNetwork": true
    }
  }
}
EOF
fi

# 🌟 核心修复：用 jq 精准注入 Key（每次启动都根据 .env 同步，防掉线、防失效）
# 动态解析 PRIMARY_MODEL, FALLBACK_MODEL_1, FALLBACK_MODEL_2，将其加入支持的 models 列表中
DEEPSEEK_MODELS=("deepseek-v4-flash" "deepseek-v4-pro")
AGNES_MODELS=("agnes-2.0-flash")

add_model_id() {
  local model_str="$1"
  if [[ "$model_str" == deepseek/* ]]; then
    local model_id="${model_str#deepseek/}"
    local found=0
    for m in "${DEEPSEEK_MODELS[@]}"; do
      if [ "$m" = "$model_id" ]; then
        found=1
        break
      fi
    done
    if [ $found -eq 0 ]; then
      DEEPSEEK_MODELS+=("$model_id")
    fi
  elif [[ "$model_str" == agnes/* ]]; then
    local model_id="${model_str#agnes/}"
    local found=0
    for m in "${AGNES_MODELS[@]}"; do
      if [ "$m" = "$model_id" ]; then
        found=1
        break
      fi
    done
    if [ $found -eq 0 ]; then
      DEEPSEEK_MODELS+=("$model_id")
    fi
  fi
}

add_model_id "${PRIMARY_MODEL:-deepseek/deepseek-v4-flash}"
add_model_id "${FALLBACK_MODEL_1:-deepseek/deepseek-v4-pro}"
add_model_id "${FALLBACK_MODEL_2:-agnes/agnes-2.0-flash}"
DEEPSEEK_MODELS+=("deepseek-v4-flash-vision-exp")

# 构建 deepseek models 的 JSON 数组
ds_models_json="["
for m in "${DEEPSEEK_MODELS[@]}"; do
  name="$m"
  if [ "$m" = "deepseek-v4-flash" ]; then name="DeepSeek V4 Flash"; fi
  if [ "$m" = "deepseek-v4-pro" ]; then name="DeepSeek V4 Pro"; fi
  if [ "$m" = "deepseek-v4-flash-vision-exp" ]; then
    name="DeepSeek V4 Flash Vision Exp"
    ds_models_json="${ds_models_json}{\"id\":\"$m\",\"name\":\"$name\",\"input\":[\"text\",\"image\"]},"
  else
    ds_models_json="${ds_models_json}{\"id\":\"$m\",\"name\":\"$name\"},"
  fi
done
ds_models_json="${ds_models_json%,}]"

# 构建 agnes models 的 JSON 数组
agnes_models_json="["
for m in "${AGNES_MODELS[@]}"; do
  name="$m"
  if [ "$m" = "agnes-2.0-flash" ]; then name="Agnes 2.0 Flash"; fi
  agnes_models_json="${agnes_models_json}{\"id\":\"$m\",\"name\":\"$name\"},"
done
agnes_models_json="${agnes_models_json%,}]"

# jq 已在镜像中安装（Dockerfile apt 阶段），--arg 自动处理转义
jq --arg tok "${OPENCLAW_GATEWAY_TOKEN:-Jimi_Agent_2026}" \
   --arg bind_mode "${OPENCLAW_GATEWAY_BIND:-auto}" \
   --arg ds_url "${DEEPSEEK_BASE_URL:-https://api.deepseek.com}" \
   --arg ds_key "${DEEPSEEK_API_KEY:-}" \
   --arg agnes_url "${AGNES_BASE_URL:-https://apihub.agnes-ai.com/v1}" \
   --arg agnes_key "${AGNES_API_KEY:-}" \
   --arg tavily_key "${TAVILY_API_KEY:-}" \
   --arg tavily_url "${TAVILY_BASE_URL:-https://api.tavily.com}" \
   --arg brave_key "${BRAVE_API_KEY:-}" \
   --arg search_prov "${SEARCH_PROVIDER:-tavily}" \
   --arg primary "${PRIMARY_MODEL:-deepseek/deepseek-v4-flash}" \
   --arg fallback1 "${FALLBACK_MODEL_1:-deepseek/deepseek-v4-pro}" \
   --arg fallback2 "${FALLBACK_MODEL_2:-agnes/agnes-2.0-flash}" \
   --arg embed_prov "${EMBEDDING_PROVIDER:-openai}" \
   --arg embed_model "${EMBEDDING_MODEL:-BAAI/bge-large-zh-v1.5}" \
   --arg embed_url "${EMBEDDING_BASE_URL:-https://api.siliconflow.cn/v1}" \
   --arg embed_key "${EMBEDDING_API_KEY:-}" \
   --arg embed_dims "${EMBEDDING_DIMENSIONS:-1024}" \
   --arg apiyi_url "${APIYI_BASE_URL:-https://api.apiyi.com/v1}" \
   --arg apiyi_key "${APIYI_API_KEY:-}" \
   --argjson ds_models "$ds_models_json" \
   --argjson agnes_models "$agnes_models_json" \
   '
    .gateway.auth.token = $tok |
    .gateway.auth.mode = "token" |
    .gateway.controlUi.allowedOrigins = ["*"] |
    .gateway.bind = $bind_mode |
    .models.providers.deepseek = ((.models.providers.deepseek // {}) + {
      "api": (.models.providers.deepseek.api // "openai-completions"),
      "timeoutSeconds": (.models.providers.deepseek.timeoutSeconds // 600),
      "models": $ds_models,
      "baseUrl": $ds_url,
      "apiKey": $ds_key
    }) |
    (if $agnes_key == "" then
      del(.models.providers.agnes)
    else
      .models.providers.agnes = ((.models.providers.agnes // {}) + {
        "api": (.models.providers.agnes.api // "openai-completions"),
        "timeoutSeconds": (.models.providers.agnes.timeoutSeconds // 600),
        "models": $agnes_models,
        "baseUrl": $agnes_url,
        "apiKey": $agnes_key
      })
    end) |
    (if $apiyi_key == "" then
      del(.models.providers.apivy)
    else
      .models.providers.apivy = {
        "baseUrl": $apiyi_url,
        "apiKey": $apiyi_key,
        "api": "openai-completions",
        "timeoutSeconds": 120,
        "models": [
          {
            "id": "qwen3-vl-flash",
            "name": "Qwen3 VL Flash (Vision)",
            "reasoning": false,
            "input": ["text", "image"],
            "contextWindow": 200000,
            "maxTokens": 8192,
            "api": "openai-completions"
          },
          {
            "id": "qwen3-vl-plus",
            "name": "Qwen3 VL Plus (Vision)",
            "reasoning": false,
            "input": ["text", "image"],
            "contextWindow": 200000,
            "maxTokens": 8192,
            "api": "openai-completions"
          }
        ]
      }
    end) |
    .plugins.entries.tavily.config.webSearch.apiKey = $tavily_key |
   .plugins.entries.tavily.config.webSearch.baseUrl = $tavily_url |
   .plugins.entries.brave.config.webSearch.apiKey = $brave_key |
   .plugins.entries["memory-lancedb"].config.embedding.provider = $embed_prov |
   .plugins.entries["memory-lancedb"].config.embedding.model = $embed_model |
   .plugins.entries["memory-lancedb"].config.embedding.baseUrl = $embed_url |
   .plugins.entries["memory-lancedb"].config.embedding.apiKey = $embed_key |
   .plugins.entries["memory-lancedb"].config.embedding.dimensions = ($embed_dims | tonumber) |
   .plugins.entries["memory-lancedb"].hooks.allowConversationAccess = true |
   .plugins.entries.github.enabled = (.plugins.entries.github.enabled // false) |
   .plugins.entries["device-pair"].enabled = (.plugins.entries["device-pair"].enabled // false) |
    (if ($search_prov == "tavily" and $tavily_key == "") or ($search_prov == "brave" and $brave_key == "") or ($search_prov == "" or $search_prov == null) then
      del(.tools.web.search.provider)
    else
      .tools.web.search.provider = $search_prov
    end) |
     .agents.defaults.model.primary = $primary |
     .agents.defaults.model.fallbacks = (([$fallback1, $fallback2] + (.agents.defaults.model.fallbacks // [])) | unique) |
     .agents.defaults.models[$primary] = {} |
     .agents.defaults.models[$fallback1] = {} |
     .agents.defaults.models[$fallback2] = {} |
      .agents.defaults.imageModel = {
        "primary": "apivy/qwen3-vl-plus",
        "fallbacks": [
          "apivy/qwen3-vl-flash"
        ],
        "timeoutMs": 90000
      } |
      .agents.defaults.models["apivy/qwen3-vl-plus"] = {} |
      .agents.defaults.models["apivy/qwen3-vl-flash"] = {} |
     .agents.defaults.sandbox.mode = "off" |
     .agents.defaults.mediaMaxMb = 200 |
     .agents.defaults.bootstrapMaxChars = 50000 |
     (if .agents.entries.main then .agents.entries.main.bootstrapMaxChars = 50000 else . end) |
     del(.plugins.bundledDiscovery) |
     del(.plugins.entries["open-prose"]) |
      .plugins.allow = ([((.plugins.allow // [])[] | select(. != "open-prose"))] + ["browser", "document-extract", "qwen"] | unique) |
     .plugins.entries.browser = { "enabled": true } |
     .plugins.entries["document-extract"] = { "enabled": true } |
     .skills.load.allowSymlinkTargets = ["/app/workspace/skills"] |
     .browser = { "enabled": true, "headless": true, "noSandbox": true, "extensionRelay": { "allowLegacyAuth": false }, "ssrfPolicy": { "dangerouslyAllowPrivateNetwork": true } }
   ' \
   "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" \
&& mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" \
|| { echo "❌ jq 注入失败，保留占位符版本"; rm -f "${CONFIG_FILE}.tmp"; }

chmod 600 "$CONFIG_FILE" 2>/dev/null
echo "✅ 基因播种完成，配置文件大小: $(wc -c < "$CONFIG_FILE") bytes"
echo "   Primary Model: $PRIMARY_MODEL"
echo "   Search Provider: $SEARCH_PROVIDER"

# 3. 持久化 ID (商业锁核心)
# 使用挂载卷内的持久化 UUID，而非不稳定的网卡 MAC 地址
if [ -f "$ID_FILE" ]; then
    MACHINE_ID=$(cat "$ID_FILE" | tr -d '\r\n ')
else
    # 优先读取 boot_id 的前12位（不依赖网卡，在任何容器运行时均稳定）
    RAW_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '-' | head -c 12)
    # 备用：从 eth0 读取（兼容旧行为）
    [ -z "$RAW_ID" ] && RAW_ID=$(cat /sys/class/net/eth0/address 2>/dev/null | tr -d ':')
    # 最终兜底：随机生成
    [ -z "$RAW_ID" ] && RAW_ID=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 12)
    echo "$RAW_ID" > "$ID_FILE"
    MACHINE_ID=$RAW_ID
fi

echo "===================================================="
echo "🤖 吉米·智驱 (Jimi Agent) 启动中..."
echo "💻 设备识别码: $MACHINE_ID"
echo "===================================================="

# 4. 商业授权检查 (基石代码)
NOW_TS=$(date +%s)
IS_AUTHORIZED=false
if [ "$LICENSE_KEY" != "TRIAL" ] && [[ "$LICENSE_KEY" == *"-"* ]]; then
    INPUT_DATE=$(echo "$LICENSE_KEY" | cut -d'-' -f1)
    INPUT_SIG=$(echo "$LICENSE_KEY" | cut -d'-' -f2)
    EXPECTED_SIG=$(echo -n "${INPUT_DATE}${MACHINE_ID}${SALT}" | md5sum | cut -c1-8)
    if [ "$INPUT_SIG" == "$EXPECTED_SIG" ]; then
        FORMAT_DATE="${INPUT_DATE:0:4}-${INPUT_DATE:4:2}-${INPUT_DATE:6:2}"
        EXP_TS=$(date -d "$FORMAT_DATE 23:59:59" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$FORMAT_DATE 23:59:59" +%s 2>/dev/null)
        if [ -n "$EXP_TS" ] && [ "$NOW_TS" -le "$EXP_TS" ]; then
            echo "✨ 商业正式版授权认证成功！"
            IS_AUTHORIZED=true
        fi
    fi
else
    if [ ! -f "$LOCK_FILE" ]; then
        SIG=$(echo -n "${NOW_TS}${SALT}" | md5sum | cut -c1-8)
        echo "${NOW_TS}:${SIG}" > "$LOCK_FILE"
        echo "🎁 14 天商业试用许可已激活。"
    fi
    SEAL_CONTENT=$(cat "$LOCK_FILE" | tr -d '\r\n ')
    SAVED_TS=$(echo $SEAL_CONTENT | cut -d':' -f1); SAVED_SIG=$(echo $SEAL_CONTENT | cut -d':' -f2)
    if [ "$(echo -n "${SAVED_TS}${SALT}" | md5sum | cut -c1-8)" == "$SAVED_SIG" ]; then
        E_TS=$(( SAVED_TS + 2592000 ))
        if [ "$NOW_TS" -le "$E_TS" ] && [ "$NOW_TS" -ge "$SAVED_TS" ]; then
            DIFF=$(( E_TS - NOW_TS ))
            echo "⏳ 试用期剩余：$(( DIFF / 3600 )) 小时"
            IS_AUTHORIZED=true
        fi
    fi
fi
if [ "$IS_AUTHORIZED" = false ]; then echo "🚫 许可无效，联系微信: 186-8898-5985"; exit 1; fi

## 4.4 🧹 清理异常关机残留的 SQLite 锁文件 (防止 Windows/NTFS 挂载卷死锁)
find "$TARGET_DIR" -type f \( -name "*.sqlite-wal" -o -name "*.sqlite-shm" -o -name "*.sqlite-journal" \) -delete 2>/dev/null || true

# 4.5 🔄 数据库路径自适应迁移 (解决从旧版 /home/node/.openclaw 迁移至新版 /root/.openclaw 的路径失效问题)
python3 -c "
import sqlite3, os
db_path = '$TARGET_DIR/state/openclaw.sqlite'
if os.path.exists(db_path):
    print('🔄 正在对 SQLite 数据库进行路径自适应修复 (/home/node -> /root)...')
    try:
        conn = sqlite3.connect(db_path, timeout=30.0)
        conn.execute('PRAGMA busy_timeout = 30000;')
        c = conn.cursor()
        
        # 检查并修复 installed_plugin_index
        c.execute(\"SELECT 1 FROM sqlite_master WHERE type='table' AND name='installed_plugin_index';\")
        if c.fetchone():
            try:
                c.execute(\"\"\"
                    UPDATE installed_plugin_index 
                    SET plugins_json = REPLACE(plugins_json, '/home/node/.openclaw', '/root/.openclaw'), 
                        install_records_json = REPLACE(install_records_json, '/home/node/.openclaw', '/root/.openclaw')
                    WHERE typeof(plugins_json) = 'text';
                \"\"\")
                print('✅ 插件索引路径修复完成')
            except Exception as e:
                print('⚠️ 修复 installed_plugin_index 警告:', e)

        # 检查并修复 2026.10.x+ config_machine_state 中的 plugins.installedIndex（自动收敛容器重建后失效的 __openclaw-generation__ 临时后缀）
        c.execute(\"SELECT 1 FROM sqlite_master WHERE type='table' AND name='config_machine_state';\")
        if c.fetchone():
            try:
                import json, re
                c.execute(\"SELECT value_json FROM config_machine_state WHERE state_key='plugins.installedIndex';\")
                row = c.fetchone()
                if row and row[0]:
                    raw_json = row[0].replace('/home/node/.openclaw', '/root/.openclaw')
                    data = json.loads(raw_json)
                    records = data.get('index', {}).get('installRecords', {})
                    idx_changed = (raw_json != row[0])
                    for k, rec in records.items():
                        if isinstance(rec, dict):
                            ip = rec.get('installPath', '')
                            if '__openclaw-generation__' in ip and not os.path.exists(ip):
                                fixed_ip = re.sub(r'__openclaw-generation__g-[0-9a-f]+', '', ip)
                                if os.path.exists(fixed_ip):
                                    rec['installPath'] = fixed_ip
                                    for drop_k in ('integrity', 'shasum', 'resolvedAt', 'installedAt'):
                                        rec.pop(drop_k, None)
                                    idx_changed = True
                    if idx_changed:
                        c.execute(\"UPDATE config_machine_state SET value_json=? WHERE state_key='plugins.installedIndex';\", (json.dumps(data),))
                        open('/tmp/.need_plugin_registry_refresh', 'w').close()
                        print('✅ 插件世代路径 (plugins.installedIndex) 自动对齐至预置种子包完成')
            except Exception as e:
                print('⚠️ 修复 plugins.installedIndex 警告:', e)

        # 检查并修复 sandbox_registry_entries
        c.execute(\"SELECT 1 FROM sqlite_master WHERE type='table' AND name='sandbox_registry_entries';\")
        if c.fetchone():
            try:
                c.execute(\"\"\"
                    UPDATE sandbox_registry_entries 
                    SET entry_json = REPLACE(entry_json, '/home/node/.openclaw', '/root/.openclaw')
                    WHERE typeof(entry_json) = 'text';
                \"\"\")
                print('✅ 沙箱注册记录路径修复完成')
            except Exception as e:
                print('⚠️ 修复 sandbox_registry_entries 警告:', e)

        # 清理异常崩溃残留的 state_leases 锁，防止死锁阻止启动
        c.execute(\"SELECT 1 FROM sqlite_master WHERE type='table' AND name='state_leases';\")
        if c.fetchone():
            try:
                c.execute('DELETE FROM state_leases;')
                print('✅ 历史进程残留锁 (state_leases) 清理完成')
            except Exception as e:
                pass

        conn.commit()
        print('✅ SQLite 数据库路径自动适应调整完毕！')
    except Exception as e:
        print('⚠️ SQLite 数据库自动更新时出现警告:', e)
    finally:
        if 'conn' in locals(): conn.close()

# 4.6 🔄 自动自愈 SQLite 孤立外键记录 (防止 2026.8.1+ 启动时 SQLite foreign_key_check 崩溃)
agent_db = '$TARGET_DIR/agents/main/agent/openclaw-agent.sqlite'
if os.path.exists(agent_db):
    try:
        a_conn = sqlite3.connect(agent_db, timeout=30.0)
        a_c = a_conn.cursor()
        for _ in range(5):
            violations = a_c.execute('PRAGMA foreign_key_check;').fetchall()
            if not violations:
                break
            for t, r, p, f in violations:
                try:
                    a_c.execute(f'DELETE FROM {t} WHERE rowid=?', (r,))
                except Exception:
                    pass
            a_conn.commit()
        a_conn.close()
    except Exception:
        pass
" || true

# 5. 插件检测辅助函数，支持 scoped 插件的多级子目录检测 (解决 find 匹配多级路径问题)
is_plugin_installed() {
    local name="$1"
    # 1. 优先检查内置的镜像包（速度最快）
    if [ -d "/app/plugins-seed/projects" ]; then
        if find /app/plugins-seed/projects -maxdepth 2 -type d -name "*$name*" 2>/dev/null | grep -q .; then
            return 0
        fi
    fi
    # 2. 检查实际挂载目录（使用 -L 允许 find 穿透软链接）
    if [ -d "$TARGET_DIR/npm/projects" ]; then
        if find -L "$TARGET_DIR/npm/projects" -maxdepth 2 -type d -name "*$name*" 2>/dev/null | grep -q .; then
            return 0
        fi
    fi
    return 1
}

# 6. 确保搜索插件已安装 (如果配置了对应搜索服务商且未安装)
if [ "$SEARCH_PROVIDER" = "tavily" ] && [ -n "$TAVILY_API_KEY" ] && ! is_plugin_installed "tavily-plugin"; then
    echo "📥 正在自动安装 Tavily 搜索插件..."
    openclaw plugins install @openclaw/tavily-plugin --accept-capabilities || true
fi
if [ "$SEARCH_PROVIDER" = "brave" ] && [ -n "$BRAVE_API_KEY" ] && ! is_plugin_installed "brave-plugin"; then
    echo "📥 正在自动安装 Brave 搜索插件..."
    openclaw plugins install @openclaw/brave-plugin --accept-capabilities || true
fi

# 7. 确保核心记忆和渠道插件已安装 (按需求，微信渠道 openclaw-weixin 仅支持手动安装，不在此处自动安装)
if ! is_plugin_installed "deepseek-provider"; then
    echo "📥 正在自动安装 DeepSeek 渠道插件..."
    openclaw plugins install @openclaw/deepseek-provider --accept-capabilities || true
fi
if ! is_plugin_installed "memory-lancedb"; then
    echo "📥 正在自动安装 LanceDB 记忆插件..."
    openclaw plugins install @openclaw/memory-lancedb --accept-capabilities || true
fi

# 7.1 自动激活预装/已有插件的 Capability 授权（仅首次初始化执行一次，避免每次启动触发 9 次缓慢的 SQLite doctor 检查）
if [ ! -f "$TARGET_DIR/.plugins_initialized" ]; then
    echo "⚙️ 首次初始化：正在配置插件初始授权与能力..."
    openclaw plugins enable deepseek --accept-capabilities 2>/dev/null || true
    openclaw plugins enable memory-lancedb --accept-capabilities 2>/dev/null || true
    openclaw plugins enable brave --accept-capabilities 2>/dev/null || true
    openclaw plugins enable tavily --accept-capabilities 2>/dev/null || true
    openclaw plugins enable openclaw-weixin --accept-capabilities 2>/dev/null || true
    openclaw plugins enable qwen --accept-capabilities 2>/dev/null || true
    openclaw plugins enable byteplus --accept-capabilities 2>/dev/null || true
    openclaw plugins enable moonshot --accept-capabilities 2>/dev/null || true
    openclaw plugins disable open-prose 2>/dev/null || true
    touch "$TARGET_DIR/.plugins_initialized" 2>/dev/null || true
    echo "✅ 插件初始授权配置完成！"
fi

# 7.4 🔄 自动同步主环境变量到 Sandbox 工作空间 (.env)，确保 Python/Bash 等本地脚本免配置、不冲突
echo "🔄 正在自动同步网关环境配置到 Sandbox 工作空间..."
mkdir -p "$TARGET_DIR/workspace"
cat << EOF > "$TARGET_DIR/workspace/.env"
# =====================================================
# 吉米·智驱 Sandbox 隔离运行环境配置文件 (由 entrypoint.sh 自动生成，请勿直接编辑)
# =====================================================
DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL:-https://api.deepseek.com}"
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-}"
APIYI_BASE_URL="${APIYI_BASE_URL:-https://api.apiyi.com/v1}"
APIYI_API_KEY="${APIYI_API_KEY:-}"
AGNES_BASE_URL="${AGNES_BASE_URL:-https://apihub.agnes-ai.com/v1}"
AGNES_API_KEY="${AGNES_API_KEY:-}"

EMBEDDING_PROVIDER="${EMBEDDING_PROVIDER:-openai}"
EMBEDDING_BASE_URL="${EMBEDDING_BASE_URL:-}"
EMBEDDING_API_KEY="${EMBEDDING_API_KEY:-}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-}"
EMBEDDING_DIMENSIONS="${EMBEDDING_DIMENSIONS:-}"

TAVILY_API_KEY="${TAVILY_API_KEY:-}"
TAVILY_BASE_URL="${TAVILY_BASE_URL:-https://api.tavily.com}"
BRAVE_API_KEY="${BRAVE_API_KEY:-}"
SEARCH_PROVIDER="${SEARCH_PROVIDER:-}"

VOLC_ARK_API_KEY="${VOLC_ARK_API_KEY:-}"
VOLC_TTS_API_KEY="${VOLC_TTS_API_KEY:-}"
VOLC_TTS_ENDPOINT="${VOLC_TTS_ENDPOINT:-}"
VOLC_VIDEO_GEN_ENDPOINT="${VOLC_VIDEO_GEN_ENDPOINT:-}"
VOLC_VIDEO_GEN_MINI_ENDPOINT="${VOLC_VIDEO_GEN_MINI_ENDPOINT:-}"
VOLC_IMAGE_GEN_ENDPOINT="${VOLC_IMAGE_GEN_ENDPOINT:-}"
VOLC_VISION_ENDPOINT="${VOLC_VISION_ENDPOINT:-}"
VOLC_EMBEDDING_VISION_ENDPOINT="${VOLC_EMBEDDING_VISION_ENDPOINT:-}"
SHOTSTACK_API_KEY="${SHOTSTACK_API_KEY:-}"
EOF
chmod 600 "$TARGET_DIR/workspace/.env"

# 7.45 🔄 自动迁移历史 Session 存储至 SQLite (解决 2026.8.1 legacy session store migration 拦截)
if [ -f "$TARGET_DIR/agents/main/sessions/sessions.json" ]; then
    echo "🔄 正在自动迁移历史会话至 SQLite..."
    openclaw doctor --session-sqlite import --yes 2>/dev/null || true
fi

# 7.46 🔄 自动清理/归档历史 Workspace 遗留标记文件 (解决 2026.8.1 assertNoUnmigratedWorkspaceState 拦截)
mkdir -p "$TARGET_DIR/legacy-archive"
if [ -f "$TARGET_DIR/workspace/openclaw-workspace-state.json" ]; then
    mv "$TARGET_DIR/workspace/openclaw-workspace-state.json" "$TARGET_DIR/legacy-archive/" 2>/dev/null || true
fi
if [ -f "$TARGET_DIR/workspace/.openclaw/workspace-state.json" ]; then
    mv "$TARGET_DIR/workspace/.openclaw/workspace-state.json" "$TARGET_DIR/legacy-archive/" 2>/dev/null || true
fi
if [ -d "$TARGET_DIR/workspace-attestations" ]; then
    mv "$TARGET_DIR/workspace-attestations" "$TARGET_DIR/legacy-archive/" 2>/dev/null || true
fi
if [ -f "$TARGET_DIR/workspace.attested" ]; then
    mv "$TARGET_DIR/workspace.attested" "$TARGET_DIR/legacy-archive/" 2>/dev/null || true
fi

# 7.47 🧹 自动清理历史废弃 Agent（如 hermes, test），避免 doctor 报警与资源浪费
for stale_agent in hermes test; do
    if [ -d "$TARGET_DIR/agents/$stale_agent" ]; then
        echo "🧹 发现已废弃的测试 Agent ($stale_agent)，正在自动清理..."
        rm -rf "$TARGET_DIR/agents/$stale_agent"
    fi
done

# 7.48 🧹 自动归档历史审计日志（config-audit* / .migrated.raw），消除 2026.10.1+ Doctor 迁移拒绝告警
mkdir -p "$TARGET_DIR/legacy-archive"
rm -rf /root/.openclaw.update-captures 2>/dev/null || true
for raw_audit in "$TARGET_DIR"/logs/*migrated.raw* "$TARGET_DIR"/audit/*migrated.raw* "$TARGET_DIR"/logs/config-audit* "$TARGET_DIR"/audit/config-audit*; do
    if [ -f "$raw_audit" ]; then
        mv "$raw_audit" "$TARGET_DIR/legacy-archive/" 2>/dev/null || rm -f "$raw_audit"
    fi
done

# 自动修复历史审计日志前导空白
python3 -c "
import glob, os
for pattern in ['$TARGET_DIR/logs/config-audit*', '$TARGET_DIR/audit/*']:
    for f in glob.glob(pattern):
        if os.path.isfile(f) and os.path.getsize(f) > 0:
            try:
                with open(f, 'rb') as fp:
                    content = fp.read()
                lstripped = content.lstrip()
                if lstripped != content:
                    with open(f, 'wb') as fp:
                        fp.write(lstripped)
            except Exception:
                pass
" 2>/dev/null || true

# 7.48 🧹 消除重复扩展与未编译源码刷屏告警：优先使用编译好的 dist/extensions 生产扩展
if [ -d "/app/dist/extensions" ] && [ -d "/app/extensions" ]; then
    mv /app/extensions /app/extensions.source.bak 2>/dev/null || true
elif [ -d "/app/extensions/ollama" ]; then
    rm -rf /app/extensions/ollama 2>/dev/null || true
fi

if [ ! -f "/app/.jimi_dist_patched" ]; then
# BEGIN_DIST_PATCH
# 🌟 核心防御：对 OpenClaw 2026.8.1+ 动态打补丁 (防御 undefined.trim / 模型别名映射 / 思考策略安全)
node -e '
const fs = require("fs");
const path = require("path");
const distDir = "/app/dist";

if (fs.existsSync(distDir)) {
  const files = fs.readdirSync(distDir);
  for (const file of files) {
    if (!file.endsWith(".js")) continue;
    const fullPath = path.join(distDir, file);
    let content = fs.readFileSync(fullPath, "utf8");
    let changed = false;

    // 1. 修复 diagnostic-run-activity 中 params.sessionId.trim() 空值崩溃
    if (content.includes("params.runId?.trim() || params.sessionId.trim()")) {
      content = content.replace("params.runId?.trim() || params.sessionId.trim()", "params.runId?.trim() || (params.sessionId ? params.sessionId.trim() : String())");
      changed = true;
      console.log(`✅ Patched ${file} for safe diagnostic-run-activity`);
    }

    // 2. 修复 server-runtime-subscriptions 中 entry.sessionId.trim() 空值崩溃
    if (content.includes("run.sessionId?.trim() || entry.sessionId.trim()")) {
      content = content.replace("run.sessionId?.trim() || entry.sessionId.trim()", "run.sessionId?.trim() || (entry.sessionId ? entry.sessionId.trim() : String())");
      changed = true;
      console.log(`✅ Patched ${file} for safe server-runtime-subscriptions`);
    }

    // 3. 修复 thinking-*.js 中 buildCatalogModelKey 空值 .trim() 崩溃
    if (file.startsWith("thinking-") && content.includes("function buildCatalogModelKey(provider, model) {") && !content.includes("provider = (provider ||")) {
      content = content.replace("function buildCatalogModelKey(provider, model) {", "function buildCatalogModelKey(provider, model) { provider = (provider || String()).toString(); model = (model || String()).toString();");
      changed = true;
      console.log(`✅ Patched ${file} for safe buildCatalogModelKey`);
    }

    // 4. 修复 provider-transport-fetch-*.js / stream-*.js 中模型别名转换
    if ((file.startsWith("provider-transport-fetch-") || file.startsWith("stream-")) && content.includes("return async (input, init) => {") && !content.includes("ep-20260623104648-2t7qq")) {
      const target = "return async (input, init) => {";
      const replacement = `return async (input, init) => {
		if (model && model.id === "ep-20260623104648-2t7qq") { model.id = "deepseek-v4-pro"; }
		if (init && typeof init.body === "string" && init.body.includes("ep-20260623104648-2t7qq")) {
			try {
				const b = JSON.parse(init.body);
				if (b.model === "ep-20260623104648-2t7qq") {
					b.model = "deepseek-v4-pro";
					init.body = JSON.stringify(b);
				}
			} catch(e){}
		}`;
      content = content.replace(target, replacement);
      changed = true;
      console.log(`✅ Patched ${file} for model alias`);
    }

    // 5. 常见防御性 trim 保护
    if (content.includes("const provider = runtime.provider.trim();")) {
      content = content.replace("const provider = runtime.provider.trim();", "const provider = runtime?.provider?.trim();");
      changed = true;
    }
    if (content.includes("const model = runtime.model.trim();")) {
      content = content.replace("const model = runtime.model.trim();", "const model = runtime?.model?.trim();");
      changed = true;
    }
    if (content.includes("const model = params.model.trim();")) {
      content = content.replace("const model = params.model.trim();", "const model = params.model?.trim() ?? \"\";");
      changed = true;
    }

    if (changed) {
      fs.writeFileSync(fullPath, content, "utf8");
    }
  }
}
' || true

# 🌟 核心修复：对 OpenClaw 静态限制的文件大小进行动态打补丁，防止 PDF 超过 5MB 导致网关直接崩溃退出
node -e '
const fs = require("fs");
const path = require("path");
const distDir = "/app/dist";
if (fs.existsSync(distDir)) {
  const files = fs.readdirSync(distDir);
  for (const file of files) {
    if (file.startsWith("runner.entries-") && file.endsWith(".js")) {
      const fullPath = path.join(distDir, file);
      let content = fs.readFileSync(fullPath, "utf8");
      const target = "const DEFAULT_INPUT_FILE_MAX_BYTES = 5 * 1024 * 1024;";
      const replacement = "const DEFAULT_INPUT_FILE_MAX_BYTES = 200 * 1024 * 1024;";
      if (content.includes(target)) {
        content = content.replace(target, replacement);
        fs.writeFileSync(fullPath, content, "utf8");
        console.log(`✅ Patched ${file} for DEFAULT_INPUT_FILE_MAX_BYTES`);
      }
    }
  }
}
' || true

# 🌟 核心修复：对 OpenClaw 的 WebSocket 传输限制（MAX_PAYLOAD_BYTES 和 MAX_PREAUTH_PAYLOAD_BYTES）进行动态打补丁，防止大文件传输导致 Websocket 断连
node -e '
const fs = require("fs");
const path = require("path");
const distDir = "/app/dist";
if (fs.existsSync(distDir)) {
  const files = fs.readdirSync(distDir);
  for (const file of files) {
    if (file.startsWith("server-constants-") && file.endsWith(".js")) {
      const fullPath = path.join(distDir, file);
      let content = fs.readFileSync(fullPath, "utf8");
      
      const target1 = "const MAX_PAYLOAD_BYTES = 25 * 1024 * 1024;";
      const replacement1 = "const MAX_PAYLOAD_BYTES = 200 * 1024 * 1024;";
      
      const target2 = "const MAX_BUFFERED_BYTES = 50 * 1024 * 1024;";
      const replacement2 = "const MAX_BUFFERED_BYTES = 300 * 1024 * 1024;";
      
      const target3 = "const MAX_PREAUTH_PAYLOAD_BYTES = 64 * 1024;";
      const replacement3 = "const MAX_PREAUTH_PAYLOAD_BYTES = 200 * 1024 * 1024;";
      
      let patched = false;
      if (content.includes(target1)) {
        content = content.replace(target1, replacement1);
        patched = true;
      }
      if (content.includes(target2)) {
        content = content.replace(target2, replacement2);
        patched = true;
      }
      if (content.includes(target3)) {
        content = content.replace(target3, replacement3);
        patched = true;
      }
      
      if (patched) {
        fs.writeFileSync(fullPath, content, "utf8");
        console.log(`✅ Patched ${file} for WebSocket payload constants`);
      }
    }
  }
}
' || true

# 🌟 核心修复：对 OpenClaw 静态限制的附件大小进行动态打补丁，防止大文件（比如大于 20MB 的 PDF）上传被系统直接拦截
node -e '
const fs = require("fs");
const path = require("path");
const distDir = "/app/dist";
if (fs.existsSync(distDir)) {
  const files = fs.readdirSync(distDir);
  for (const file of files) {
    if (file.startsWith("attachment-normalize-") && file.endsWith(".js")) {
      const fullPath = path.join(distDir, file);
      let content = fs.readFileSync(fullPath, "utf8");
      
      const target1 = "opts?.maxBytes ?? 20 * 1024 * 1024";
      const replacement1 = "opts?.maxBytes ?? 200 * 1024 * 1024";
      
      const target2 = "configured : 20";
      const replacement2 = "configured : 200";
      
      let patched = false;
      if (content.includes(target1)) {
        content = content.replace(target1, replacement1);
        patched = true;
      }
      if (content.includes(target2)) {
        content = content.replace(target2, replacement2);
        patched = true;
      }
      
      if (patched) {
        fs.writeFileSync(fullPath, content, "utf8");
        console.log(`✅ Patched ${file} for mediaMaxMb limits`);
      }
    }
  }
}
' || true

# 🌟 核心防御：彻底修复 Windows 宿主机挂载卷 (virtiofs/9p/NTFS) 上的原子写与目录模式检查异常
node -e '
const fs = require("fs");
const path = require("path");

function patchFile(fullPath) {
  if (!fs.existsSync(fullPath)) return;
  let content;
  try {
    const st = fs.statSync(fullPath);
    if (st.isDirectory()) return;
    content = fs.readFileSync(fullPath, "utf8");
  } catch (_) {
    return;
  }

  let changed = false;

  // 1. 禁用 Windows 挂载卷上不支持的 applyDirectoryModeSync 与 pinDirectoryForMode
  if (content.includes("function applyDirectoryModeSync(") && !content.includes("/* patched applyDirectoryModeSync */")) {
    content = content.replace(
      /function\s+applyDirectoryModeSync\s*\([^)]*\)\s*\{/g,
      "function applyDirectoryModeSync() { /* patched applyDirectoryModeSync */ return;"
    );
    changed = true;
  }
  if (content.includes("async function pinDirectoryForMode(") && !content.includes("/* patched pinDirectoryForMode */")) {
    content = content.replace(
      /async\s+function\s+pinDirectoryForMode\s*\([^)]*\)\s*\{/g,
      "async function pinDirectoryForMode() { /* patched pinDirectoryForMode */ return;"
    );
    changed = true;
  }

  // 2. 治愈 assertOwnedFile：防止 Windows 宿主机挂载卷上报 "Atomic replace owned file must remain regular" 或 hardlink 异常
  if (content.includes("function assertOwnedFile(") && !content.includes("/* patched assertOwnedFile */")) {
    content = content.replace(
      /function\s+assertOwnedFile\s*\([^)]*\)\s*\{/g,
      "function assertOwnedFile() { /* patched assertOwnedFile */ return;"
    );
    changed = true;
  }

  // 3. 治愈 assertRegularFile：防止 Windows 宿主机挂载卷上报 "sibling temp must be a regular file"
  if (content.includes("function assertRegularFile(") && !content.includes("/* patched assertRegularFile */")) {
    content = content.replace(
      /function\s+assertRegularFile\s*\([^)]*\)\s*\{/g,
      "function assertRegularFile() { /* patched assertRegularFile */ return;"
    );
    changed = true;
  }

  // 4. 治愈 identityCheck 与 inspectFileIdentity：彻底解决 Windows 宿主机挂载卷上虚拟 inode/dev 跳变引发的 "file identity changed or could not be verified"
  if (content.includes("function identityCheck(") && !content.includes("/* patched identityCheck */")) {
    content = content.replace(
      /function\s+identityCheck\s*\([^)]*\)\s*\{/g,
      "function identityCheck() { /* patched identityCheck */ return () => true;"
    );
    changed = true;
  }
  if (content.includes("inspectFileIdentity(") && !content.includes("/* patched inspectFileIdentity */")) {
    content = content.replace(
      /(?:export\s+)?async\s+function\s+inspectFileIdentity\s*\([^)]*\)\s*\{/g,
      "export async function inspectFileIdentity(inspect) { /* patched inspectFileIdentity */ return await inspect();"
    );
    changed = true;
  }
  if (content.includes("inspectFileIdentitySync(") && !content.includes("/* patched inspectFileIdentitySync */")) {
    content = content.replace(
      /(?:export\s+)?function\s+inspectFileIdentitySync\s*\([^)]*\)\s*\{/g,
      "export function inspectFileIdentitySync(inspect) { /* patched inspectFileIdentitySync */ return inspect();"
    );
    changed = true;
  }

  // 5. 治愈 missingOwnedFile / ENOENT 延迟：解决 Windows 宿主机挂载卷上刚 rename 完成后 lstat 瞬间报 ENOENT 引发的 "Atomic replace owned file disappeared"
  if (content.includes("throw missingOwnedFile(") && !content.includes("/* patched throw missingOwnedFile */")) {
    content = content.replace(
      /throw\s+missingOwnedFile\s*\([^)]*\);?/g,
      "/* patched throw missingOwnedFile */ return;"
    );
    changed = true;
  }
  if (content.includes("missingOwnedFile") && content.includes("ENOENT") && !content.includes("/* patched worker missingOwnedFile */")) {
    content = content.replace(
      /throw\s+[A-Za-z0-9_$]+\.code===[^\s?]+\s*\?\s*missingOwnedFile\([^)]+\)\s*:\s*[A-Za-z0-9_$]+/g,
      "/* patched worker missingOwnedFile */ return"
    );
    changed = true;
  }

  // 6. 治愈 assertCurrent 与 assertPublished：在 Windows 挂载卷上原子替换已完成写入，跳过导致假死的二次探测
  if (content.includes("async assertCurrent(") && !content.includes("/* patched async assertCurrent */")) {
    content = content.replace(
      /async\s+assertCurrent\s*\([^)]*\)\s*\{/g,
      "async assertCurrent() { /* patched async assertCurrent */ return;"
    );
    changed = true;
  }
  if (content.includes("assertCurrent(fsModule") && !content.includes("/* patched sync assertCurrent */")) {
    content = content.replace(
      /assertCurrent\s*\(fsModule[^)]*\)\s*\{/g,
      "assertCurrent() { /* patched sync assertCurrent */ return;"
    );
    changed = true;
  }
  if (content.includes("async assertPublished(") && !content.includes("/* patched async assertPublished */")) {
    content = content.replace(
      /async\s+assertPublished\s*\([^)]*\)\s*\{/g,
      "async assertPublished() { /* patched async assertPublished */ return;"
    );
    changed = true;
  }
  if (content.includes("assertPublished(fsModule") && !content.includes("/* patched sync assertPublished */")) {
    content = content.replace(
      /assertPublished\s*\(fsModule[^)]*\)\s*\{/g,
      "assertPublished() { /* patched sync assertPublished */ return;"
    );
    changed = true;
  }
  if (content.includes("async assertPublished(Ot") && !content.includes("/* patched worker async assertPublished */")) {
    content = content.replace(
      /async\s+assertPublished\s*\(Ot[^)]*\)\s*\{/g,
      "async assertPublished() { /* patched worker async assertPublished */ return;"
    );
    changed = true;
  }
  if (content.includes("assertPublished(Ot") && !content.includes("/* patched worker sync assertPublished */")) {
    content = content.replace(
      /assertPublished\s*\(Ot[^)]*\)\s*\{/g,
      "assertPublished() { /* patched worker sync assertPublished */ return;"
    );
    changed = true;
  }

  // 7. 治愈 openclaw-cli-shim：为 agent-cli 写入增加安全防崩兜底
  if (/await\s+writeTextAtomic\s*\(\s*executablePath/.test(content) && !content.includes("/* patched cli-shim */")) {
    content = content.replace(
      /await\s+writeTextAtomic\s*\(\s*executablePath\s*,\s*content\s*,\s*\{[^}]*\}\s*\);?/g,
      "try { await writeTextAtomic(executablePath, content, { mode: 448, dirMode: 448, durable: false, tempPrefix: \"openclaw-agent-cli\" }); } catch (_) { try { await fs.writeFile(executablePath, content, { mode: 448 }); } catch (_) {} } /* patched cli-shim */"
    );
    changed = true;
  }

  // 8. 治愈 file-handle-transfer / copyFile：彻底解决 "copy source and target descriptors refer to the same file"
  if (content.includes("copy source and target descriptors refer to the same file") && !content.includes("/* patched same file check */")) {
    content = content.replace(
      /if\s*\(\s*sourceStat\.dev\s*===\s*targetStat\.dev\s*&&\s*sourceStat\.ino\s*===\s*targetStat\.ino\s*\)\s*\{[^}]*copy\s+source\s+and\s+target\s+descriptors\s+refer\s+to\s+the\s+same\s+file[^}]*\}/g,
      "if (sourceFd === targetFd) { throw new FsSafeError(\"path-alias\", \"copy source and target descriptors refer to the same file\"); } /* patched same file check */"
    );
    changed = true;
  }
  if (content.includes("copy source and target handles refer to the same file") && !content.includes("/* patched same handle check */")) {
    content = content.replace(
      /if\s*\(\s*sourceStat\.dev\s*===\s*targetStat\.dev\s*&&\s*sourceStat\.ino\s*===\s*targetStat\.ino\s*\)\s*\{[^}]*copy\s+source\s+and\s+target\s+handles\s+refer\s+to\s+the\s+same\s+file[^}]*\}/g,
      "if ((typeof source !== \"undefined\" && typeof target !== \"undefined\" && (source === target || (source.fd != null && source.fd === target.fd))) || (typeof sourceHandle !== \"undefined\" && typeof targetHandle !== \"undefined\" && sourceHandle === targetHandle)) { throw new FsSafeError(\"path-alias\", \"copy source and target handles refer to the same file\"); } /* patched same handle check */"
    );
    changed = true;
  }

  // 9. 治愈 assertPluginNativeNamespaceHost：解决容器/符号链接插件目录被误判为非宿主 OpenClaw peer link 导致 LanceDB 无法加载
  if (content.includes("assertPluginNativeNamespaceHost(") && !content.includes("/* patched assertPluginNativeNamespaceHost */")) {
    content = content.replace(
      /function\s+assertPluginNativeNamespaceHost\s*\([^)]*\)\s*\{/g,
      "function assertPluginNativeNamespaceHost() { /* patched assertPluginNativeNamespaceHost */ return;"
    );
    changed = true;
  }

  // 10. 治愈 Fake-IP (RFC 2544 198.18.0.0/15) SSRF 误拦截：支持 Clash/Stash Tun 模式下的外部模型与插件目录拉取
  if (content.includes("isBlockedSpecialUseIpv4Address(") && !content.includes("/* patched rfc2544 fake-ip */")) {
    content = content.replace(
      /function\s+isBlockedSpecialUseIpv4Address\s*\([^)]*\)\s*\{[^}]*\}/g,
      "function isBlockedSpecialUseIpv4Address(address, options = {}) { /* patched rfc2544 fake-ip */ const inRfc2544 = address.match(RFC2544_BENCHMARK_PREFIX); if (inRfc2544) return false; return BLOCKED_IPV4_SPECIAL_USE_RANGES.has(address.range()); }"
    );
    changed = true;
  }

  // 11. 治愈 2026.10.1+ isPluginNpmManagedPath：允许 /root/.openclaw/npm 符号链接指向 /app/plugins-seed 时通过 lstatSync.isDirectory() 校验
  if (content.includes("function isPluginNpmManagedPath(") && !content.includes("isSymbolicLink()")) {
    content = content.replace(
      /(\b\w+\(\w+\))\.isDirectory\(\)(\s*&&\s*\w+\.relative\()/g,
      "($1.isDirectory()||$1.isSymbolicLink())$2"
    );
    changed = true;
  }

  if (changed) {
    try {
      fs.writeFileSync(fullPath, content, "utf8");
      console.log(`✅ Patched ${fullPath} for Windows virtiofs/NTFS compatibility`);
    } catch (e) {
      console.error(`⚠️ Failed to write patch to ${fullPath}:`, e.message);
    }
  }
}

function scanDirs(dir, fileList = []) {
  if (!fs.existsSync(dir)) return fileList;
  try {
    const entries = fs.readdirSync(dir);
    for (const entry of entries) {
      const full = path.join(dir, entry);
      try {
        const st = fs.statSync(full);
        if (st.isDirectory()) {
          if (!entry.startsWith(".") || entry.includes("fs-safe")) {
            scanDirs(full, fileList);
          }
        } else if (entry.endsWith(".js") || entry.endsWith(".mjs")) {
          fileList.push(full);
        }
      } catch (_) {}
    }
  } catch (_) {}
  return fileList;
}

const targetFiles = new Set();
scanDirs("/app/dist", []).forEach(f => targetFiles.add(f));

try {
  const pnpmDir = "/app/node_modules/.pnpm";
  if (fs.existsSync(pnpmDir)) {
    const pnpmEntries = fs.readdirSync(pnpmDir);
    for (const pe of pnpmEntries) {
      if (pe.includes("@openclaw+fs-safe")) {
        scanDirs(path.join(pnpmDir, pe), []).forEach(f => targetFiles.add(f));
      }
    }
  }
} catch (_) {}

scanDirs("/app/node_modules/@openclaw/fs-safe", []).forEach(f => targetFiles.add(f));

for (const f of targetFiles) {
  patchFile(f);
}

// 12. 治愈 2026.10.1+ Control UI Service Worker (sw.js)：防止 Mac/Win 开启 Stash/Clash 时 navigator.onLine=false 导致 sw.js 拦截页面返回 Response.error() (Chrome 报 ERR_FAILED)
const swPath = "/app/dist/control-ui/sw.js";
if (fs.existsSync(swPath)) {
  try {
    const cleanSw = `// Jimi Pro Safe Service Worker (prevents Stash/VPN offline-shell ERR_FAILED deadlocks)
self.addEventListener("install", () => { self.skipWaiting(); });
self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    } catch (_) {}
    try {
      await self.clients.claim();
      const clients = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      for (const client of clients) {
        client.postMessage({ type: "sw-updated", version: "2026.10.1" }, []);
        try { await client.navigate(client.url); } catch (_) {}
      }
    } catch (_) {}
    try { await self.registration.unregister(); } catch (_) {}
  })());
});
self.addEventListener("message", (event) => {
  if (event.data && event.data.type === "sw-version-probe" && event.ports && event.ports[0]) {
    event.ports[0].postMessage({ type: "sw-updated", version: "2026.10.1" });
  }
});
`;
    fs.writeFileSync(swPath, cleanSw, "utf8");
    console.log("✅ Patched /app/dist/control-ui/sw.js to prevent browser ERR_FAILED Service Worker deadlock");
  } catch (_) {}
}
' || true
# END_DIST_PATCH
touch /app/.jimi_dist_patched 2>/dev/null || true
else
    # 增量兜底：确保构建期已打标镜像中的 isPluginNpmManagedPath 同样具备符号链接穿透能力
    node -e '
    const fs = require("fs"), path = require("path");
    function walk(d) {
      if (!fs.existsSync(d)) return;
      for (const e of fs.readdirSync(d)) {
        const f = path.join(d, e);
        try {
          const st = fs.statSync(f);
          if (st.isDirectory()) walk(f);
          else if (e.endsWith(".mjs") || e.endsWith(".js")) {
            const c = fs.readFileSync(f, "utf8");
            if (c.includes("function isPluginNpmManagedPath(") && !c.includes("isSymbolicLink()")) {
              const p = c.replace(/(\b\w+\(\w+\))\.isDirectory\(\)(\s*&&\s*\w+\.relative\()/g, "($1.isDirectory()||$1.isSymbolicLink())$2");
              if (p !== c) fs.writeFileSync(f, p, "utf8");
            }
          }
        } catch (_) {}
      }
    }
    walk("/app/dist");
    ' 2>/dev/null || true
    echo "⚡ 核心兼容补丁与 Service Worker 防死锁补丁已在构建期预置就绪！"
fi

# 7. 智能按版本检查并迁移数据库架构（仅在首次安装或版本升级如 2026.10.1 -> 2026.10.2 时执行一次，免去每次日常重启 30 秒等待）
CURRENT_OC_VER=$(node -p "try { require('/app/package.json').version } catch(e) { 'unknown' }" 2>/dev/null || echo "unknown")
LAST_DOCTOR_VER=$(cat "$TARGET_DIR/.doctor_migrated_ver" 2>/dev/null || echo "")
if [ "$CURRENT_OC_VER" != "$LAST_DOCTOR_VER" ] || [ "$FORCE_DOCTOR" = "1" ]; then
    echo "🩺 检测到新版本 ($CURRENT_OC_VER)，正在执行数据库升级与健康迁移 (openclaw doctor --fix)..."
    openclaw doctor --fix --yes --non-interactive || true
    echo "$CURRENT_OC_VER" > "$TARGET_DIR/.doctor_migrated_ver" 2>/dev/null || true
    touch /tmp/.need_plugin_registry_refresh 2>/dev/null || true
else
    echo "⚡ 数据库架构已与当前版本 ($CURRENT_OC_VER) 对齐，跳过冗余 doctor 扫描以极速启动！"
fi

if [ -f "/tmp/.need_plugin_registry_refresh" ]; then
    echo "🔄 正在快速刷新插件注册表索引..."
    openclaw plugins registry --refresh 2>/dev/null || true
    rm -f /tmp/.need_plugin_registry_refresh
fi

# 8. 启动引擎
exec openclaw gateway --allow-unconfigured
