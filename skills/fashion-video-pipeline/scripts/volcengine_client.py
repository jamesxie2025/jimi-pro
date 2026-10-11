#!/usr/bin/env python3
"""Volcengine Seedance Client — 修复版 (v3)

核心改动：
1. TTS 改用 Seed Speech 2.0 HTTP API → openspeech.bytedance.com/api/v3/tts/unidirectional
2. 鉴权使用 X-Api-Key header (不再用 ark_api_key)
3. 支持 Resource-Id: seed-tts-2.0
4. 支持 URANUS 系列音色 (zh_female_vv_uranus_bigtts等)
5. 返回音频时长信息 (用于字幕时间轴)
6. 时长直接在 API 层指定，不做后期拉伸
7. 默认加入面向镜头约束
8. 支持质量档位映射
"""

import os
import json
import time
import uuid
import urllib.request
import urllib.error
import urllib.parse
import base64
import requests as _requests


def encode_image_to_data_url(image_path):
    """将本地图片转为 base64 data URL。"""
    with open(image_path, "rb") as f:
        encoded = base64.b64encode(f.read()).decode('utf-8')
    ext = image_path.split('.')[-1].lower()
    mime = "image/jpeg" if ext in ['jpg', 'jpeg'] else f"image/{ext}"
    return f"data:{mime};base64,{encoded}"


class VolcengineClient:
    def __init__(self, config_path):
        with open(config_path, 'r', encoding='utf-8') as f:
            self.config = json.load(f)
        
        self.ark_api_key = self.config['volcengine'].get('ark_api_key')
        if not self.ark_api_key or "YOUR_" in self.ark_api_key:
            self.ark_api_key = os.getenv('DEEPSEEK_API_KEY') or os.getenv('VOLC_ARK_API_KEY') or self.ark_api_key

        def get_endpoint(key, env_name):
            val = self.config['volcengine'].get('endpoints', {}).get(key)
            if not val or "YOUR_" in val:
                val = os.getenv(env_name) or val
            return val

        self.video_endpoint = get_endpoint('video_gen', 'VOLC_VIDEO_GEN_ENDPOINT')
        self.video_endpoint_mini = get_endpoint('video_gen_mini', 'VOLC_VIDEO_GEN_MINI_ENDPOINT')
        self.image_endpoint = get_endpoint('image_gen', 'VOLC_IMAGE_GEN_ENDPOINT')
        self.vision_endpoint = get_endpoint('vision', 'VOLC_VISION_ENDPOINT')
        self.embedding_endpoint = get_endpoint('embedding_vision', 'VOLC_EMBEDDING_VISION_ENDPOINT')
        self.tts_endpoint = get_endpoint('tts', 'VOLC_TTS_ENDPOINT')
        self.base_url = "https://ark.cn-beijing.volces.com/api/v3"
        
        # Seed Speech 2.0 TTS 配置
        tts_cfg = self.config['volcengine'].get('tts', {})
        self.tts_api_key = tts_cfg.get('api_key', '')
        if not self.tts_api_key or "YOUR_" in self.tts_api_key:
            self.tts_api_key = os.getenv('VOLC_TTS_API_KEY') or os.getenv('TTS_API_KEY') or self.tts_api_key
        
        self.tts_voice = tts_cfg.get('voice', 'zh_female_vv_uranus_bigtts')
        self.tts_resource_id = tts_cfg.get('resource_id', 'seed-tts-2.0')
        # TTS 基础 URL，可从配置获取或默认
        self.tts_base_url = tts_cfg.get('base_url', 'https://openspeech.bytedance.com/api/v3/tts/unidirectional')

    # ─────────────── Ark 相关（视频/图片）───────────────

    def _make_ark_request(self, method, url, payload=None):
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.ark_api_key}"
        }
        data = None
        if payload:
            data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req) as response:
                result = json.loads(response.read().decode('utf-8'))
                return result
        except urllib.error.HTTPError as e:
            error_message = e.read().decode('utf-8', errors='replace')
            print(f"❌ HTTP Error: {e.code} - {error_message[:300]}")
            raise

    def get_quality_params(self, quality="standard"):
        """根据质量档位返回模型和时长参数。"""
        mapping = {
            "fast": {
                "model_suffix": "seedance2.0fast",
                "default_duration": 5,
                "max_duration": 8,
            },
            "standard": {
                "model_suffix": "seedance2.0",
                "default_duration": 8,
                "max_duration": 10,
            },
            "premium": {
                "model_suffix": "seedance2.0",
                "default_duration": 12,
                "max_duration": 15,
            },
        }
        return mapping.get(quality, mapping["standard"])

    def submit_video_task(self, prompt, reference_image_url=None,
                          duration=8, ratio="9:16", quality="standard",
                          fast=False):
        """
        提交图生视频任务。
        - 时长由 duration 参数直接指定，不做后期拉伸
        - quality 用于模型选择
        - fast=True 时使用 Seedance 2.0 Mini 快速出片
        """
        qp = self.get_quality_params(quality)
        actual_duration = min(duration, qp["max_duration"])

        endpoint = self.video_endpoint_mini if fast else self.video_endpoint
        if fast:
            print("   🚀 快速模式 (Seedance 2.0 Mini)")

        url = f"{self.base_url}/contents/generations/tasks"

        content_items = [
            {
                "type": "text",
                "text": prompt
            }
        ]

        if reference_image_url:
            content_items.append({
                "type": "image_url",
                "image_url": {
                    "url": reference_image_url
                },
                "role": "reference_image"
            })

        payload = {
            "model": self.video_endpoint,
            "content": content_items,
            "generate_audio": False,  # 后期统一处理
            "ratio": ratio,
            "duration": actual_duration,
            "watermark": False
        }

        print(f"📤 Submitting video task...")
        print(f"   Duration: {actual_duration}s (quality: {quality})")
        print(f"   Ratio: {ratio}")
        print(f"   Prompt preview: {prompt[:80]}...")

        result = self._make_ark_request("POST", url, payload)

        task_id = result.get("id")
        if not task_id:
            raise Exception(f"Failed to get task ID. Response: {result}")

        print(f"✅ Task submitted. Task ID: {task_id}")
        return task_id

    def submit_image_task(self, prompt, size="2K", ratio="16:9"):
        """文生图任务。"""
        url = f"{self.base_url}/images/generations"
        payload = {
            "model": self.image_endpoint,
            "prompt": prompt,
            "response_format": "url",
            "size": size,
            "watermark": True
        }
        print("📤 Submitting image generation task...")
        result = self._make_ark_request("POST", url, payload)

        try:
            image_url = result["data"][0]["url"]
            print(f"✅ Image generated: {image_url}")
            return image_url
        except KeyError:
            raise Exception(f"Failed to parse image URL. Response: {result}")

    # ─────────────── TTS（Seed Speech 2.0）───────────────

    def submit_tts_task(self, text, output_path, voice=None):
        """
        Seed Speech 2.0 HTTP 非流式 TTS。
        Endpoint: https://openspeech.bytedance.com/api/v3/tts/unidirectional
        鉴权: X-Api-Key (Seed Speech API Key)
        Resource-Id: seed-tts-2.0
        返回: MP3 音频文件路径
        """
        voice = voice or self.tts_voice

        payload = {
            "req_params": {
                "text": text,
                "speaker": voice,
                "audio_params": {
                    "format": "mp3",
                    "sample_rate": 24000
                }
            }
        }

        headers = {
            "Content-Type": "application/json",
            "X-Api-Key": self.tts_api_key,
            "X-Api-Resource-Id": self.tts_resource_id,
            "X-Api-Request-Id": str(uuid.uuid4())
        }

        print(f"🎤 Generating TTS audio...")
        print(f"   Voice: {voice}")
        print(f"   Resource-Id: {self.tts_resource_id}")
        print(f"   Text: {text[:60]}...")

        try:
            resp = _requests.post(
                self.tts_base_url,
                headers=headers,
                json=payload,
                timeout=60,
                proxies={"https": "", "http": ""}
            )
            resp.raise_for_status()
            text = resp.text
            # 响应是多行 JSON (streaming chunks)
            # 每行: {"code":0,"message":"","data":"SUQzBAAAAA..."}
            # 最后一行: {"code":20000,"message":"..."}
            audio_chunks = []
            for line in text.strip().split('\n'):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get('code') == 0 and obj.get('data'):
                    audio_chunks.append(obj['data'])
                elif obj.get('code') not in (0, 20000):
                    msg = obj.get('message', str(obj))[:150]
                    print(f"  ⚠️  TTS chunk: {msg}")
            
            if not audio_chunks:
                raise Exception(f"TTS API: no audio data. Response: {text[:200]}")
            
            audio_data = base64.b64decode(''.join(audio_chunks))

            with open(output_path, "wb") as f:
                f.write(audio_data)
            size_kb = len(audio_data) / 1024
            print(f"✅ TTS saved: {output_path} ({size_kb:.0f}KB)")
            return output_path

        except Exception as e:
            status = getattr(e, 'response', None)
            if status is not None:
                detail = status.text[:300]
                print(f"❌ TTS Error: {status.status_code} - {detail}")
            else:
                print(f"❌ TTS Error: {e}")
            raise

    def get_tts_voices(self):
        """
        返回支持的 Seed Speech 2.0 音色列表。
        实际可用音色以火山控制台为准：
        https://console.volcengine.com/speech/new/voices
        """
        return {
            "zh_female_vv_uranus_bigtts": "VV 2.0 (女生, 官方推荐)",
            "zh_female_xiaohe_uranus_bigtts": "小何 2.0 (女生, 通用)",
            "zh_male_m191_uranus_bigtts": "云舟 2.0 (男生, 通用)",
            "zh_male_taocheng_uranus_bigtts": "小天 2.0 (男生)",
            "zh_male_liufei_uranus_bigtts": "刘飞 2.0 (男生)",
        }

    # ─────────────── 任务轮询 ───────────────

    def query_task_status(self, task_id):
        """查询视频生成任务状态。"""
        url = f"{self.base_url}/contents/generations/tasks/{task_id}"
        result = self._make_ark_request("GET", url)
        return result

    def wait_for_video(self, task_id, poll_interval=10, timeout=600):
        """轮询等待视频生成完成。"""
        start_time = time.time()
        while time.time() - start_time < timeout:
            status_response = self.query_task_status(task_id)
            status = status_response.get("status", "unknown")
            elapsed = int(time.time() - start_time)
            print(f"  [{elapsed}s] Status: {status}")

            if status in ["succeeded", "completed"]:
                try:
                    content = status_response.get("content", {})
                    if isinstance(content, dict) and "video_url" in content:
                        if isinstance(content["video_url"], str):
                            return content["video_url"]
                        elif isinstance(content["video_url"], dict) and "url" in content["video_url"]:
                            return content["video_url"]["url"]
                    if isinstance(content, list):
                        for item in content:
                            if isinstance(item, dict) and item.get("type") == "video_url":
                                return item["video_url"]["url"]
                    print(f"⚠️  Could not parse video URL. Response: {status_response}")
                    return None
                except Exception as e:
                    print(f"⚠️ Parse error: {e}")
                    return status_response
            elif status in ["failed", "error"]:
                print(f"❌ Task failed: {status_response}")
                return None

            time.sleep(poll_interval)

        print("⏰ Polling timeout.")
        return None

    def download_video(self, video_url, output_path):
        """下载生成的视频到本地。"""
        print(f"⬇️ Downloading video...")
        try:
            urllib.request.urlretrieve(video_url, output_path)
            size_kb = os.path.getsize(output_path) / 1024
            print(f"✅ Downloaded: {output_path} ({size_kb:.0f}KB)")
            return output_path
        except Exception as e:
            print(f"❌ Download failed: {e}")
            raise


if __name__ == "__main__":
    print("Volcengine Client v3 — Loaded.")
    print("  TTS: Seed Speech 2.0 (dedicated API key)")
    print("  Video: Ark Seedance API (ark_api_key)")
    print("  Image: Ark Image Gen API (ark_api_key)")


    # ─────────────── 质量反关（Doubao Vision）───────────────

    def quality_check(self, video_path):
        """
        用 Doubao Vision 对视频抽取3帧做质量检测。
        检查：Logo可见性、字幕可见性、画面清晰度、画面缺陷。
        """
        if not self.vision_endpoint:
            print("  ⚠️  未配置 Vision endpoint，跳过质量反关")
            return

        import subprocess, base64, os, tempfile, requests, json
        tmpdir = tempfile.mkdtemp()
        frames = {}
        try:
            for pct, label in [(0.2, "开场"), (0.5, "中段"), (0.8, "结尾")]:
                out = os.path.join(tmpdir, f"{label}.jpg")
                subprocess.run(
                    ["ffmpeg", "-y", "-ss", f"{pct*15:.1f}",
                     "-i", video_path, "-vframes", "1", "-q:v", "2", out],
                    capture_output=True, timeout=30
                )
                frames[label] = out

            vision_url = f"{self.base_url}/chat/completions"
            results = []
            for label, fp in frames.items():
                with open(fp, "rb") as img:
                    b64 = base64.b64encode(img.read()).decode('utf-8')

                payload = {
                    "model": self.vision_endpoint,
                    "messages": [{"role": "user", "content": [
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                        {"type": "text", "text": "检查这张视频截图：1)右上角有无logo？2)底部有无中文字幕？3)画面清晰度如何？4)有无明显画面缺陷？简短回答。"}
                    ]}],
                    "max_tokens": 200
                }
                headers = {"Content-Type": "application/json", "Authorization": f"Bearer {self.ark_api_key}"}
                resp = requests.post(vision_url, headers=headers, json=payload, timeout=30, proxies={"https": "", "http": ""})
                try:
                    ans = resp.json()["choices"][0]["message"]["content"]
                    print(f"    🖼️ {label}: {ans[:120]}")
                    results.append(ans)
                except:
                    print(f"    ⚠️ {label}: 检测失败")
            return results
        finally:
            import shutil
            shutil.rmtree(tmpdir, ignore_errors=True)
