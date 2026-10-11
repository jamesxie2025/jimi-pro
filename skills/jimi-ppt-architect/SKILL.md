---
name: jimi-ppt-architect
description: 吉米PPT架构师：python-pptx全自定义排版，卡片/表格/色彩系统，咨询级PPTX生成
version: sha256:66cadc1e225f1092
---

# Jimi PPT Architect v2

吉米专属 PPT 架构师技能：根据结构化的 JSON 数据，利用 python-pptx 自动生成咨询级的 PowerPoint (PPTX) 演示文稿。

## 核心理念

**不是生成纯文字列表，而是构建专业视觉叙事。** 每一页都应该有明确的视觉层次：色条引导 → 标题区 → 内容卡片/表格 → 底部洞察栏。

## 工作流程

### 第一步：分析需求，确定 PPT 风格与结构

从用户需求中提取：
- **主题色调**：默认浅色/白色底（除非用户明确要求深色）
- **页数结构**：封面 → 摘要 → 内容页 → 对比页 → ROI/价值页 → 行动号召
- **信息密度**：每页 3-5 个要点，用卡片或表格承载

### 第二步：生成结构化 JSON 大纲

JSON Schema（扩展版）：

```json
{
  "title": "封面主标题",
  "subtitle": "封面副标题",
  "theme": "light|dark",
  "slides": [
    {
      "type": "summary|cards|table|comparison|roi|cta",
      "title": "页标题",
      "section_label": "// SECTION",
      "items": [
        {
          "icon": "🎯",
          "title": "卡片标题",
          "body": "卡片内容（支持换行）",
          "accent": "blue|green|orange|purple|gold"
        }
      ],
      "table": {
        "headers": ["列1", "列2"],
        "rows": [["数据", "数据"]],
        "accent_colors": ["blue", "green"]
      },
      "insight": "底部洞察文字"
    }
  ]
}
```

**页面类型说明：**
- `summary`：多卡片并列（2-4 张）
- `cards`：功能/模块卡片网格（4-8 张）
- `table`：完整对比表格
- `comparison`：左右/三栏对比
- `roi`：投资回报卡片 + 徽章
- `cta`：行动号召 + 联系方式

### 第三步：用 python-pptx 全自定义渲染

不使用默认模板布局。每页从 blank layout 开始，手动放置所有元素。

**色彩系统（浅色主题，默认）：**
```
背景: #FFFFFF
卡片: #F6F8FA
主文字: #1F2328
副文字: #656D76
蓝色: #0969DA
绿色: #1A7F37
橙色: #BC4C00
紫色: #8250DF
金色: #9A6700
```

**色彩系统（深色主题）：**
```
背景: #0D1117
卡片: #161B22
主文字: #E6EDF3
副文字: #8B949E
蓝色: #58A6FF
绿色: #3FB950
橙色: #F78166
紫色: #A371F7
金色: #F0C040
```

**布局规范：**
- 16:9 宽屏 (13.333" × 7.5")
- 顶部 3pt 色条 + section label + 标题 + 2pt 下划线
- 内容区距左 0.8"，卡片间距 0.25"
- 每张卡片顶部 2-3pt 彩色强调条
- 底部常驻洞察栏（可选）

**核心渲染函数：**
```python
def add_bg(slide, color): ...
def add_rect(slide, left, top, w, h, fill, line, radius): ...
def add_accent_bar(slide, left, top, w, h, color): ...
def add_text_box(slide, left, top, w, h, text, size, color, bold, align): ...
def add_rich_text(slide, left, top, w, h, lines): ...
def build_card(slide, x, y, w, h, icon, title, body, accent): ...
def build_table(slide, left, top, w, h, headers, rows, accents): ...
def build_roi_card(slide, x, y, w, h, name, cost, return_val, roi, accent): ...
```

### 渲染命令

```bash
python3 /path/to/build_ppt.py
# 脚本内部包含 JSON 数据 + 渲染函数，一键生成
```

脚本应自包含（一个 .py 文件），方便一键生成。

## 设计原则

1. **层次分明**：色条 → 标签 → 标题 → 内容 → 洞察，自上而下
2. **色彩克制**：每页最多 3 种强调色，蓝绿金紫各司其职
3. **卡片为王**：信息用卡片承载，不用大段文字
4. **数据突出**：ROI 数字用大号粗体 + 彩色徽章
5. **表格清晰**：表头深色填充，数据行条纹交替
6. **默认浅色底**：适合打印和企业展示，用户要求深色时再切换
7. **字体降级**：优先 Arial / Microsoft YaHei，保证跨平台兼容

## 注意事项

- 生成的 PPT 文件路径统一放在 `workspace/output/<项目名>/` 下
- 完成后告知用户文件路径和页数结构
- 避免 emoji 在不支持的系统字体上显示为方框
- 所有文字必须在文本框边界内，不允许溢出
