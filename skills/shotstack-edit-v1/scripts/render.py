#!/usr/bin/env python3
"""
Shotstack 渲染：提交 JSON → 轮询状态 → 下载成片。

生产端: POST https://api.shotstack.io/edit/v1/render
         GET  https://api.shotstack.io/edit/v1/render/{id}  (done 后 response.url)
鉴权:   x-api-key: bWKfgZ4Kc8P53RJROL12A7ndBvfDTdVMLNas9xN2
成片:   1080x1440 竖版, 约17s, 渲染约77s, 暂存URL 24h 过期需及时下载

用法:
  python3 render.py --json json/ --out videos/ --poll        # 全部提交+轮询+下载
  python3 render.py --json json/ --out videos/ --poll --only B6M3769,H3Y3676
  python3 render.py --json json/ --out videos/ --submit-only  # 只提交不下载
"""
import argparse, json, os, sys, time, urllib.request, urllib.error

API_KEY = "bWKfgZ4Kc8P53RJROL12A7ndBvfDTdVMLNas9xN2"
RENDER = "https://api.shotstack.io/edit/v1/render"


def http_json(method, url, payload=None, timeout=30):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("x-api-key", API_KEY)
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def submit(sku, edit):
    try:
        resp = http_json("POST", RENDER, payload=edit, timeout=40)
        rid = resp.get("response", {}).get("id")
        return True, rid, resp
    except urllib.error.HTTPError as e:
        err = e.read().decode()[:500]
        return False, None, err
    except Exception as e:
        return False, None, str(e)


def poll(rid, interval=8, max_wait=420):
    t0 = time.time()
    while time.time() - t0 < max_wait:
        try:
            d = http_json("GET", f"{RENDER}/{rid}", timeout=20)
            st = d.get("response", {}).get("status")
            if st == "done":
                return True, d["response"].get("url")
            if st == "failed":
                return False, d.get("response", {}).get("error") or "failed"
        except Exception:
            pass
        time.sleep(interval)
    return False, "poll超时"


def download(url, path):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=120) as r:
        with open(path, "wb") as fh:
            fh.write(r.read())
    return os.path.getsize(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default="json", help="渲染JSON目录")
    ap.add_argument("--out", default="videos", help="成片输出目录")
    ap.add_argument("--poll", action="store_true", help="提交后轮询并下载")
    ap.add_argument("--submit-only", action="store_true", help="只提交不轮询")
    ap.add_argument("--only", help="逗号分隔SKU")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    only = set(x.strip() for x in args.only.split(",")) if args.only else None

    files = sorted(f for f in os.listdir(args.json) if f.endswith(".json"))
    results = []
    for fn in files:
        sku = fn[:-5]
        if only and sku not in only:
            continue
        with open(os.path.join(args.json, fn)) as fh:
            edit = json.load(fh)
        ok, rid, info = submit(sku, edit)
        print(f"[{sku}] submit={'OK' if ok else 'ERR'} id={rid}", flush=True)
        if not ok:
            results.append({"sku": sku, "id": None, "status": "error", "info": info})
            continue
        if args.submit_only:
            results.append({"sku": sku, "id": rid, "status": "submitted"})
            continue
        if not args.poll:
            results.append({"sku": sku, "id": rid, "status": "submitted", "poll": "skipped"})
            continue
        # 轮询 + 下载
        done, url = poll(rid)
        if done and url:
            try:
                size = download(url, os.path.join(args.out, f"{sku}.mp4"))
                print(f"   -> done, {size/1e6:.1f}MB", flush=True)
                results.append({"sku": sku, "id": rid, "status": "done", "url": url, "size": size})
            except Exception as e:
                print(f"   -> 下载失败({e})", flush=True)
                results.append({"sku": sku, "id": rid, "status": "download_error", "url": url})
        else:
            print(f"   -> {url}", flush=True)
            results.append({"sku": sku, "id": rid, "status": "failed", "error": url})

    with open(os.path.join(args.out, "_results.json"), "w") as fh:
        json.dump(results, fh, ensure_ascii=False, indent=2)
    okn = sum(1 for r in results if r["status"] in ("done",))
    print(f"[done] {okn}/{len(results)} 成片 -> {args.out}")


if __name__ == "__main__":
    main()
