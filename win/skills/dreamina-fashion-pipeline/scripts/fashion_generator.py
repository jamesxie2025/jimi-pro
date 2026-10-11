#!/usr/bin/env python3
import os
import sys
import json
import argparse
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from PIL import Image

def run_cmd(args):
    """Run a shell command and return stdout as string."""
    try:
        res = subprocess.run(args, capture_output=True, text=True, check=True)
        return res.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {' '.join(args)}", file=sys.stderr)
        print(f"Stdout: {e.stdout}", file=sys.stderr)
        print(f"Stderr: {e.stderr}", file=sys.stderr)
        raise e

def submit_task(image_path, prompt, model_version="5.0", ratio="3:4"):
    """Submit a dreamina image2image task and return the submit_id."""
    args = [
        "dreamina", "image2image",
        "--images", image_path,
        "--prompt", prompt,
        "--model_version", model_version,
        "--ratio", ratio,
        "--poll", "0"  # We handle polling ourselves
    ]
    stdout = run_cmd(args)
    try:
        data = json.loads(stdout)
        return data.get("submit_id"), data.get("gen_status")
    except json.JSONDecodeError:
        print(f"Failed to parse JSON output: {stdout}", file=sys.stderr)
        return None, None

def poll_task(submit_id, download_dir, timeout=300):
    """Poll a dreamina task until it succeeds or fails, and download the output."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        args = [
            "dreamina", "query_result",
            "--submit_id", submit_id,
            "--download_dir", download_dir
        ]
        stdout = run_cmd(args)
        try:
            data = json.loads(stdout)
            status = data.get("gen_status")
            if status == "success":
                return "success", data
            elif status == "fail":
                return "fail", data.get("fail_reason", "unknown error")
        except json.JSONDecodeError:
            pass
        time.sleep(5)
    return "timeout", "task timed out"

def build_grid(image_paths, output_path, cols=2):
    """Combine multiple images into a grid."""
    if not image_paths:
        return
    
    # Open images and get sizes
    images = []
    for p in image_paths:
        try:
            images.append(Image.open(p))
        except Exception as e:
            print(f"Warning: could not open image {p}: {e}")
    
    if not images:
        return

    # Assuming all images are same size, resize if not
    w, h = images[0].size
    rows = (len(images) + cols - 1) // cols
    
    grid_img = Image.new("RGB", (w * cols, h * rows), color=(255, 255, 255))
    
    for idx, img in enumerate(images):
        r = idx // cols
        c = idx % cols
        if img.size != (w, h):
            img = img.resize((w, h), Image.Resampling.LANCZOS)
        grid_img.paste(img, (c * w, r * h))
        
    grid_img.save(output_path)
    print(f"🎉 Combined grid image saved to: {output_path}")

def main():
    parser = argparse.ArgumentParser(description="Fashion AI Design Assistant - Generator")
    parser.add_argument("--image", required=True, help="Path to the input clothing image")
    parser.add_argument("--action", choices=["season_convert", "grid_variants"], default="season_convert",
                        help="Action to perform: seasonal conversion or grid variants")
    parser.add_argument("--season", choices=["summer", "autumn", "winter", "spring"], default="summer",
                        help="Target season for conversion")
    parser.add_argument("--count", type=int, default=4, help="Number of variations (e.g. 4 or 9)")
    parser.add_argument("--model", default="5.0", help="Dreamina model version to use")
    parser.add_argument("--ratio", default="3:4", help="Aspect ratio for generation")
    parser.add_argument("--output_dir", default="./output_variants", help="Directory to save generated images")
    parser.add_argument("--custom_prompt", default="", help="Additional details to append to the prompt")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.image):
        print(f"Error: input image '{args.image}' not found.")
        sys.exit(1)
        
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Construct base prompt
    prompts = []
    if args.action == "season_convert":
        season_prompts = {
            "summer": "Convert this clothing item into a summer version. Short sleeves, lightweight breathable cotton linen fabric, bright and refreshing summer colors, sunny feel, high fashion studio catalog photo, clean background, 8k resolution.",
            "winter": "Convert this clothing item into a winter version. Long sleeves, warm heavy wool cashmere fabric, cozy winter textures, rich deep winter colors, modeled in high fashion studio, clean background, 8k resolution.",
            "autumn": "Convert this clothing item into an autumn version. Medium sleeves, layered autumn style, trench coat/jacket texture, warm earth tones, soft knitwear texture, high fashion catalog style, clean background, 8k resolution.",
            "spring": "Convert this clothing item into a spring version. Short/medium sleeves, floral patterns, pastel palette, light cardigan or dress texture, spring blossoms vibe, high fashion catalog style, clean background, 8k resolution."
        }
        base_prompt = season_prompts[args.season]
        if args.custom_prompt:
            base_prompt += f" {args.custom_prompt}"
        prompts = [base_prompt] * args.count
    else:
        # grid_variants: generate diverse style variations of the input image
        base_prompt = "Generate a fashion variant design of this clothing item. Keep the general category but explore creative design modifications in collars, pockets, and details. Elegant designer styling, high fashion studio photo, 8k."
        if args.custom_prompt:
            base_prompt += f" {args.custom_prompt}"
        # Let's add slight prompt variations to enforce diversity
        variations = [
            ", focus on modern minimalist aesthetic",
            ", focus on utility pockets and techwear details",
            ", focus on classic vintage tailoring",
            ", focus on avant-garde asymmetric silhouette",
            ", focus on sporty casual style",
            ", focus on elegant luxury detailing",
            ", focus on bohemian relaxed fit",
            ", focus on geometric paneling",
            ", focus on premium embroidered details"
        ]
        prompts = [base_prompt + variations[i % len(variations)] for i in range(args.count)]
        
    print(f"👗 Action: {args.action}")
    if args.action == "season_convert":
        print(f"☀️ Target Season: {args.season.upper()}")
    print(f"🖼️ Input Image: {args.image}")
    print(f"🔢 Count: {args.count} variations")
    print(f"🤖 Model: {args.model}")
    print(f"📐 Ratio: {args.ratio}")
    print(f"📂 Output Dir: {args.output_dir}")
    print("\n🚀 Submitting tasks to Dreamina...")
    
    submit_ids = []
    # Submit tasks in a thread pool to speed up submission
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(submit_task, args.image, p, args.model, args.ratio): p for p in prompts}
        for future in as_completed(futures):
            prompt = futures[future]
            try:
                sid, status = future.result()
                if sid:
                    print(f"  ✅ Task submitted! ID: {sid} (Status: {status})")
                    submit_ids.append(sid)
                else:
                    print(f"  ❌ Failed to submit task for prompt: {prompt}")
            except Exception as e:
                print(f"  ❌ Exception during submission: {e}")
                
    if not submit_ids:
        print("Error: No tasks were successfully submitted.")
        sys.exit(1)
        
    print(f"\n⏳ Polling {len(submit_ids)} tasks for completion (this may take 1-3 minutes)...")
    
    completed_files = []
    
    # We will poll tasks in parallel
    with ThreadPoolExecutor(max_workers=len(submit_ids)) as executor:
        run_temp_dir = os.path.join(args.output_dir, f"run_{int(time.time())}")
        os.makedirs(run_temp_dir, exist_ok=True)
        
        futures = {executor.submit(poll_task, sid, run_temp_dir): sid for sid in submit_ids}
        for future in as_completed(futures):
            sid = futures[future]
            try:
                status, info = future.result()
                if status == "success":
                    print(f"  🎯 Task {sid} finished successfully!")
                    # Scan files in run_temp_dir
                    files = [os.path.join(run_temp_dir, f) for f in os.listdir(run_temp_dir) if os.path.isfile(os.path.join(run_temp_dir, f))]
                    # Find downloaded files that haven't been processed yet
                    for f in files:
                        if f not in completed_files:
                            new_name = os.path.join(args.output_dir, f"variant_{len(completed_files) + 1}.png")
                            os.rename(f, new_name)
                            completed_files.append(new_name)
                            print(f"    💾 Saved to: {new_name}")
                            break
                else:
                    print(f"  ❌ Task {sid} failed: {info}")
            except Exception as e:
                print(f"  ❌ Exception during polling task {sid}: {e}")
                
    # Clean up temp directory
    try:
        for f in os.listdir(run_temp_dir):
            os.remove(os.path.join(run_temp_dir, f))
        os.rmdir(run_temp_dir)
    except Exception:
        pass
        
    if completed_files:
        print(f"\n✅ Generated {len(completed_files)} clothing variations successfully.")
        cols = 2 if args.count <= 4 else 3
        grid_output = os.path.join(args.output_dir, f"grid_{args.action}_{args.season if args.action=='season_convert' else 'variants'}.png")
        build_grid(completed_files, grid_output, cols=cols)
    else:
        print("Error: No images were successfully generated.")
        sys.exit(1)

if __name__ == "__main__":
    main()
