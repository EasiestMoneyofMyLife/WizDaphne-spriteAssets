#!/usr/bin/env python3
# dhash_batch.py
# 子命令:
#   scan  <目录> <输出.tsv>
#   match <基准.tsv> <候选.tsv> <阈值> <输出.tsv>
#   same  <基准.tsv> <候选.tsv> <输出.tsv>
import sys, os
from PIL import Image

def dhash(path, size=8):
    img = Image.open(path).convert("L").resize((size + 1, size), Image.LANCZOS)
    px = list(img.getdata())
    bits = 0
    for row in range(size):
        base = row * (size + 1)
        for col in range(size):
            left = px[base + col]
            right = px[base + col + 1]
            bits = (bits << 1) | (1 if left > right else 0)
    return bits

def cmd_scan(root, out):
    rows = []
    for dirpath, _, files in os.walk(root):
        if os.sep + "deleted" + os.sep in dirpath + os.sep:
            continue
        for fn in files:
            if fn == ".gitkeep":
                continue
            if fn.endswith(".png") and "#" in fn:
                continue
            if not fn.lower().endswith(".png"):
                continue
            fp = os.path.join(dirpath, fn)
            try:
                h = dhash(fp)
                rows.append((fn, f"{h:016x}", fp))
            except Exception:
                rows.append((fn, "", fp))
    with open(out, "w", encoding="utf-8") as f:
        for name, h, fp in rows:
            f.write(f"{name}\t{h}\t{fp}\n")
    print(f"scan {root}: {len(rows)} files -> {out}")

def popcount64(x):
    import numpy as np
    x = x.astype(np.uint64, copy=False)
    x = x - ((x >> np.uint64(1)) & np.uint64(0x5555555555555555))
    x = (x & np.uint64(0x3333333333333333)) + ((x >> np.uint64(2)) & np.uint64(0x3333333333333333))
    x = (x + (x >> np.uint64(4))) & np.uint64(0x0F0F0F0F0F0F0F0F)
    return ((x * np.uint64(0x0101010101010101)) >> np.uint64(56)).astype(np.int64)

def cmd_match(base_tsv, cand_tsv, threshold, out_tsv):
    import numpy as np
    threshold = int(threshold)

    base_names = []
    base_hashes = []
    with open(base_tsv, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 3 or not p[1]:
                continue
            base_names.append(p[0])
            base_hashes.append(int(p[1], 16))

    cand_names = []
    cand_hashes = []
    cand_paths = []
    with open(cand_tsv, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 3:
                continue
            cand_names.append(p[0])
            cand_hashes.append(int(p[1], 16) if p[1] else -1)
            cand_paths.append(p[2])

    N = len(cand_names)
    M = len(base_hashes)

    # 结果默认无匹配
    best_name = [""] * N
    best_dist = [999] * N

    if M > 0:
        base_arr = np.array(base_hashes, dtype=np.uint64)
        # 只处理 hash 有效的候选
        valid_idx = [i for i, h in enumerate(cand_hashes) if h >= 0]
        if valid_idx:
            cand_valid = np.array([cand_hashes[i] for i in valid_idx], dtype=np.uint64)
            # 分批，控制内存
            BATCH = 512
            for start in range(0, len(cand_valid), BATCH):
                end = min(start + BATCH, len(cand_valid))
                chunk = cand_valid[start:end]
                xor = np.bitwise_xor(chunk[:, None], base_arr[None, :])
                dist = popcount64(xor)  # (batch, M)
                bi = np.argmin(dist, axis=1)
                bd = dist[np.arange(dist.shape[0]), bi]
                for k in range(len(chunk)):
                    g = valid_idx[start + k]
                    d = int(bd[k])
                    best_dist[g] = d
                    if d <= threshold:
                        best_name[g] = base_names[int(bi[k])]

    with open(out_tsv, "w", encoding="utf-8") as f:
        for i in range(N):
            f.write(f"{cand_names[i]}\t{best_name[i]}\t{best_dist[i]}\t{cand_paths[i]}\n")
    print(f"match: {N} candidates -> {out_tsv}")

def cmd_same(base_tsv, cand_tsv, out_tsv):
    base = {}
    with open(base_tsv, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) >= 3 and p[1]:
                base[p[0]] = int(p[1], 16)
    with open(out_tsv, "w", encoding="utf-8") as f:
        with open(cand_tsv, encoding="utf-8") as cf:
            for line in cf:
                p = line.rstrip("\n").split("\t")
                if len(p) < 3 or not p[1]:
                    continue
                name, hstr, fp = p[0], p[1], p[2]
                if name not in base:
                    continue
                d = bin(int(hstr, 16) ^ base[name]).count("1")
                f.write(f"{name}\t{d}\t{fp}\n")
    print(f"same -> {out_tsv}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: dhash_batch.py scan|match|same ...", file=sys.stderr)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "scan" and len(sys.argv) == 4:
        cmd_scan(sys.argv[2], sys.argv[3])
    elif cmd == "match" and len(sys.argv) == 6:
        cmd_match(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif cmd == "same" and len(sys.argv) == 5:
        cmd_same(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print("参数错误", file=sys.stderr)
        sys.exit(1)