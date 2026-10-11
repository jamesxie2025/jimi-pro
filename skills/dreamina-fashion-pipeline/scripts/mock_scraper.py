#!/usr/bin/env python3
import os
import sys
import json

def scan_clothing_folders(base_dir):
    """Scan subdirectories in base_dir for clothing images and tag them."""
    if not os.path.exists(base_dir):
        print(f"Error: directory '{base_dir}' not found.", file=sys.stderr)
        return []
        
    catalog = []
    
    # We will look at subdirectories
    for item in os.listdir(base_dir):
        item_path = os.path.join(base_dir, item)
        if not os.path.isdir(item_path) or item.startswith('.'):
            continue
            
        # Analyze category and basic season from folder name
        # Folder names examples: "上衣A3F3123", "卫衣F3D3290", "外套F2F3033", "短袖E1F3068", "短裙N1F3351"
        category = "Other"
        season = "all-season"
        
        if "上衣" in item:
            category = "Tops"
        elif "卫衣" in item:
            category = "Sweater"
            season = "autumn/winter"
        elif "外套" in item:
            category = "Jacket/Coat"
            season = "autumn/winter"
        elif "短袖" in item:
            category = "T-Shirt"
            season = "summer"
        elif "短裙" in item:
            category = "Skirt"
            season = "summer/spring"
        elif "风衣" in item:
            category = "Trench Coat"
            season = "autumn"
        elif "毛衣" in item or "毛织" in item:
            category = "Knitwear"
            season = "winter"
        elif "衬衫" in item or "衬衣" in item:
            category = "Shirt"
            
        # Find images in this folder
        images = []
        for f in os.listdir(item_path):
            if f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp')):
                images.append(os.path.join(item_path, f))
                
        if not images:
            continue
            
        catalog.append({
            "id": item,
            "folder_name": item,
            "category": category,
            "season": season,
            "images": images,
            "tags": [category, season, "trend", "popular"]
        })
        
    return catalog

def main():
    base_dir = "Materials/视频测试"
    output_file = "Materials/trend_catalog.json"
    
    print(f"🔍 Scanning fashion materials in: {base_dir}")
    catalog = scan_clothing_folders(base_dir)
    
    if not catalog:
        print("⚠️ No clothing items found to catalog.")
        sys.exit(1)
        
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        
    print(f"🎉 Successfully crawled and indexed {len(catalog)} trend items!")
    print(f"💾 Catalog saved to: {output_file}")
    
    # Print some stats
    categories = {}
    for item in catalog:
        cat = item["category"]
        categories[cat] = categories.get(cat, 0) + 1
        
    print("\n📊 Trend Database Statistics:")
    for cat, count in categories.items():
        print(f"  - {cat}: {count} items")

if __name__ == "__main__":
    main()
