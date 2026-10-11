#!/usr/bin/env python3
"""FFmpeg Composer — 修复版 (v3)

核心改动：
1. 移除所有 setpts 拉伸操作（禁止画面凝固）
2. 支持 Logo/BGM/字幕/TTS 的灵活开关
3. 支持 SRT 字幕文件生成（含时间轴对齐）
4. 支持 TTS 配音 + SRT 字幕自动对齐（根据语速/字数估算时间轴）
5. 支持后期加工模式（输入已完成视频）
6. 中文字体自动检测（WenQuanYi/Noto fallback）
"""

import os
import json
import subprocess
import math
import re

class FFmpegComposer:
    def __init__(self, config_path=None):
        self.config = {}
        self.branding = {}
        if config_path and os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                self.config = json.load(f)
            self.branding = self.config.get('branding', {})
        
        # 自动检测中文字体
        self.font_path = self._detect_font()

    def _detect_font(self):
        """自动检测可用中文字体。"""
        candidates = [
            self.branding.get("font_path", ""),
            "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/opentype/noto/NotoSansSC-Regular.otf",
            "/System/Library/Fonts/PingFang.ttc",
            "C:\\Windows\\Fonts\\msyh.ttc",
        ]
        for path in candidates:
            if path and os.path.exists(path):
                return path
        return None

    def run_command(self, cmd, desc=""):
        """运行 FFmpeg 命令。"""
        label = desc or ' '.join(cmd[:4])
        print(f"  ⚙️  {label}")
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode != 0:
            err = result.stderr.decode('utf-8', errors='replace')[:500]
            print(f"❌ FFmpeg Error: {err}")
            raise Exception(f"FFmpeg failed (code {result.returncode})")
        return True

    def get_video_info(self, video_path):
        """获取视频信息（时长、分辨率、帧率）。"""
        cmd = [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", "-show_streams", video_path
        ]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        info = json.loads(result.stdout)
        
        video_stream = None
        audio_stream = None
        for s in info.get("streams", []):
            if s["codec_type"] == "video" and not video_stream:
                video_stream = s
            if s["codec_type"] == "audio" and not audio_stream:
                audio_stream = s
        
        duration = float(info["format"]["duration"])
        width = int(video_stream["width"]) if video_stream else 720
        height = int(video_stream["height"]) if video_stream else 1280
        fps = video_stream.get("r_frame_rate", "24/1") if video_stream else "24/1"
        has_audio = audio_stream is not None
        
        # 获取音频时长（如果 TTS 等单独音频）
        audio_duration = None
        if audio_stream:
            audio_duration = float(audio_stream.get("duration", duration))
        
        return {
            "duration": duration,
            "width": width,
            "height": height,
            "fps": fps,
            "has_audio": has_audio,
            "video_stream": video_stream,
            "audio_stream": audio_stream,
            "audio_duration": audio_duration,
        }

    def get_audio_info(self, audio_path):
        """获取音频信息（时长等）。
        先尝试 ffprobe 精确获取，失败则按比特率估算。
        """
        cmd = [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", "-show_streams", audio_path
        ]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        info = json.loads(result.stdout) if result.stdout else {}
        
        duration = info.get("format", {}).get("duration")
        if duration:
            return {"duration": float(duration)}
        
        # Fallback: estimate from file size (assume 128kbps MP3)
        size_bytes = os.path.getsize(audio_path)
        estimated = size_bytes * 8 / 128000
        print(f"  ⚠️  ffprobe 无法读取时长，按文件大小估算: {estimated:.1f}s")
        return {"duration": estimated}

    # ─────────────── SRT 字幕生成 ───────────────

    def estimate_tts_segments(self, text, total_duration):
        """
        根据 TTS 音频时长和文本内容，估算每句话的时间轴。
        返回: [(start_sec, end_sec, text), ...]
        """
        if not text:
            return []
        
        # 按标点拆分成句子
        sentences = re.split(r'([。！？.!?\n])', text)
        segments = []
        buffer = ""
        for part in sentences:
            buffer += part
            if part in '。！？.!?\n' and buffer.strip():
                segments.append(buffer.strip())
                buffer = ""
        if buffer.strip():
            segments.append(buffer.strip())
        
        if not segments:
            segments = [text]
        
        # 时间分配：根据字符数按比例分配
        total_chars = sum(len(s) for s in segments)
        if total_chars == 0:
            segments = [text]
            total_chars = len(text)
        
        # 中文语速约 3-4 字/秒，英文约 3-5 词/秒
        # 用字符数占比分配时间
        start_time = 0.0
        result = []
        for seg in segments:
            ratio = len(seg) / total_chars
            seg_duration = ratio * total_duration
            # 最小 0.8 秒，最大不超过总时长
            seg_duration = max(0.8, seg_duration)
            end_time = min(start_time + seg_duration, total_duration)
            result.append((round(start_time, 1), round(end_time, 1), seg))
            start_time = end_time
        
        # 修正最后一个 segment 对齐到总时长
        if result:
            result[-1] = (result[-1][0], round(total_duration, 1), result[-1][2])
        
        return result

    def generate_srt(self, segments, output_path):
        """
        生成 SRT 字幕文件。
        segments: [(start_sec, end_sec, text), ...]
        """
        def sec_to_srt(sec):
            h = int(sec // 3600)
            m = int((sec % 3600) // 60)
            s = int(sec % 60)
            ms = int((sec - int(sec)) * 1000)
            return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
        
        lines = []
        for i, (start, end, text) in enumerate(segments, 1):
            # 清理文本（移除多余空格和换行）
            clean_text = re.sub(r'\s+', ' ', text).strip()
            if not clean_text:
                continue
            # SRT 字幕单行不超过 40 字，太长则分行
            if len(clean_text) > 40:
                mid = len(clean_text) // 2
                # 尽量在空格或标点处换行
                split_pos = clean_text.rfind(' ', 0, mid)
                if split_pos < mid // 2:
                    split_pos = clean_text.find(' ', mid)
                if split_pos > 0 and split_pos < len(clean_text) - 1:
                    line1 = clean_text[:split_pos]
                    line2 = clean_text[split_pos+1:]
                    display_text = f"{line1}\n{line2}"
                else:
                    display_text = clean_text
            else:
                display_text = clean_text
            
            lines.append(f"{i}")
            lines.append(f"{sec_to_srt(start)} --> {sec_to_srt(end)}")
            lines.append(display_text)
            lines.append("")
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write("\n".join(lines))
        
        print(f"  📝 SRT subtitle file generated: {output_path}")
        print(f"     {len(segments)} segments, total {sum(e-s for s,e,_ in segments):.1f}s")
        return output_path

    def process_srt_subtitle(self, srt_path, video_info):
        """
        生成基于 SRT 文件的字幕 overlay filter 字符串。
        """
        if not os.path.exists(srt_path):
            print("  ⚠️  SRT file not found, falling back to simple subtitle")
            return None
        
        font_path = self.font_path or ""
        
        # 使用 subtitles filter (基于 SRT)
        # 注意：subtitles filter 在 -vf 中使用，不是 filter_complex
        # 所以需要单独处理
        return None  # SRT 在 compose 中特殊处理

    # ─────────────── Logo 处理 ───────────────

    def process_logo(self, logo_cfg, video_info):
        """生成 Logo overlay 的 FFmpeg filter 字符串。"""
        logo_path = logo_cfg.get("path", self.branding.get("logo_path"))
        if not logo_path or not os.path.exists(logo_path):
            print("  ⚠️  Logo file not found, skipping")
            return None
        
        pos = logo_cfg.get("position", self.branding.get("logo_position", "top-right"))
        scale = logo_cfg.get("scale", self.branding.get("logo_scale", 150))
        opacity = logo_cfg.get("opacity", self.branding.get("logo_opacity", 0.85))
        
        # 定位
        pos_map = {
            "top-right": f"W-w-{15}:{15}",
            "top-left": f"15:{15}",
            "bottom-right": f"W-w-{15}:H-h-{15}",
            "bottom-left": f"15:H-h-{15}",
            "center-bottom": f"(W-w)/2:H-h-{30}",
        }
        overlay_pos = pos_map.get(pos, "W-w-15:15")
        
        logo_filter = (
            f"[1:v]scale={scale}:-1,format=rgba,"
            f"colorchannelmixer=aa={opacity}[logo];"
            f"[0:v][logo]overlay={overlay_pos}[v_out]"
        )
        return logo_filter

    # ─────────────── 简单字幕（drawtext） ───────────────

    def process_subtitle(self, subtitle_cfg, video_info):
        """生成字幕 overlay 的 FFmpeg filter 字符串（简单单行）。"""
        text = subtitle_cfg.get("text", "")
        if not text:
            return None
        
        font_size = subtitle_cfg.get("font_size", 42)
        style = subtitle_cfg.get("style", "bg-box")
        width = video_info["width"]
        height = video_info["height"]
        font_path = self.font_path or ""
        
        if style == "bg-box":
            subtitle_filter = (
                f"drawtext=text='{text}':"
                f"fontfile={font_path}:"
                f"fontsize={font_size}:"
                f"fontcolor=white:"
                f"box=1:boxcolor=black@0.5:"
                f"boxborderw=10:"
                f"x=(w-text_w)/2:"
                f"y=h-text_h-{max(60, height//20)}"
            )
        else:
            subtitle_filter = (
                f"drawtext=text='{text}':"
                f"fontfile={font_path}:"
                f"fontsize={font_size}:"
                f"fontcolor=white:"
                f"shadowcolor=black@0.6:shadowx=2:shadowy=2:"
                f"x=(w-text_w)/2:"
                f"y=h-text_h-{max(60, height//20)}"
            )
        return subtitle_filter

    # ─────────────── 主合成方法 ───────────────

    def compose_video(self, input_path, output_path,
                      logo_cfg=None, subtitle_cfg=None,
                      bgm_path=None, tts_path=None,
                      srt_path=None, tts_text=None,
                      bgm_volume=0.3, tts_volume=1.0):
        """
        视频后期装配（主线方法）。
        
        参数：
            input_path: 输入视频路径（可含原声）
            output_path: 输出视频路径
            logo_cfg: Logo 配置 dict 或 None
            subtitle_cfg: 字幕配置 dict 或 None（单行固定文字）
            bgm_path: BGM 音频路径或 None
            tts_path: TTS 配音路径或 None
            srt_path: SRT 字幕文件路径（优先于 subtitle_cfg）
            tts_text: TTS 文本（若提供且 srt_path 未提供，则自动生成 SRT）
            bgm_volume: BGM 音量（0.0-1.0）
            tts_volume: TTS 音量（0.0-1.0）
        """
        video_info = self.get_video_info(input_path)
        print(f"  📹 Input: {input_path}")
        print(f"     Size: {video_info['width']}x{video_info['height']}")
        print(f"     Duration: {video_info['duration']:.1f}s")
        print(f"     Audio: {'yes' if video_info['has_audio'] else 'no'}")

        # ── 自动生成 SRT ──
        final_srt_path = srt_path
        if tts_path and os.path.exists(tts_path) and tts_text and not srt_path:
            # 自动根据 TTS 音频时长生成 SRT
            tts_info = self.get_audio_info(tts_path)
            segments = self.estimate_tts_segments(tts_text, tts_info["duration"])
            srt_out = output_path + ".srt"
            self.generate_srt(segments, srt_out)
            final_srt_path = srt_out

        # ── 构建输入文件列表 ──
        inputs = [input_path]
        input_map = ["0:v"]

        # Logo 作为额外输入
        logo_path = (logo_cfg or {}).get("path", self.branding.get("logo_path"))
        if logo_path and os.path.exists(logo_path):
            inputs.append(logo_path)

        # ── 构建 filter 链 ──
        filters = []
        
        logo_filter = self.process_logo(logo_cfg or {}, video_info)
        
        # 组装 filter_complex: 有 Logo 时
        if logo_filter:
            filters.append(logo_filter)
        
        # ── 音频处理 ──
        audio_input_count = len(inputs)
        
        # 收集所有音频源及其音量
        audio_entries = []  # [(input_id, stream_spec, volume, label)]
        
        # 原声
        if video_info["has_audio"]:
            audio_entries.append((0, "a", 0.8 if any(
                [bgm_path and os.path.exists(bgm_path),
                 tts_path and os.path.exists(tts_path)]
            ) else 1.0, "original"))
        
        # BGM
        if bgm_path and os.path.exists(bgm_path):
            bgm_duration = self.get_audio_info(bgm_path)["duration"]
            inputs.append(bgm_path)
            audio_entries.append((audio_input_count, "a", bgm_volume, "bgm"))
            audio_input_count += 1
        
        # TTS
        if tts_path and os.path.exists(tts_path):
            inputs.append(tts_path)
            audio_entries.append((audio_input_count, "a", tts_volume, "tts"))
            audio_input_count += 1

        # ── 组装 FFmpeg 命令 ──
        cmd = ["ffmpeg", "-y"]
        
        # 添加所有输入
        for inp in inputs:
            cmd.extend(["-i", inp])
        
        # 字幕处理方式选择
        use_srt = final_srt_path and os.path.exists(final_srt_path)
        use_drawtext = subtitle_cfg and subtitle_cfg.get("text")
        
        # ── 构建视频 filter ──
        if logo_filter:
            # 有 Logo 时需要对 logo 的输出来叠加字幕
            video_filter_parts = []
            
            # Logo filter 已定义
            if use_srt:
                # SRT 字幕直接用 subtitles filter 叠加在 logo 输出上
                video_filter_parts.append(
                    f"[v_out]subtitles={final_srt_path}"
                    f":fontfile={self.font_path or ''}[v_final]"
                )
            elif use_drawtext:
                simple_filter = self.process_subtitle(subtitle_cfg, video_info)
                if simple_filter:
                    video_filter_parts.append(
                        f"[v_out]{simple_filter}[v_final]"
                    )
                else:
                    video_filter_parts.append("[v_out]null[v_final]")
            else:
                video_filter_parts.append("[v_out]null[v_final]")
            
            filters.extend(video_filter_parts)
            video_out = "[v_final]"
        else:
            # 无 Logo
            if use_srt:
                filters.append(
                    f"[0:v]subtitles={final_srt_path}"
                    f":fontfile={self.font_path or ''}[v_final]"
                )
                video_out = "[v_final]"
            elif use_drawtext:
                simple_filter = self.process_subtitle(subtitle_cfg, video_info)
                if simple_filter:
                    filters.append(f"[0:v]{simple_filter}[v_final]")
                    video_out = "[v_final]"
                else:
                    video_out = "0:v"
            else:
                video_out = "0:v"
        
        # ── 执行 filter_complex ──
        if filters:
            filter_complex_str = ";".join(filters)
            cmd.extend(["-filter_complex", filter_complex_str])
            cmd.extend(["-map", video_out])
        else:
            cmd.extend(["-map", "0:v"])
        
        # ── 音频映射 ──
        if audio_entries:
            if len(audio_entries) == 1:
                idx, stream, vol, label = audio_entries[0]
                cmd.extend(["-map", f"{idx}:{stream}"])
                if vol != 1.0:
                    # 使用 afade/volume filter 调整单路音量
                    cmd.extend(["-af", f"volume={vol}"])
            else:
                # 多路混音
                amix_inputs = []
                vol_filters = []
                
                for idx, stream, vol, label in audio_entries:
                    if vol != 1.0:
                        vol_label = f"[av{idx}]"
                        vol_filters.append(
                            f"[{idx}:{stream}]volume={vol}{vol_label}"
                        )
                        amix_inputs.append(vol_label)
                    else:
                        amix_inputs.append(f"[{idx}:{stream}]")
                
                all_filters = vol_filters[:]
                amix_str = (
                    f"{''.join(amix_inputs)}"
                    f"amix=inputs={len(audio_entries)}:duration=first:dropout_transition=2[aout]"
                )
                all_filters.append(amix_str)
                
                # 合并到现有 filter_complex 或新建
                audio_filter_str = ";".join(all_filters)
                
                if filters:
                    # 追加音频 filter 到现有 filter_complex
                    # 需要合并 video 和 audio filter
                    pass  # 下面会处理
                
                # 简单方案：单独加 -af
                audio_pre_filter = None
                if vol_filters:
                    # 构建复杂 filter，可能需要单独处理
                    # 使用 amix 和 volume
                    full_audio_filter = ";".join(all_filters)
                    cmd.extend(["-filter_complex", full_audio_filter])
                    cmd.extend(["-map", "[aout]"])
                else:
                    # 所有音量都是 1.0，直接 amix
                    amix_str = (
                        f"{''.join(amix_inputs)}"
                        f"amix=inputs={len(audio_entries)}:duration=first:dropout_transition=2[aout]"
                    )
                    cmd.extend(["-filter_complex", amix_str])
                    cmd.extend(["-map", "[aout]"])
        else:
            cmd.extend(["-an"])
        
        # 编码参数
        cmd.extend([
            "-c:v", "libx264", "-preset", "medium", "-crf", "23",
            "-c:a", "aac", "-b:a", "128k",
            output_path
        ])
        
        # ── 执行 ──
        self.run_command(cmd, desc="Composing final video")
        
        # 验证输出
        if os.path.exists(output_path):
            size_mb = os.path.getsize(output_path) / (1024 * 1024)
            print(f"✅ Output: {output_path} ({size_mb:.1f}MB)")
        else:
            print(f"❌ Output file not found!")
            raise Exception("Composition failed")
        
        return output_path

    # ─────────────── 快捷方法 ───────────────

    def quick_logo(self, input_path, output_path, logo_path, position="bottom-right"):
        """快捷方法：仅加 Logo。"""
        logo_cfg = {"path": logo_path, "position": position}
        return self.compose_video(input_path, output_path, logo_cfg=logo_cfg)

    def quick_subtitle(self, input_path, output_path, text, font_size=42):
        """快捷方法：仅加字幕。"""
        subtitle_cfg = {"text": text, "font_size": font_size}
        return self.compose_video(input_path, output_path, subtitle_cfg=subtitle_cfg)

    def compose_with_tts_srt(self, input_path, output_path,
                              tts_path, tts_text,
                              logo_cfg=None, bgm_path=None,
                              bgm_volume=0.3, tts_volume=1.0):
        """
        快捷方法：TTS 配音 + 自动 SRT 字幕 + Logo + BGM。
        一次搞定最常见的工作流。
        """
        return self.compose_video(
            input_path=input_path,
            output_path=output_path,
            logo_cfg=logo_cfg,
            bgm_path=bgm_path,
            tts_path=tts_path,
            tts_text=tts_text,
            bgm_volume=bgm_volume,
            tts_volume=tts_volume,
        )

    # ─────────────── 视频拼接 ───────────────

    def concat_videos(self, video_list, output_path, transition=None):
        """合并多个视频片段。"""
        if len(video_list) == 1:
            cmd = ["ffmpeg", "-y", "-i", video_list[0], "-c", "copy", output_path]
            self.run_command(cmd, desc="Copy single video")
            return output_path
        
        # 用 concat demuxer 直接拼接（最快，无需重编码）
        concat_list = output_path + ".list.txt"
        with open(concat_list, "w") as f:
            for v in video_list:
                f.write(f"file '{os.path.abspath(v)}'\n")
        
        cmd = ["ffmpeg", "-y", "-f", "concat", "-safe", "0",
               "-i", concat_list, "-c", "copy", output_path]
        self.run_command(cmd, desc=f"Concat {len(video_list)} videos (copy)")
        if os.path.exists(concat_list):
            os.remove(concat_list)
        
        return output_path

    def trim_video(self, input_path, output_path, start=0, duration=None,
                   use_minterpolate=False, target_fps=None):
        """裁剪/变速视频（不用 setpts 拉伸）。"""
        cmd = ["ffmpeg", "-y", "-i", input_path]
        
        if use_minterpolate:
            if target_fps:
                cmd.extend(["-filter:v", f"minterpolate=fps={target_fps}:mi_mode=mci"])
        else:
            if start > 0:
                cmd.extend(["-ss", str(start)])
            if duration:
                cmd.extend(["-t", str(duration)])
        
        cmd.extend(["-c:v", "libx264", "-preset", "medium", "-crf", "23",
                    "-c:a", "aac", output_path])
        self.run_command(cmd, desc="Trim video")
        return output_path


if __name__ == "__main__":
    print("FFmpeg Composer v3 (Fixed + SRT Subtitles) — Loaded.")
