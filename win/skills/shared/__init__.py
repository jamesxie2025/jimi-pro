#!/usr/bin/env python3
"""
Shared utilities for video post-production across skills.

Provides:
- FFmpegComposer (Logo/BGM/字幕/TTS/调色/裁切/拼接)
- VideoInfo (视频信息获取)
- SubtitleGenerator (SRT/ASS 字幕生成)
"""

import os
import sys

# 让两个技能目录都能找到脚本
SKILLS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FASHION_DIR = os.path.join(SKILLS_DIR, "fashion-video-pipeline", "scripts")
JIMI_DIR = os.path.join(SKILLS_DIR, "jimi-agent-video", "scripts")

# 优先使用 fashion 目录下的 ffmpeg_composer（功能更全）
if os.path.exists(os.path.join(FASHION_DIR, "ffmpeg_composer.py")):
    sys.path.insert(0, FASHION_DIR)
    from ffmpeg_composer import FFmpegComposer
else:
    raise ImportError("ffmpeg_composer.py not found")

# Symlink: 让 jimi-agent-video 也能 import
for target_dir in [FASHION_DIR, JIMI_DIR]:
    link_path = os.path.join(target_dir, "ffmpeg_composer.py")
    if not os.path.exists(link_path):
        try:
            os.symlink(os.path.join(FASHION_DIR, "ffmpeg_composer.py"), link_path)
        except (OSError, FileExistsError):
            pass

__all__ = ["FFmpegComposer"]
