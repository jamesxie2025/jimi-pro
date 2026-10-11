#!/usr/bin/env python3
"""
通用资源上传辅助：单个/多个本地文件 → Shotstack Ingest 入库 → {原文件名: source URL}。

实际批量入库用 ingest.py；本脚本提供单一文件的 upload_flow 复用入口 + 简单 CLI。

用法:
  python3 upload_assets.py --file /data/视频测试/上衣A3F3123/xx.jpg
  python3 upload_assets.py --dir /data/视频测试 --out map.json --img-only
"""
import argparse, json, os, sys

# 复用 ingest.py 的 upload_flow/scan_dir
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ingest import upload_flow, scan_dir  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", help="单文件路径")
    ap.add_argument("--dir", help="目录(批量/按文件夹)")
    ap.add_argument("--out", default="upload_map.json")
    ap.add_argument("--img-only", action="store_true")
    args = ap.parse_args()

    result = {}
    if args.file:
        ok, val = upload_flow(args.file)
        print(f"{'OK' if ok else 'ERR'} {args.file} -> {val if ok else val}")
        result[os.path.basename(args.file)] = val if ok else val
    elif args.dir:
        folders = scan_dir(args.dir, img_only=args.img_only)
        for sku, files in folders.items():
            print(f"[{sku}] {len(files)}")
            result[sku] = {}
            for fp in files:
                ok, val = upload_flow(fp)
                print(f"   {'OK ' if ok else 'ERR'} {os.path.basename(fp)}")
                if ok:
                    result[sku][os.path.basename(fp)] = val
    else:
        ap.error("需要 --file 或 --dir")

    with open(args.out, "w") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
    print(f"-> {args.out}")


if __name__ == "__main__":
    main()
