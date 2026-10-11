---
name: "nano-banana-pro"
description: "API易 gemini-3-pro-image-preview 图片生成+视觉对话"
---

# nano-banana-pro

## 概述

通过 API易平台调用 **gemini-3-pro-image-preview** (Nano Banana Pro) 模型，支持图片生成和视觉理解。
Base URL: 载自环境变量 `APIYI_BASE_URL` (默认: `https://api.apiyi.com/v1`)
API Key: 载自环境变量 `APIYI_API_KEY` (在宿主机的 `.env` 中填写，容器启动后自动同步到隔离沙箱内)

## 真实模型 ID

| 特性 | 值 |
|------|------|
| 模型 ID | `gemini-3-pro-image-preview` |
| 最高分辨率 | 4K |
| 按次计费 | $0.09/次 |
| 输入支持 | text + image |

## 使用方法

调用方式为标准 OpenAI chat completions API：

```bash
# 宿主机的 .env 已配置好 APIYI_API_KEY 后，在隔离沙箱内可直接执行：
curl $APIYI_BASE_URL/chat/completions \
  -H "Authorization: Bearer $APIYI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-3-pro-image-preview",
    "messages": [{"role": "user", "content": "你的问题"}]
  }'
```

## Python 示例

```python
import os
import openai

# 自动从 entrypoint 写入的 Sandbox 环境变量中加载配置，无需任何硬编码
client = openai.OpenAI(
    base_url=os.environ.get("APIYI_BASE_URL", "https://api.apiyi.com/v1"),
    api_key=os.environ.get("APIYI_API_KEY")
)

# 文字对话
response = client.chat.completions.create(
    model="gemini-3-pro-image-preview",
    messages=[{"role": "user", "content": "你好"}]
)

# 图片生成（通过 prompt 描述）
response = client.chat.completions.create(
    model="gemini-3-pro-image-preview",
    messages=[{
        "role": "user",
        "content": [
            {"type": "text", "text": "生成一张科技感海报"}
        ]
    }],
    max_tokens=2000
)
```

## 支持流式与非流式

默认使用非流式。如需流式，添加 `"stream": true` 到请求体。
