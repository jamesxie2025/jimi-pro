---
name: jimi-premiere-bridge
description: Use when an agent needs to assemble commercial-grade video timelines for Adobe Premiere Pro from Dreamina (即梦) AI clips, real footage, voiceover, and background music with smart auto-ducking.
---

# Jimi Premiere Bridge Skill

Use this skill when you need to assemble commercial-grade, multi-track video editing projects for Adobe Premiere Pro (or DaVinci Resolve) from Dreamina (即梦) AI clips, real footage, voiceovers, and background music.

## Architecture

```text
[OpenClaw Agent] --(JSON Recipe)--> [Jimi Bridge Service :9099] --> [FCP XML Project] --> [Premiere Pro]
```

## How to Call from inside Docker Container (jimi-agent-pro)

Endpoint: `http://host.docker.internal:9099/api/compile`
Method: `POST`
Header: `Content-Type: application/json`

### JSON Recipe Payload

```json
{
  "title": "项目名称_商用短视频",
  "width": 1920,
  "height": 1080,
  "fps": 25,
  "scenes": [
    {
      "file": "/host/Downloads/jimi_demo_clips/part_01.mp4",
      "duration": 4.5,
      "motion": "zoom_in",
      "title": "分镜1：战略启动"
    },
    {
      "file": "/host/Downloads/jimi_demo_clips/part_02.mp4",
      "duration": 4.0,
      "motion": "zoom_out",
      "title": "分镜2：数据穿透"
    }
  ],
  "voiceover": {
    "file": "/host/Downloads/voice.mp3",
    "start_time": 0.5
  },
  "bgm": {
    "file": "/host/Downloads/12461663-the-last-tick-12345.mp3",
    "auto_duck": true,
    "volume_base": 0.55,
    "volume_duck": 0.15
  }
}
```

### Features
1. **FCP XML (xmeml v5)**: Standard exchange file, opened in Premiere Pro via File -> Import.
2. **Motion Keyframes (Ken Burns / Slow Zoom)**: Eliminates AI stiffness (`zoom_in` scales 100% -> 112%).
3. **Smart Auto-Ducking**: BGM automatically drops to -18dB when voiceover is speaking and returns to -6dB during silence.
4. **Path Translation**: Supports `/host/...` paths from Docker mapped seamlessly to macOS host `/Users/xwxie/...`.

### Launching on Host
The output XML is saved in:
`/Users/xwxie/Public/jimi-pro/jimi-bridge/output/<title>.xml`
In Premiere Pro, select **File -> Import** to open the timeline instantly.
