#!/usr/bin/env python3
"""
Shotstack Ingest API 素材入库：把本地图片/视频直传到 Shotstack 悉尼 S3，生成 {文件名: source URL} 映射。

流程（已验证）：
  ① POST https://api.shotstack.io/ingest/v1/upload  → 拿签名 S3 PUT URL + source id（该端点无 body，不能带 filename 参数，否则 400）
  ② PUT  本地文件 → 签名 URL（直传 Shotstack 悉尼 S3）
  ③ GET  https://api.shotstack.io/ingest/v1/sources/{id}  → 轮询 status=ready，取 source URL

同步串行版(推荐)：图片只传(--img-only)，50s ready 超时，边传边写日志文件(不依赖 tail 缓冲)。
⚠️ 已知坑：并行轮询版会因少数大视频的导入(source 状态 importing)卡死；视频素材少用。

用法:
  python3 ingest.py --dir /data/视频测试 --out map.json
  python3 ingest.py --dir /data/视频测试 --only SKU1,SKU2 --img-only --max-per 5 --timeout 50 --out map.json
"""
import argparse, json, os, sys, time, urllib.request

INGEST = "https://api.shotstack.io/ingest/v1"
API_KEY = "bWKfgZ4Kc8P53RJROL12A7ndBvfDTdVMLNas9xN2"
IMG_EXT = (".jpg", ".jpeg", ".png", ".webp", ".gif")
VID_EXT = (".mp4", ".mov", ".m4v", ".webm")
LOG = None


def log(msg):
    print(msg, flush=True)
    if LOG:
        with open(LOG, "a") as fh:
            fh.write(msg + "\n")


def http(method, url, data=None, headers=None, timeout=30):
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("x-api-key", API_KEY)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read()
        return r.status, body


def upload_flow(fpath, timeout=50):
    """单文件 Ingest 入库 → ready 的 source URL。返回 (ok, url_or_err)。"""
    fname = os.path.basename(fpath)
    # ① 拿签名上传 URL
    try:
        st, body = http("POST", f"{INGEST}/upload")
        up = json.loads(body)
        put_url = up["url"]
    except Exception as e:
        return False, f"upload-token失败({e})"
    # ② 直传
    try:
        with open(fpath, "rb") as fh:
            data = fh.read()
        st, _ = http("PUT", put_url, data=data,
                     headers={"Content-Type": "application/octet-stream"}, timeout=timeout)
    except Exception as e:
        return False, f"PUT失败({e})"
    sid = up.get("id") or put_url.split("/")[-1]
    # ③ 轮询 ready
    url = None
    for _ in range(int(timeout / 5) + 1):
        try:
            st, body = http("GET", f"{INGEST}/sources/{sid}", timeout=15)
            d = json.loads(body)
            if d.get("status") == "ready":
                url = d.get("sourceUrl") or d.get("url")
                break
            if d.get("status") == "fail":
                return False, "source failed"
        except Exception:
            pass
        time.sleep(5)
    if url:
        return True, url
    return False, "ready超时"


def scan_dir(root, only=None, img_only=False, max_per=None):
    """扫描目录, 返回 {SKU或文件夹名: [文件绝对路径, ...]}。"""
    out = {}
    for ent in sorted(os.listdir(root)):
        full = os.path.join(root, ent)
        if not os.path.isdir(full):
            continue
        sku = ent
        if only and not any(o in ent for o in only):
            continue
        files = []
        for fn in sorted(os.listdir(full)):
            low = fn.lower()
            if low.endswith(IMG_EXT) or (not img_only and low.endswith(VID_EXT)):
                files.append(os.path.join(full, fn))
        if max_per:
            files = files[:max_per]
        if files:
            out[sku] = files
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", default="map.json")
    ap.add_argument("--only", help="逗号分隔SKU/文件夹关键字")
    ap.add_argument("--img-only", action="store_true", help="只传图片, 跳过视频")
    ap.add_argument("--max-per", type=int, default=None, help="每个产品最多传几张")
    ap.add_argument("--timeout", type=int, default=50, help="每文件 ready 超时秒")
    ap.add_argument("--log", default=None, help="日志文件路径")
    args = ap.parse_args()

    global LOG
    LOG = args.log
    only = [x.strip() for x in args.only.split(",")] if args.only else None
    folders = scan_dir(args.dir, only=only, img_only=args.img_only, max_per=args.max_per)

    result = {}
    for sku, files in folders.items():
        log(f"[{sku}] {len(files)} files")
        result[sku] = {}
        for fp in files:
            ok, val = upload_flow(fp, timeout=args.timeout)
            tag = "OK " if ok else "ERR"
            log(f"   {tag} {os.path.basename(fp)} -> {val if not ok else 'ok'}")
            if ok:
                result[sku][os.path.basename(fp)] = val
        log(f"[{sku}] done {len(result[sku])}/{len(files)}")

    with open(args.out, "w") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
    log(f"[all] map -> {args.out} ({len(result)} products)")
    print(json.dumps(result, ensure_ascii=False)[:300])


if __name__ == "__main__":
    main()
