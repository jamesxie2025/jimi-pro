---
name: "shotstack-edit-v1"
description: "用 Shotstack Edit API v1（生产 https://api.shotstack.io/edit/v1）通过 JSON 时间轴批量生成短视频。适合'Excel素材表 → 批量成片'的服装/电商/营销引流视频流水线。支持图片/视频成片、中文标题、AI配音(TTS)、BGM、转场、Ken Burns 动画。含 V2 修复：简体中文字体(NotoSansSC)、无黑屏交叉溶解转场、精致渐变收尾。"
---

# Shotstack Edit API v1 视频流水线

云端批量生成服装/电商引流视频。**Excel 素材表 → Ingest 传素材 → build_json → render 出片**。

## 核心常量（生产环境）
- **Render 端点**: `POST https://api.shotstack.io/edit/v1/render`、`GET .../render/{id}`
- **Ingest 端点**: `https://api.shotstack.io/ingest/v1`
- **API Key**: `bWKfgZ4Kc8P53RJROL12A7ndBvfDTdVMLNas9xN2`（Header `x-api-key`）
- **Owner**: `bg0x0876rv`；成片暂存 S3 URL **24h 过期**，需及时下载
- 渲染约 77s（17s 成片含 TTS）；成片 1080x1440 竖版、17s、H.264+AAC

## 一键流水线（如何用）
```bash
cd /app/workspace/skills/shotstack-edit-v1/scripts
# ① 素材入库：Ingest 直传 Shotstack 悉尼 S3（--img-only 跳过视频，--max-per 控制张数）
python3 ingest.py --dir /data/视频测试 --only SKU1,SKU2 --img-only --max-per 5 --timeout 50 --out map.json
# ② Excel → 每产品渲染 JSON（表头在 openpyxl iter_rows idx2，即 Excel R3）
python3 build_json.py --xlsx /data/视频测试/亿柚服饰_视频素材录入表.xlsx --uploads map.json --out json/ --products SKU1,SKU2
# ③ 提交+轮询+下载（--submit-only 只提交；--poll 轮询）
python3 render.py --json json/ --out videos/ --poll --only SKU1,SKU2
```

## 素材公网化（必备前置）
Shotstack 只接受 `http(s)://` 的 src；本地路径/base64 data URI 拒绝。用 **Ingest API** 直传其悉尼 S3（快且稳，替代临时图床如 tmpfiles——后者会导致渲染失败）：
```
① POST /ingest/v1/upload        → 拿签名 S3 URL（无 body，不能带 filename 参数，否则 400）
② PUT  文件 → 签名 URL（Content-Type: application/octet-stream）
③ GET  /ingest/v1/sources/{id} → 轮询 status=ready，取 source URL
```
⚠️ 用**同步串行 + 短超时(50s ready)** 调 ingest.py：并行轮询版会卡在少数大视频的 importing 状态。

## 🇨🇳 中文文字（V2 关键修复）
- **必须用简体中文字体**（修复乱码豆腐块带叉）：
  ```json
  "fonts": [{"src":"https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/fonts/NotoSansSC-Regular.otf"}]
  ```
  `font.family` 写 `"NotoSansSC-Regular"`。**不要用** `NotoSansTC`（繁体子集，简体缺字→乱码）。
- **rich-text schema（已踩坑修正，防 400）**：
  - `font`: `{family, size, color, weight}`（weight 100~900）
  - `stroke`/`shadow`/`background`/`style` 都是 **asset 级**（与 font 平级，不在 font 内）
    - `stroke: {width, color, opacity}`
    - `shadow: {offsetX, offsetY, blur, color, opacity}`
    - `background: {color, borderRadius}`
    - `style: {letterSpacing, textTransform}`
  - `animation: {preset, duration, style:"word|character", direction}`
  - `align: {horizontal:"center|left|right", vertical:"top|middle|bottom"}`
  - position/offset/fit/scale/width/height 放 **clip 对象**，不是 asset。放错报 `unknown_property ... .asset`
- 标题动画 preset：`fadeIn|typewriter|slideIn|slideUp|slideDown|shift|ascend`

## ↪️ 转场（V2 修复"黑屏过渡"）
- **避免黑屏**: 用 `fade` 淡出会退到背景色(暗)→黑屏感。**改用相邻图重叠交叉溶解**：后一张 clip 的 `start` 提前上一张结束前的某秒（如 0.5s），上图还显示时下图叠入，形成 dissolve 而非黑屏。
- 图片加 **Ken Burns**：`effect: "zoomIn|zoomOut|zoomInSlow|zoomOutSlow|zoomInFast|zoomOutFast"` 让切换平滑、有高级动画感。
- transition 值：`fade|fadeSlow|fadeFast`（仅开场淡入/结尾淡出用即可）。

## 🗣️ AI 配音（text-to-speech）
- 中文普通话：`"voice":"Zhiyu","language":"cmn-CN"`（女声）；粤语 `Hiujin`+`yue-CN`
- 文案=「钩子+这件商品名+最多2个卖点+引流话术」，读得自然不生硬。
- clip `length:"auto"` 让画面随配音自动对齐。

## 🎵 BGM（V2：更优美，官方曲目）
只放 **Shotstack 官方 s3-ap-southeast-2 音乐库**（农场必可拉，避免 403/抓取失败）：
```
unminus/palmtrees.mp3  宁静氛围 ✓(200)
freepd/fireworks.mp3   轻快 ✓(200)
freepd/advertising.mp3 广告感 ✓(200)
unminus/lit.mp3        律动 ✓(200)
```
`soundtrack: {"src":bgm,"effect":"fadeInFadeOut","volume":0.55}` 淡入淡出有质感。

## 🎨 模板配色（V2）
- 底 `#0E1626`（深墨蓝，非纯黑）；主强调 `#FABC3C`(暖金)、辅助 `#FF5E7E`(玫红)
- **去掉整块实色 banner 大卡**（Jim 嫌黄色大方块突兀）。改：主图衬底 + `html` 底部半透明渐变蒙版(linear-gradient to top) + 白字标题 + 金色品牌名 `YIYOU 亿柚` 收尾。
- 卖点用 `✦`+白字+阴影(font shadow)，优雅不抢主体。

## ✅ 每条成片结构（3:4 / 1080x1440，约 15~17s）
钩子开场(主图+Ken Burns+封面大字 slideDown) → 中间N段(重叠交叉溶解+Ken Burns轮换+卖点✦字卡+渐变蒙版) → 结尾卡(主图+渐变+爆款标题 typewriter+引流话术+品牌名)。

## 🔧 脚本
```
scripts/ingest.py          素材入库(Ingest API 同步串行)
scripts/upload_assets.py   单文件/批量上传辅助
scripts/build_json.py      Excel+上传映射 → 每产品渲染 JSON
scripts/render.py          提交+轮询+下载成片
```
注意输出路径规范：成片存 `/data/michelle_output/<日期_任务名>/videos/`，副本放 workspace/output。

## ⚠️ 常见坑
- BGM 用 403(local)但农场可拉的：以渲染端为准；只放上面官方列表最稳。
- 渲染 JSON 顶层**不可有未知字段**（如 `total` 会 400）。build_json 返回 dict 不含 total。
- `background` 只有 `color`（无 `fill`）；`animation.style` 只接受 `character|word`（无 `full`）。
- Excel 真表头在 iter_rows **idx2**（R3），值如 `'产品编号'` 来自清洗表头 `split("[")[0]`；跳过产品编号空行。
- 渲染前先 `python3 -m py_compile scripts/*.py` + 用 1 个产品试渲染 (--only) 验证整链。

---

## 🎬 模式2：多段视频 → 品牌展示片(Showreel)

把【同一场景/产品】的多段视频合成一支有节奏的展示片。与模式1 互补。

### 完整工作流（已验证可复用）
```bash
cd /app/workspace/skills/shotstack-edit-v1/scripts
# ① 素材入库（平面目录直接传；ingest.py 只扫子目录，flat 视频用内联脚本，见 video_test 例）
python3 vt_ingest.py           # 产出 {文件名: sourceURL} JSON（或改用 ingest.py 的子目录结构）

# ② 生成展示片 JSON（顺序clip, 不重叠！重叠→文字轨文字消失 已实测）
python3 showreel.py --map vt_map.json --dur vt_dur.json --out json/showreel.json \
    --title "深蓝针织开衫 · 卡其半身裙" --subtitle "一衣多穿 · 气质通勤" \
    --brand "YIYOU 亿柚" --cta "喜欢这套的私信我~" \
    --captions "卖点1,卖点2,卖点3" --bgm palmtrees --ratio 16:9 --audio duck --vol 0.5

# ③ 渲染出无字幕版本
python3 render.py --json json/ --out videos/ --poll --only showreel

# ④ 本地烧录中文（保证文字必现；Shotstack 的 video 轨+rich-text overlay 偶发不渲染！）
#    用 --times "开始-结束:文案" 换行分隔
python3 burn_text.py --in videos/showreel.mp4 --out videos/showreel_final.mp4 \
    --title "深蓝针织开衫 · 卡其半身裙" \
    --times "3.4-11.7:V领针织开衫温柔显脸小\n12.6-18.6:卡其半身裙自带高级感" \
    --brand "YIYOU 亿柚" --cta "喜欢这套的私信我~" --end 58.8
```

### 模式2 关键规则（踩坑记录）
- **video 基础轨上，rich-text overlay 文字不渲染**（image 轨能出字）。→ 文字一律用 burn_text.py 本地烧录（ffmpeg drawtext + WenQuanYi 中文字体，中文100%清晰带黑边）。
- **同一轨道 clip 严禁时间重叠**（重叠→轨上后叠 clip 不渲染）。视频段用顺序排列 + 短淡切/滑动转场(`wipeRight/slideLeft/carouselLeft` 等)，**不用 crossfade（非法值）**。
- 转场合法值：`fade fadeSlow fadeFast reveal wipeLeft/Right slideLeft/Right/Up/Down carouselLeft/Right/Up/Down`（无 `crossfade`）。
- 输出比例：源是 16:9 4K → 用 `--ratio 16:9` 保留全画面；要抖音/小红书竖版用 `9:16`（中心裁切）。
- 音频：`--audio keep|duck(0.25)|mute` 控制原片声音；BGM 用官方 `music/unminus|freepd` 悉尼 CDN 曲目，`fadeInFadeOut`。
- duration 映射（--dur {文件名:秒}）用 ffprobe 取，保证时间轴精确。
