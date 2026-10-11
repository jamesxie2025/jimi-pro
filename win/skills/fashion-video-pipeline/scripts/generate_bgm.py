#!/usr/bin/env python3
"""
Generate placeholder BGM tracks for testing.
Produces simple ambient tones using ffmpeg.
"""

import subprocess, os

BGM_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "resources", "bgm")
os.makedirs(BGM_DIR, exist_ok=True)

# JIMI-AGENT BGM dir
JIMI_BGM_DIR = os.path.join(
    os.path.dirname(os.path.dirname(__file__)).replace("fashion-video-pipeline", "jimi-agent-video"),
    "resources", "bgm"
)
os.makedirs(JIMI_BGM_DIR, exist_ok=True)

tracks = [
    ("tech_ambient.mp3",      "sine=frequency=220:duration=15",      "0.1", "科技氛围BGM"),
    ("soft_jazz.mp3",         "sine=frequency=330:duration=15",      "0.12", "轻爵士BGM"),
    ("upbeat_pop.mp3",       "sine=frequency=440:duration=15",      "0.15", "动感BGM"),
    ("cinematic_drone.mp3",   "sine=frequency=110:duration=15",      "0.08", "电影感BGM"),
    ("placeholder.mp3",       "sine=frequency=260:duration=10",      "0.1", "占位BGM"),
]

for filename, source, volume, desc in tracks:
    path = os.path.join(BGM_DIR, filename)
    if not os.path.exists(path):
        cmd = [
            "ffmpeg", "-y", "-f", "lavfi", "-i", source,
            "-af", f"volume={volume}",
            "-b:a", "64k", path
        ]
        subprocess.run(cmd, capture_output=True)
        print(f"  ✅ {filename} ({desc})")
    else:
        print(f"  ⏭️  {filename} already exists")

# Copy to JIMI BGM dir
for filename in ["tech_ambient.mp3", "upbeat_pop.mp3"]:
    src = os.path.join(BGM_DIR, filename)
    dst = os.path.join(JIMI_BGM_DIR, filename)
    if os.path.exists(src) and not os.path.exists(dst):
        import shutil
        shutil.copy2(src, dst)
        print(f"  📋 Copied {filename} → jimi-agent-video bgm")

print(f"\n✅ BGM generated in {BGM_DIR}")
