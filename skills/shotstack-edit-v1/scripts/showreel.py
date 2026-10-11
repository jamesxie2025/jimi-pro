#!/usr/bin/env python3
"""
Shotstack 品牌展示片(Showreel) 生成器 —— 可复用技能模式2。

把【同一场景/产品】的多段视频片段，合成为一支有节奏的展示片：
  开场标题卡 → 各片段按序(Ken Burns 动效 + 重叠交叉溶解转场) → 结尾品牌卡
  + 保留原片现场音(压电平) + BGM 氛围乐 + TTS 中文旁白 + 底部字幕/卖点标签

与模式1(Excel 批量)互补：模式1 按素材表批量产单产品短视频；模式2 把多段视频剪成一支合集。

用法:
  python3 showreel.py --map /tmp/vt_map.json --dur durations.json --out json/showreel.json \
      --title "深蓝针织开衫 · 卡其半身裙" --brand "YIYOU 亿柚" \
      --cta "私信解锁更多同款" --bgm palmtrees --ratio 9:16 --audio duck
  python3 render.py --json json/ --out videos/ --poll --only showreel

参数:
  --map       ingest 后的 {文件名: sourceURL} JSON
  --dur       {文件名: 时长秒} JSON（用于精确时间轴；缺则用 --default-step）
  --out       输出 JSON 路径
  --title     开场标题(空则用品牌)
  --subtitle  开场副标题
  --brand     品牌名(结尾卡)
  --cta       结尾行动号召
  --captions  逗号分隔, 主体段底部字幕
  --bgm       背景乐: palmtrees|lit|fireworks|advertising
  --ratio     成片比例: 16:9 | 9:16 | 1:1
  --audio     原片声音: keep|duck(0.25)|mute
  --vol       BGM 音量 0-1
  --dissolve  重叠交叉溶解秒数(默认0.6, 转场不黑屏)
  --seg-len   每段统一时长(默认用原长)
  --default-step  缺时长时的默认步进
  --tts       TTS 旁白文案
"""
import argparse, json, os, sys

RENDER = "https://api.shotstack.io/edit/v1"
FONT = "NotoSansSC-Regular"
FONT_URL = "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/fonts/NotoSansSC-Regular.otf"
BGM = {
    "palmtrees": "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/music/unminus/palmtrees.mp3",
    "lit": "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/music/unminus/lit.mp3",
    "fireworks": "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/music/freepd/fireworks.mp3",
    "advertising": "https://shotstack-assets.s3-ap-southeast-2.amazonaws.com/music/freepd/advertising.mp3",
}
ACCENT = "#FABC3C"
RATIOS = {"16:9": (1920, 1080), "9:16": (1080, 1920), "1:1": (1080, 1080)}
AUDIO_VOL = {"keep": 1.0, "duck": 0.25, "mute": 0.0}


def size_fmt(ratio):
    w, h = RATIOS[ratio]
    return {"format": "mp4", "size": {"width": w, "height": h}}


def video_clip(src, start, length, volume, effect, transition=None):
    c = {
        "asset": {"type": "video", "src": src, "volume": volume},
        "start": round(start, 3),
        "length": round(length, 3),
        "fit": "crop",
        "position": "center",
        "effect": effect,
    }
    if transition:
        c["transition"] = transition
    return c


def text_clip(text, start, length, size, color, y="bottom", preset="fadeIn", dur=0.7):
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
        "width": 1500,
        "height": 300,
    }


def build(assets, durations, args):
    files = list(assets.keys())
    if args.order:
        files = [f.strip() for f in args.order.split(",") if f.strip() in assets]
    if not files:
        files = sorted(assets.keys())
    if not files:
        print("!! 无视频素材", file=sys.stderr)
        return None

    title_len, end_len = 3.0, 3.5
    DISSOLVE = args.dissolve
    videos, overlays = [], []
    t = title_len
    kb = ["zoomIn", "zoomOut", "zoomInSlow", "zoomOutSlow"]
    captions = args.captions or []
    dur_map = durations or {}

    # 1) 开场标题卡
    tt = args.title or args.brand
    videos.append(video_clip(assets[files[0]], 0, title_len, 0, "zoomIn"))
    overlays.append(text_clip(tt, 0, title_len, 62, "#FFFFFF", y="middle", preset="fadeIn"))
    if args.subtitle:
        overlays.append(text_clip(args.subtitle, 0.6, title_len - 0.8, 32, ACCENT,
                                  y="bottom", preset="fadeIn"))

    # 2) 主体片段：顺序(不重叠) + Ken Burns + 快速淡切(不黑屏) + 底部字幕
    # 注意: clip 一律不重叠(重叠会使同一画面轨道上的文字轨文字消失, 已实测)
    n = len(files)
    for i, fn in enumerate(files):
        dur = args.seg_len if args.seg_len else dur_map.get(fn)
        if not dur:
            dur = args.default_step
        clip = {
            "asset": {"type": "video", "src": assets[fn], "volume": AUDIO_VOL[args.audio]},
            "start": round(t, 3),
            "length": round(dur, 3),
            "fit": "crop",
            "position": "center",
            "effect": kb[i % len(kb)],
            "transition": {"in": ["fade", "wipeLeft", "slideLeft", "carouselLeft"][i % 4],
                            "out": ["fade", "wipeRight", "slideRight", "carouselRight"][i % 4]},
        }
        videos.append(clip)
        if i < len(captions) and captions[i]:
            overlays.append(text_clip(captions[i], t + 0.3, max(1.0, dur - 0.6),
                                      34, ACCENT, y="bottom"))
        t = t + dur

    # 3) 结尾品牌卡
    end_start = t
    videos.append(video_clip(assets[files[-1]], end_start, end_len, 0, "zoomOutSlow"))
    overlays.append(text_clip(args.brand, end_start + 0.4, end_len - 0.6, 58, "#FFFFFF",
                              y="middle", preset="typewriter"))
    if args.cta:
        overlays.append(text_clip(args.cta, end_start + 1.6, end_len - 1.8, 32, ACCENT,
                                  y="bottom", preset="fadeIn"))
    total = end_start + end_len

    tts_text = args.tts or ("".join([
        (args.title + "。") if args.title else "",
        "九组镜头，全方位呈现这件单品的质感与上身效果。",
        (args.cta + "。") if args.cta else "",
    ]))
    tts_clip = {"asset": {"type": "text-to-speech", "text": tts_text, "voice": "Zhiyu",
                          "language": "cmn-CN"}, "start": 0, "length": "auto"}

    timeline = {
        "background": "#0E1626",
        "fonts": [{"src": FONT_URL}],
        "soundtrack": {"src": BGM[args.bgm], "effect": "fadeInFadeOut", "volume": args.vol},
        "tracks": [
            {"clips": videos},
            {"clips": overlays},
            {"clips": [tts_clip]},
        ],
    }
    return {"timeline": timeline, "output": size_fmt(args.ratio)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", required=True)
    ap.add_argument("--dur", default="", help="{文件名:时长秒} JSON")
    ap.add_argument("--out", default="json/showreel.json")
    ap.add_argument("--order", default="")
    ap.add_argument("--title", default="")
    ap.add_argument("--subtitle", default="")
    ap.add_argument("--brand", default="YIYOU 亿柚")
    ap.add_argument("--cta", default="")
    ap.add_argument("--captions", default="")
    ap.add_argument("--bgm", default="palmtrees", choices=list(BGM.keys()))
    ap.add_argument("--ratio", default="9:16", choices=list(RATIOS.keys()))
    ap.add_argument("--audio", default="duck", choices=["keep", "duck", "mute"])
    ap.add_argument("--vol", type=float, default=0.5)
    ap.add_argument("--dissolve", type=float, default=0.6)
    ap.add_argument("--seg-len", type=float, default=None)
    ap.add_argument("--default-step", type=float, default=5.2)
    ap.add_argument("--tts", default="")
    args = ap.parse_args()

    assets = json.load(open(args.map))
    durations = json.load(open(args.dur)) if args.dur else None
    edit = build(assets, durations, args)
    if not edit:
        sys.exit(1)
    d = os.path.dirname(args.out) or "."
    os.makedirs(d, exist_ok=True)
    with open(args.out, "w") as fh:
        json.dump(edit, fh, ensure_ascii=False, indent=2)
    print(f"[showreel] 写入 {args.out}, 比例 {args.ratio}, clips={len(assets)}")


if __name__ == "__main__":
    main()
