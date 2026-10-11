#!/usr/bin/env python3
"""
从「亿柚服饰_视频素材录入表.xlsx」+ 上传素材映射(upload_map.json) 生成每条产品的 Shotstack render JSON。

V2 定稿（2026-08-18，已用视觉模型 + 实地渲染逐步验证）：
  ✅ 中文乱码(带叉豆腐块)  → 官方简体中文字体 NotoSansSC-Regular.otf（实测彻底修复，简体全覆盖）
  ✅ 尾部黄色大方块突兀    → 去掉实色 banner 大卡，金黄色只做文字/品牌点缀
  ✅ 转场黑屏              → 图片顺序排放+过渡淡切(短duration)+kenburns动效；绝不用重叠溶解
  ✅ 文字必现              → rich-text 用 V1 已验证安全结构(简单font+align+fadeIn/typewriter+width/height)
  ✅ 文字不重叠            → 【关键】同一轨道内 clip 绝不允许时间重叠，否则后叠 clip 不渲染（实测图片重叠→整条文字轨消失；文字重叠→上方字消失）

rich-text 排雷（实地验证，务必遵守）：
  - 用简体 SC 字体 family="NotoSansSC-Regular"（不是 NotoSansTC，简体缺字→乱码）
  - 同一轨道内 clip 时间严禁重叠（重叠会导致覆盖的 clip 不渲染）→ 每条轨道只放同时间段互不重叠的 clip
  - text clip 不要加 clip.position / asset.shadow / asset.style / font.weight / 富文本<span>（会导致整段不渲染或显示代码）
  - 文字动画 preset 只用 fadeIn / typewriter（方向动画 slideIn/slideUp 易把文字推出屏幕）
  - align.vertical 只接受 top|middle|bottom（无 center）
  - 图片动效 effect 用 Ken Burns(zoomIn/zoomOut/zoomInSlow/zoomOutSlow) → 平滑无黑屏

用法:
  python3 build_json.py --xlsx 亿柚服饰_视频素材录入表.xlsx --uploads upload_map.json --out json/
  python3 build_json.py --xlsx ... --uploads upload_map.json --out json/ --products B6M3769,H3Y3676
"""
import argparse, json, os, sys

import openpyxl

# ---------- 可调模板参数 ----------
OUT_W, OUT_H = 1080, 1440          # 3:4 竖版
BG = "#0E1626"                      # 深墨蓝底（非纯黑，避免黑屏感）
ACCENT = "#FABC3C"                  # 主强调色（暖金，仅点缀文字/品牌）
BRAND = "YIYOU 亿柚"               # 品牌名

# ✅ 官方简体中文字体（Shotstack 悉尼 CDN，实测修复中文乱码）
FONT = "NotoSansSC-Regular"
FONT_URL = "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/fonts/NotoSansSC-Regular.otf"

# ✅ BGM：全部用 Shotstack 官方 s3-ap-southeast-2 音乐库(农场必可拉)
BGMS = [
    "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/music/unminus/palmtrees.mp3",
    "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/music/freepd/fireworks.mp3",
    "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/music/freepd/advertising.mp3",
    "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/music/unminus/lit.mp3",
]
VOICE = "Zhiyu"

# ✅ 文字可读性 scrim 渐变蒙版(独立轨道, 白字在亮背景上也能看清)
OVERLAY_BOTTOM = "https://shotstack-ingest-api-v1-sources.s3.ap-southeast-2.amazonaws.com/bg0x0876rv/zzz01m0a-ajwy3-g442r-v4b10-94jce8/source.png"
OVERLAY_TOP = "https://shotstack-ingest-api-v1-sources.s3.ap-southeast-2.amazonaws.com/bg0x0876rv/zzz01m0a-ak48r-afy71-8xpx8-kkk4r6/source.png"                     # 中文普通话女声
LANG = "cmn-CN"
IMG_LEN = 2.6                       # 每张中间图时长
HOOK_LEN = 3.2                      # 开场钩子时长
END_LEN = 3.8                       # 结尾卡时长
TRANSITION = {"in": "fade", "out": "fade"}   # 短过渡，避免黑屏感
KENBURNS = ["zoomIn", "zoomOut", "zoomInSlow", "zoomOutSlow"]
IMG_EXT = (".jpg", ".jpeg", ".png", ".webp")
VID_EXT = (".mp4", ".mov", ".m4v", ".webm")


def size_fmt():
    return {"format": "mp4", "size": {"width": OUT_W, "height": OUT_H}}


def image_clip(src, start, length, effect="zoomIn", transition=True):
    c = {
        "asset": {"type": "image", "src": src},
        "start": round(start, 3),
        "length": round(length, 3),
        "fit": "crop",
        "position": "center",
        "effect": effect,
    }
    if transition:
        c["transition"] = TRANSITION
    return c


def video_clip(src, start, length):
    return {
        "asset": {"type": "video", "src": src, "volume": 0.0},
        "start": round(start, 3),
        "length": round(length, 3),
        "fit": "crop",
        "position": "center",
        "transition": TRANSITION,
    }


def text_clip(text, start, length, size=52, color="#FFFFFF", y="bottom", preset="fadeIn", dur=0.7):
    """中文 rich-text 字卡（V1 已验证安全结构；无 shadow/style/weight/富文本；时间不重叠）。"""
    return {
        "asset": {
            "type": "rich-text",
            "text": text,
            "font": {"family": FONT, "size": size, "color": color},
            "animation": {"preset": preset, "duration": dur},
            "align": {"horizontal": "center", "vertical": y},
        },
        "start": round(start, 3),
        "length": round(length, 3),
        "width": int(OUT_W * 0.9),
        "height": int(OUT_H * 0.12),
    }


def build_one(row, assets):
    """返回 edit(dict)。保证同一轨道 clip 时间不重叠。"""
    name = str(row.get("产品名称", "") or "新品")
    hk = str(row.get("片头钩子文案", "") or "")
    points = [str(row.get(f"核心卖点{i}", "") or "") for i in (1, 2, 3)]
    points = [p for p in points if p]
    title = str(row.get("爆款标题", "") or name)
    poster = str(row.get("封面文字", "") or "")
    cta = str(row.get("引流话术(结尾)", "") or "")

    vids = sorted((k, v) for k, v in assets.items() if k.lower().endswith(VID_EXT))
    imgs = sorted((k, v) for k, v in assets.items() if k.lower().endswith(IMG_EXT))
    if not imgs and not vids:
        print(f"  !! {name}: 无素材", file=sys.stderr)
        return None
    ordered = vids + imgs

    # ---- 轨道：图片 / 顶部字 / 底部字 / 结尾字 / tts(独立) ----
    track_img, track_top, track_bottom, track_end = [], [], [], []

    # 1) 钩子开场
    fn0, src0 = ordered[0]
    if fn0.lower().endswith(VID_EXT):
        track_img.append(video_clip(src0, 0, HOOK_LEN))
    else:
        track_img.append(image_clip(src0, 0, HOOK_LEN, "zoomIn"))
    head = poster or hk or ""
    if head:
        track_top.append(text_clip(head, 0, HOOK_LEN, size=56, color="#FFFFFF", y="middle", preset="fadeIn"))
    track_bottom.append(text_clip(BRAND, 0, HOOK_LEN, size=38, color=ACCENT, y="bottom", preset="fadeIn"))

    # 2) 中间顺序图 + 底部卖点
    t = HOOK_LEN
    kb = 0
    rest = ordered[1:]
    n_points = len(points) or 1
    for i, (fn, src) in enumerate(rest):
        if fn.lower().endswith(VID_EXT):
            track_img.append(video_clip(src, t, IMG_LEN))
        else:
            track_img.append(image_clip(src, t, IMG_LEN, KENBURNS[kb % len(KENBURNS)]))
            kb += 1
        if points:
            b = text_clip("✦ " + points[i % n_points], t + 0.4, IMG_LEN - 0.4,
                          size=42, color=ACCENT, y="bottom", preset="fadeIn")
            track_bottom.append(b)
        t += IMG_LEN

    # 3) 结尾卡：主图 + 爆款标题 + CTA + 品牌
    end_start = t
    if imgs:
        track_img.append(image_clip(imgs[0][1], end_start, END_LEN, "zoomOutSlow"))
    else:
        track_img.append(video_clip(ordered[-1][1], end_start, END_LEN))
    # 结尾字在单独轨道(track_end)，内部时间不重叠(分段：标题→CTA→品牌)
    track_end.append(text_clip(title, end_start + 0.2, 1.8, size=52, color="#FFFFFF",
                               y="middle", preset="typewriter"))
    if cta:
        track_end.append(text_clip(cta, end_start + 2.0, 1.2, size=36, color=ACCENT,
                                   y="bottom", preset="fadeIn"))
    track_end.append(text_clip(BRAND, end_start + 3.2, 0.6, size=34, color=ACCENT,
                               y="bottom", preset="fadeIn"))
    total = end_start + END_LEN

    # 4) 配音
    parts = []
    if hk:
        parts.append(hk)
    parts.append("这件" + (name if name else "新款"))
    if points:
        parts.append("，" + "，".join(points[:2]))
    if cta:
        parts.append("。" + cta)
    tts_text = "".join(parts) or name
    tts_clip = {"asset": {"type": "text-to-speech", "text": tts_text, "voice": VOICE, "language": LANG},
                "start": 0, "length": "auto"}

    sku = str(row.get("产品编号", "") or "")
    bgm = BGMS[abs(hash(sku)) % len(BGMS)]

    # 5) 文字可读性 scrim：底部渐变蒙片覆盖全片(独立track)，钩子期加顶部渐变
    overlay_bottom = [{
        "asset": {"type": "image", "src": OVERLAY_BOTTOM},
        "start": 0, "length": total, "fit": "crop", "position": "center",
    }]
    overlay_top = [{
        "asset": {"type": "image", "src": OVERLAY_TOP},
        "start": 0, "length": HOOK_LEN, "fit": "crop", "position": "center",
    }]

    timeline = {
        "background": BG,
        "fonts": [{"src": FONT_URL}],
        "soundtrack": {"src": bgm, "effect": "fadeInFadeOut", "volume": 0.55},
        "tracks": [{"clips": track_img}, {"clips": overlay_top}, {"clips": track_top},
                   {"clips": overlay_bottom}, {"clips": track_bottom},
                   {"clips": track_end}, {"clips": [tts_clip]}],
    }
    return {"timeline": timeline, "output": size_fmt()}


def load_rows(xlsx):
    wb = openpyxl.load_workbook(xlsx, data_only=True)
    ws = wb["视频素材录入表"]
    header = None
    rows = []
    header_clean = []
    for i, row in enumerate(ws.iter_rows(values_only=True)):
        if i == 2:
            header_clean = [str(h).split("[")[0].strip() for h in row]
            continue
        if i < 3 or not header_clean:
            continue
        vals = list(row)
        d = {header_clean[c]: vals[c] for c in range(min(len(vals), len(header_clean)))}
        if str(d.get("产品编号") or "").strip():
            rows.append(d)
    return rows, header_clean


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--xlsx", required=True)
    ap.add_argument("--uploads", required=True)
    ap.add_argument("--out", default="json")
    ap.add_argument("--products")
    args = ap.parse_args()

    with open(args.uploads) as fh:
        upload_map = json.load(fh)
    rows, header = load_rows(args.xlsx)
    print(f"[rows] {len(rows)} 条有效产品")
    os.makedirs(args.out, exist_ok=True)

    only = set(x.strip() for x in args.products.split(",")) if args.products else None
    made = []
    for row in rows:
        sku = str(row.get("产品编号", "") or "").strip()
        if only and sku not in only:
            continue
        assets = upload_map.get(sku, {})
        if not assets:
            for folder, m in upload_map.items():
                if sku in folder:
                    assets.update(m)
        if not assets:
            print(f"  !! {sku} {row.get('产品名称')}: 无素材", file=sys.stderr)
            continue
        edit = build_one(row, assets)
        if not edit:
            continue
        with open(os.path.join(args.out, f"{sku}.json"), "w") as fh:
            json.dump(edit, fh, ensure_ascii=False, indent=2)
        made.append(sku)
        print(f"  + {sku} {row.get('产品名称')}")
    print(f"[done] {len(made)} 条 JSON -> {args.out}")


if __name__ == "__main__":
    main()
