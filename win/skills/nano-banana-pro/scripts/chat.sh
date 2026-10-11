#!/bin/bash
# 快速测试 nano-banana-pro 模型
# 用法: ./chat.sh "你的问题"

API_KEY="${APIYI_API_KEY}"
if [ -z "$API_KEY" ] || [ "$API_KEY" = "YOUR_API_KEY_HERE" ]; then
  API_KEY="${DEEPSEEK_API_KEY}"
fi
BASE_URL="${APIYI_BASE_URL:-https://api.apiyi.com/v1}"
MODEL="nano-banana-pro"
PROMPT="${1:-你好}"

curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}]
  }" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['choices'][0]['message']['content'])
"
