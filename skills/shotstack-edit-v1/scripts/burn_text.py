#!/usr/bin/env python3
"""
Shotstack 展示片『本地字幕烧录』—— 技能模式2 的第二步。

背景：Shotstack 渲染含"video 基础轨"的成片时，rich-text 叠加字幕偶发不渲染（已实测：
image 轨能出字，video 轨时 overlay 文字被丢弃）。为**保证文字必现**，改为：
  ① Shotstack 出无字版本（镜头/转场/音乐/原声/TTS 都在）
  ② 本脚本用 ffmpeg + 中文字体(WenQuanYi)把 开场标题/分段字幕/结尾品牌 精确烧录上去

依赖：系统已装 WenQuanYi Micro Hei（/usr/share/fonts/truetype/wqy/wqy-microhei.ttc）。

用法:
  python3 burn_text.py --in out/showreel_raw.mp4 --out out/showreel.mp4 \
      --title "深蓝针织开衫 · 卡其半身裙" \
      --times "0-3:深蓝针织开衫\n3-9:V领开衫温柔显脸小\n9-15:卡其半身裙自带高级感" \
      --brand "YIYOU 亿柚" --cta "喜欢这套的私信我~" --end 58.8
  # 每行 --times 格式:  开始秒-结束秒:文案

烧录顺序: 开场标题(0-3s 居中) → 分段字幕(底部) → 结尾品牌卡(末3.5s)+CTA。
"""
import argparse, os, subprocess, sys

FONT = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"


def esc(s):
    # ffmpeg drawtext 转义: : ' \ 等
    return s.replace("\\", "\\\\").replace(":", "\\:").replace("'", "\\'")


def parse_times(s):
    """'0-3:文案\n3-9:文案' -> [(start,end,text), ...]"""
    out = []
    for line in s.splitlines():
        line = line.strip()
        if not line:
            continue
        if ":" in line:
            span, txt = line.split(":", 1)
            a, b = span.split("-")
            out.append((float(a), float(b), txt.strip()))
    return out


def build_filter(title, times, brand, cta, end, h):
    """构造 ffmpeg -vf 的 drawtext 链（含 enable 时间段、淡入淡出 alpha）。"""
    WQY = FONT
    filters = []
    # 开场标题(居中)
    if title:
        filters.append(
            f"drawtext=fontfile={WQY}:text='{esc(title)}':fontsize=68:fontcolor=white:"
            f"borderw=4:bordercolor=black:x=(w-text_w)/2:y=(h-text_h)/2-40:"
            f"alpha='if(lt(t,1),t/1,if(lt(t,3.0),(3.0-t)/0.4,0))'"
        )
    # 分段字幕(底部)
    for i, (a, b, txt) in enumerate(times):
        # 安全留给淡入淡出
        ae, bi = max(a, 0.1), max(b, a + 1.4)
        ffade = f"if(lt(t,{ae}),0,if(lt(t,{ae}+0.4),(t-{ae})/0.4,if(lt(t,{bi}-0.4),1,({bi}-t)/0.4)))"
        filters.append(
            f"drawtext=fontfile={WQY}:text='{esc(txt)}':fontsize=40:fontcolor=white:"
            f"borderw=3:bordercolor=black:x=(w-text_w)/2:y=h-160:alpha='{ffade}'"
        )
    # 结尾品牌卡
    if brand:
        bs = end - 3.5
        bf = f"if(lt(t,{bs}),0,if(lt(t,{bs}+0.6),(t-{bs})/0.6,1))"
        filters.append(
            f"drawtext=fontfile={WQY}:text='{esc(brand)}':fontsize=64:fontcolor=white:"
            f"borderw=4:bordercolor=black:x=(w-text_w)/2:y=(h-text_h)/2-60:alpha='{bf}'"
        )
    if cta:
        cs = end - 1.9
        cf = f"if(lt(t,{cs}),0,if(lt(t,{cs}+0.5),(t-{cs})/0.5,1))"
        filters.append(
            f"drawtext=fontfile={WQY}:text='{esc(cta)}':fontsize=38:fontcolor=white:"
            f"borderw=3:bordercolor=black:x=(w-text_w)/2:y=h-220:alpha='{cf}'"
        )
    return ",".join(filters)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", dest="dst", required=True)
    ap.add_argument("--title", default="")
    ap.add_argument("--times", default="")
    ap.add_argument("--brand", default="")
    ap.add_argument("--cta", default="")
    ap.add_argument("--end", type=float, default=0)
    args = ap.parse_args()

    if not args.end:
        r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                            "-of", "csv=p=0", args.src], capture_output=True, text=True)
        args.end = float(r.stdout.strip())

    times = parse_times(args.times)
    vf = build_filter(args.title, times, args.brand, args.cta, args.end, 1080)
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", args.src,
           "-vf", vf, "-c:v", "libx264", "-preset", "medium", "-crf", "20",
           "-c:a", "copy", args.dst]
    print("运行:", " ".join(cmd[:12]), "...")
    subprocess.run(cmd, check=True)
    print(f"[burn] 完成 -> {args.dst}")


if __name__ == "__main__":
    main()
