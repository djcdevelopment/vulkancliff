# Parse expF frame-pacing JSONLs -> the gamer scoreboard per config:
# median / p95 / p99 / 1%-low / stutter count (request slower than 2x that
# config's own median), on per-request total latency. Also mean tg tok/s.
import glob, json, os, statistics as st

RES = r"E:\work\battlemage\burnin-2026-08\results"

def pct(sorted_vals, p):
    # nearest-rank percentile on ascending values
    if not sorted_vals:
        return None
    k = max(0, min(len(sorted_vals) - 1, round(p / 100 * len(sorted_vals)) - 1))
    return sorted_vals[k]

print(f"{'config':<28}{'n':>5}{'median s':>10}{'p95 s':>8}{'p99 s':>8}"
      f"{'1%-low s':>10}{'stutters':>10}{'mean tg':>9}")
for path in sorted(glob.glob(os.path.join(RES, "expF-*.jsonl"))):
    rows = [json.loads(x) for x in open(path, encoding="utf-8-sig") if x.strip()]
    lat = sorted(r["total_s"] for r in rows)
    tg = [r["tg_tok_s"] for r in rows]
    med = st.median(lat)
    # 1%-low: mean of the slowest 1% of requests (gamer convention, inverted
    # for latency: for fps it's the worst frames; here the worst requests)
    n_low = max(1, len(lat) // 100)
    low1 = st.mean(lat[-n_low:])
    stut = sum(1 for v in lat if v > 2 * med)
    name = os.path.basename(path).replace("expF-", "").replace(".jsonl", "")
    print(f"{name:<28}{len(rows):>5}{med:>10.2f}{pct(lat, 95):>8.2f}{pct(lat, 99):>8.2f}"
          f"{low1:>10.2f}{stut:>10}{st.mean(tg):>9.1f}")
print("\nstutter = request > 2x its config's own median latency")
print("1%-low = mean latency of the slowest 1% of requests")
