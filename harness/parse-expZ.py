# Parse expZ roster-sweep batched-bench outputs into a tidy CSV + summary table.
# Valid inputs only: spill-poisoned runs live in results/quarantine-spilled and
# are excluded by construction. gptoss20 legs join automatically when present.
import csv, glob, os, re, sys

RES = r"E:\work\battlemage\burnin-2026-08\results"
VENDOR = {
    "phi4": ("Microsoft", "Phi-4 14B"),
    "gemma27": ("Google", "Gemma-3-27B"),
    "gptoss20": ("OpenAI", "gpt-oss-20b"),
    "qwen32": ("Alibaba", "Qwen2.5-32B"),
    "moe30": ("Alibaba", "Qwen3-30B-A3B MoE"),
    "mistral24": ("Mistral", "Mistral-Small-24B"),
    "llama70": ("Meta", "Llama-3.3-70B (2xB70)"),
}
CTX = {"": 65536, "-c32k": 32768, "-c24k": 24576}

rows = []
for path in sorted(glob.glob(os.path.join(RES, "expZ-*.txt"))):
    m = re.match(r"expZ-(\w+)-mmv(\d+)(-c\d+k)?\.txt$", os.path.basename(path))
    if not m:
        continue
    tag, mmv, suf = m.group(1), int(m.group(2)), m.group(3) or ""
    vendor, label = VENDOR.get(tag, ("?", tag))
    for line in open(path, encoding="utf-8", errors="replace"):
        c = [x.strip() for x in line.split("|")]
        if len(c) > 9 and c[1] == "512" and c[3].isdigit():
            b, spp, stg = int(c[3]), float(c[6]), float(c[8])
            rows.append(dict(model=label, vendor=vendor, tag=tag, mmv=mmv,
                             ctx=CTX[suf], B=b, S_PP=spp, S_TG=stg,
                             per_thread=round(stg / b, 2)))

out = os.path.join(RES, "expZ-summary.csv")
with open(out, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)
print(f"{len(rows)} rows -> {out}\n")

def cell(tag, mmv, b, field="S_TG"):
    for r in rows:
        if r["tag"] == tag and r["mmv"] == mmv and r["B"] == b:
            return r[field]
    return None

order = ["llama70", "gptoss20", "phi4", "gemma27", "qwen32", "moe30", "mistral24"]
print(f"{'model':<24}{'ctx':>6} | {'B8':>7} | {'B9 stock':>9}{'B9 @16':>9}{'gain':>7} | "
      f"{'B16 stock':>10}{'B16 @16':>9}{'gain':>7} | {'B32':>7}")
for tag in order:
    if cell(tag, 8, 8) is None:
        print(f"{VENDOR[tag][1]:<24}  (missing)")
        continue
    ctx = [r["ctx"] for r in rows if r["tag"] == tag][0]
    b9s, b9p = cell(tag, 8, 9), cell(tag, 16, 9)
    b16s, b16p = cell(tag, 8, 16), cell(tag, 16, 16)
    print(f"{VENDOR[tag][1]:<24}{ctx:>6} | {cell(tag, 8, 8):>7} | {b9s:>9}{b9p:>9}"
          f"{b9p / b9s:>6.1f}x | {b16s:>10}{b16p:>9}{b16p / b16s:>6.1f}x | {cell(tag, 8, 32):>7}")
print("\nB8 / B32 = stock aggregate at those B (matmul path at 32).")
print("gain = patched (GGML_VK_MMV_MAX_COLS=16) over stock at same B, warm single rep.")
