#!/usr/bin/env python3
"""
Fashion Video Pipeline — 场景测试框架 v3
支持 TTS + SRT 字幕全链路测试。
"""

import os, sys, json, time, base64, urllib.request, uuid

# 技能目录
SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.join(SKILL_DIR, "scripts")
RESOURCES_DIR = os.path.join(SKILL_DIR, "resources")
sys.path.insert(0, SCRIPTS_DIR)

from volcengine_client import VolcengineClient, encode_image_to_data_url
from ffmpeg_composer import FFmpegComposer


# ===== 测试场景 =====
TEST_CONFIG = {
    "A_front_walk": {
        "name": "A-正面走秀",
        "prompt": (
            "A young elegant Asian woman wearing a light pink fuzzy cardigan with front tie details "
            "and dark olive wide-leg cargo pants. She walks slowly directly toward the camera. "
            "Face front-facing, head stays still, eyes looking at lens. "
            "Professional runway walk. Minimalist white gallery background. "
            "Cinematic, photorealistic, 8K, soft lighting, shallow depth of field."
        ),
        "tts": "漫步秀场，自信优雅。粉色针织开衫搭配橄榄绿阔腿裤，尽显高级质感。",
        "duration": 8,
        "ratio": "9:16",
    },
    "B_street_style": {
        "name": "B-街拍通勤",
        "prompt": (
            "A young elegant Asian woman wearing [garment]. "
            "Walking on a stylish city street with confident stride. "
            "Face front-facing, looking at camera, head stays visible. "
            "Modern urban background, natural sunlight. Photorealistic, 8K."
        ),
        "tts": "都市街拍，从容通勤。本季新品让你在街头也能成为焦点。",
        "duration": 8,
        "ratio": "9:16",
    },
    "C_lifestyle": {
        "name": "C-生活方式",
        "prompt": (
            "A young elegant Asian woman wearing [garment]. "
            "Sitting at a cozy Parisian cafe, holding a coffee cup. "
            "Face front-facing, warm smile towards camera. "
            "Soft sunlight, shallow depth of field, cinematic 8K."
        ),
        "tts": "慵懒午后，一杯咖啡的时间。享受属于你的慢生活。",
        "duration": 8,
        "ratio": "9:16",
    },
    "F_promotional": {
        "name": "F-促销切片",
        "prompt": (
            "A young elegant Asian woman wearing [garment]. "
            "Energetic front-facing pose, directly looking at camera. "
            "High contrast vibrant colors, stage lighting. "
            "Face always visible, confident expression. "
            "Promotional style, bold visual impact."
        ),
        "tts": "限时优惠，低至五折！本季新品，先到先得。",
        "duration": 6,
        "ratio": "9:16",
    },
    "H_brand_film": {
        "name": "H-品牌大片",
        "prompt": (
            "A young elegant Asian woman wearing [garment]. "
            "Walking gracefully through a grand hotel lobby. "
            "Face front-facing, elegant slow motion. "
            "Dramatic cinematic lighting, ray tracing, 8K. "
            "Film grain texture, wide angle. Face always visible."
        ),
        "tts": "每一件衣服，都是你对生活的态度。本季全新系列，致敬每一个从容自信的你。",
        "duration": 10,
        "ratio": "9:16",
    },
}


def run_volcengine_test(config_path, image_path, scenario_key,
                        quality="standard", enable_tts=True, enable_subtitle=True):
    """测试火山引擎生成 + 后期全链路（含 TTS + 字幕）。"""
    scenario = TEST_CONFIG.get(scenario_key)
    if not scenario:
        print(f"⚠️  Unknown scenario: {scenario_key}")
        return None
    
    print(f"\n{'='*60}")
    print(f"🧪 测试场景: {scenario['name']}")
    print(f"   质量档: {quality}")
    print(f"   TTS: {'✅' if enable_tts else '❌'}  字幕: {'✅' if enable_subtitle else '❌'}")
    print(f"{'='*60}")
    
    client = VolcengineClient(config_path)
    composer = FFmpegComposer(config_path)
    
    # 编码图片
    print(f"\n📷 编码图片: {image_path}")
    image_data = encode_image_to_data_url(image_path)
    
    # 替换 Prompt 中的 [garment] 占位
    garment_desc = "a light pink fuzzy cardigan with front tie details and olive wide-leg pants"
    prompt = scenario["prompt"].replace("[garment]", garment_desc)
    
    print(f"\n📝 Prompt: {prompt[:100]}...")
    print(f"   Duration: {scenario['duration']}s")
    
    # ── Step 1: 生成视频 ──
    try:
        task_id = client.submit_video_task(
            prompt=prompt,
            reference_image_url=image_data,
            duration=scenario["duration"],
            ratio=scenario["ratio"],
            quality=quality
        )
    except Exception as e:
        print(f"❌ 提交失败: {e}")
        return None
    
    print(f"\n⏳ 等待生成...")
    video_url = client.wait_for_video(task_id, poll_interval=10, timeout=600)
    
    if not video_url:
        print("❌ 未能获取视频")
        return None
    
    output_dir = os.path.join(os.path.dirname(image_path), "test_output")
    os.makedirs(output_dir, exist_ok=True)
    
    raw_path = os.path.join(output_dir, f"{scenario_key}_{quality}_raw.mp4")
    client.download_video(video_url, raw_path)
    
    # ── Step 2: TTS 配音 ──
    tts_path = None
    tts_text = None
    if enable_tts:
        tts_text = scenario.get("tts", "欢迎查看本季新品。")
        tts_path = os.path.join(output_dir, f"{scenario_key}_{quality}_tts.mp3")
        try:
            client.submit_tts_task(tts_text, tts_path)
        except Exception as e:
            print(f"⚠️  TTS 失败 (可忽略): {e}")
            tts_path = None
            tts_text = None
    
    # ── Step 3: 后期装配 ──
    final_path = os.path.join(output_dir, f"{scenario_key}_{quality}_final.mp4")
    
    # BGM
    bgm_path = os.path.join(RESOURCES_DIR, "bgm", "placeholder.mp3")
    if not os.path.exists(bgm_path):
        bgm_path = None
    
    # 单行字幕（作为 SRT 的补充或降级）
    subtitle_cfg = None
    if enable_subtitle and not tts_path:
        subtitle_cfg = {"text": f"{scenario['name']} | Summer Collection", "font_size": 36}
    
    composer.compose_video(
        input_path=raw_path,
        output_path=final_path,
        logo_cfg={"path": client.config.get("branding", {}).get("logo_path"),
                   "position": "top-right"},
        bgm_path=bgm_path,
        tts_path=tts_path,
        tts_text=tts_text,     # 自动生成 SRT 字幕
        subtitle_cfg=subtitle_cfg,
    )
    
    print(f"\n{'='*60}")
    print(f"✅ 测试完成!")
    print(f"   原始: {raw_path}")
    print(f"   最终: {final_path}")
    if tts_path:
        print(f"   TTS: {tts_path}")
    if enable_tts and tts_text:
        srt_path = final_path + ".srt"
        if os.path.exists(srt_path):
            print(f"   字幕: {srt_path}")
    print(f"{'='*60}")
    
    return {
        "scenario": scenario_key,
        "quality": quality,
        "raw_path": raw_path,
        "final_path": final_path,
        "tts_path": tts_path,
    }


def test_tts_only(client, output_dir, text, voice="zh_female_vv_uranus_bigtts"):
    """仅测试 TTS 功能（不生成视频）。"""
    print(f"\n{'='*60}")
    print("🎤 测试 TTS 语音合成")
    print(f"   文本: {text[:50]}...")
    print(f"   音色: {voice}")
    print(f"{'='*60}")
    
    tts_path = os.path.join(output_dir, f"tts_test_{int(time.time())}.mp3")
    try:
        client.submit_tts_task(text, tts_path, voice=voice)
        print(f"\n✅ TTS 测试通过!")
        print(f"   文件: {tts_path}")
        return tts_path
    except Exception as e:
        print(f"\n❌ TTS 测试失败: {e}")
        return None


def list_tts_voices():
    """列出可用的 TTS 音色。"""
    voices = VolcengineClient.get_tts_voices(None)
    print("\n🎤 可用 TTS 音色 (seed-tts-2.0):")
    print("-" * 50)
    for vid, desc in voices.items():
        print(f"  {vid:45s} → {desc}")
    print("-" * 50)
    print("完整列表请访问: https://console.volcengine.com/speech/new/voices")


if __name__ == "__main__":
    print("🧪 Fashion Video Pipeline — 场景测试框架 v3")
    print("   支持 TTS + SRT 字幕自动对齐")
    print("=" * 60)
    
    if len(sys.argv) < 2:
        print("用法:")
        print("  python3 run_test.py <config_path> <image_path> [场景] [质量] [--no-tts] [--no-sub]")
        print("  python3 run_test.py --tts-only <config_path> <text> [音色]")
        print("  python3 run_test.py --list-voices")
        print("\n场景: A_front_walk, B_street_style, C_lifestyle, F_promotional, H_brand_film")
        print("质量: fast, standard, premium")
        print("音色: zh_female_vv_uranus_bigtts (默认), zh_female_xiaohe_uranus_bigtts, zh_male_m191_uranus_bigtts")
        sys.exit(1)
    
    # TTS 单独测试
    if sys.argv[1] == "--tts-only":
        config_path = sys.argv[2]
        text = sys.argv[3] if len(sys.argv) > 3 else "你好，这是一个测试。"
        voice = sys.argv[4] if len(sys.argv) > 4 else "zh_female_vv_uranus_bigtts"
        
        from volcengine_client import VolcengineClient
        client = VolcengineClient(config_path)
        output_dir = os.path.join(os.path.dirname(config_path), "test_output")
        os.makedirs(output_dir, exist_ok=True)
        test_tts_only(client, output_dir, text, voice)
        sys.exit(0)
    
    # 列出音色
    if sys.argv[1] == "--list-voices":
        list_tts_voices()
        sys.exit(0)
    
    # 全链路测试
    config_path = sys.argv[1]
    image_path = sys.argv[2]
    scenario_key = sys.argv[3] if len(sys.argv) > 3 else "A_front_walk"
    quality = sys.argv[4] if len(sys.argv) > 4 else "standard"
    
    enable_tts = "--no-tts" not in sys.argv
    enable_subtitle = "--no-sub" not in sys.argv
    
    run_volcengine_test(config_path, image_path, scenario_key, quality,
                        enable_tts=enable_tts, enable_subtitle=enable_subtitle)
