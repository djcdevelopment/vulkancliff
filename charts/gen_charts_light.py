# vulkancliff chart generator - light "lab notebook" theme.
# Emits standalone SVGs (self-backgrounded, safe on any page) from the raw
# campaign results. Palette is the validated light-mode categorical trio
# (blue #2a78d6 / orange #eb6834 / aqua #1baf7a) on cream #f7f1e6; the aqua and
# orange slots sit just under 3:1 contrast on this surface, so every chart
# carries direct labels and the article/README pair each chart with a table
# (the relief rule). Red is reserved for cliff/redline status marks.
#
# Data inputs (see ../data/ for copies): batched-bench .txt outputs (expY/expZ),
# expF frame-pacing JSONLs. Regenerate: python gen_charts_light.py [resultsdir]
import csv, glob, io, json, os, re, statistics as st, sys

RES = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "raw")
OUT = os.path.dirname(os.path.abspath(__file__))

PAPER = "#f7f1e6"; INK = "#23201a"; DIM = "#6b6353"; GRID = "#ddd3bf"
BLUE = "#2a78d6"; ORANGE = "#eb6834"; AQUA = "#1baf7a"; RED = "#c22a29"
FONT = "Georgia, 'Segoe UI', serif"

def svg_open(w, h, label):
    return ('<svg viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="%s" '
            'font-family="%s"><rect x="0" y="0" width="%d" height="%d" fill="%s"/>'
            % (w, h, label, FONT, w, h, PAPER))

def grid_y(out, L, Rr, ymap, vals):
    for v in vals:
        out.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>' % (L, ymap(v), Rr, ymap(v), GRID))
        out.append('<text x="%d" y="%.1f" fill="%s" font-size="11" text-anchor="end">%d</text>' % (L - 8, ymap(v) + 4, DIM, v))

def bench_rows(path):
    rows = []
    for line in io.open(path, encoding="utf-8", errors="replace"):
        c = [x.strip() for x in line.split("|")]
        if len(c) > 9 and c[1] == "512" and c[3].isdigit():
            rows.append((int(c[3]), float(c[6]), float(c[8])))
    return rows

def write(name, parts):
    svg = "".join(parts) + "</svg>"
    io.open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n").write(svg)
    print(name, len(svg), "bytes")

BS = [1, 2, 4, 6, 8, 9, 10, 12, 16, 24, 32]

# ---------------------------------------------------------------- dose-response
expY = {v: {b: tg for b, _p, tg in bench_rows(os.path.join(RES, "expY-mistral24b-mmv%d-rep2.txt" % v))}
        for v in (4, 8, 16)}
W, H = 760, 404; L, R, T, B = 60, 24, 50, 66
pw, ph = W - L - R, H - T - B
def X(b): return L + pw * BS.index(b) / (len(BS) - 1)
def Y(v): return T + ph * (1 - v / 170.0)
c = [svg_open(W, H, "Dose-response: the throughput cliff lands wherever the limit is set")]
grid_y(c, L, W - R, Y, (0, 50, 100, 150))
for b in BS:
    c.append('<text x="%.1f" y="%d" fill="%s" font-size="11" text-anchor="middle">%d</text>' % (X(b), H - B + 18, DIM, b))
c.append('<text x="%.1f" y="%d" fill="%s" font-size="12" font-weight="bold" text-anchor="middle">parallel sequences (threads in flight)</text>' % ((L + W - R) / 2, H - B + 40, INK))
c.append('<text x="%d" y="%d" fill="%s" font-size="11">aggregate decode tok/s</text>' % (L - 40, T - 14, DIM))
CURVES = ((4, AQUA, "limit 4", 7.0, 6.5), (8, ORANGE, "limit 8 (stock)", 4.5, 5.0), (16, BLUE, "limit 16", 2.2, 3.2))
for lim, col, lbl, wdt, rad in CURVES:
    vals = expY[lim]
    pts = " ".join("%.1f,%.1f" % (X(b), Y(vals[b])) for b in BS if b in vals)
    c.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round" stroke-linecap="round"/>' % (pts, col, wdt))
for lim, col, lbl, wdt, rad in CURVES:
    for b in BS:
        if b in expY[lim]:
            c.append('<circle cx="%.1f" cy="%.1f" r="%s" fill="%s"><title>%s, B=%d: %.1f tok/s</title></circle>' % (X(b), Y(expY[lim][b]), rad, col, lbl, b, expY[lim][b]))
for lim, col, lbl, wdt, rad in CURVES:
    x = X(lim) + (X(BS[BS.index(lim) + 1]) - X(lim)) / 2
    c.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="%s" stroke-width="1.5" stroke-dasharray="5 4"/>' % (x, T, x, H - B, RED))
    c.append('<text x="%.1f" y="%d" fill="%s" font-size="11" text-anchor="middle">cliff &gt;%d</text>' % (x, T - 4, RED, lim))
c.append('<text x="%.1f" y="%.1f" fill="%s" font-size="13" font-weight="bold">move the number, the cliff moves</text>' % (X(9) + 8, Y(160), INK))
for i, (lim, col, lbl, wdt, rad) in enumerate(CURVES):
    c.append('<rect x="%d" y="%d" width="12" height="4" rx="2" fill="%s"/><text x="%d" y="%d" fill="%s" font-size="11">%s</text>' % (L + 8 + i * 140, H - 10, col, L + 24 + i * 140, H - 5, DIM, lbl))
write("dose-response.svg", c)

# ---------------------------------------------------------------- roster bars
VENDOR = {"phi4": "Phi-4 14B", "gemma27": "Gemma-3-27B", "gptoss20": "gpt-oss-20b",
          "qwen32": "Qwen2.5-32B", "moe30": "Qwen3-30B-A3B MoE", "mistral24": "Mistral-Small-24B",
          "llama70": "Llama-3.3-70B (2 GPU)"}
KLASS = {"phi4": "dense", "gemma27": "dense - 24k ctx", "qwen32": "dense - 32k ctx",
         "mistral24": "dense", "llama70": "dense - 32k ctx", "gptoss20": "MoE", "moe30": "MoE"}
Z = {}
for path in sorted(glob.glob(os.path.join(RES, "expZ-*.txt"))):
    m = re.match(r"expZ-(\w+)-mmv(\d+)(-c\d+k)?\.txt$", os.path.basename(path))
    if m:
        Z[(m.group(1), int(m.group(2)))] = {b: tg for b, _p, tg in bench_rows(path)}
ORDER = ["phi4", "gemma27", "qwen32", "mistral24", "llama70", "gptoss20", "moe30"]
W2 = 760; rowh = 58; H2 = 50 + len(ORDER) * rowh + 26; L2, R2 = 218, 60
def X2(v): return L2 + (W2 - L2 - R2) * v / 260.0
c = [svg_open(W2, H2, "Seven name-brand models at 16 threads: stock versus patched")]
for gv in (0, 50, 100, 150, 200, 250):
    c.append('<line x1="%.1f" y1="40" x2="%.1f" y2="%d" stroke="%s"/>' % (X2(gv), X2(gv), H2 - 24, GRID))
    c.append('<text x="%.1f" y="%d" fill="%s" font-size="11" text-anchor="middle">%d</text>' % (X2(gv), H2 - 8, DIM, gv))
c.append('<text x="%d" y="26" fill="%s" font-size="11">aggregate decode tok/s at B=16</text>' % (L2, DIM))
for i, tag in enumerate(ORDER):
    y = 50 + i * rowh
    s, p = Z[(tag, 8)][16], Z[(tag, 16)][16]
    c.append('<text x="%d" y="%d" fill="%s" font-size="12" text-anchor="end">%s</text>' % (L2 - 10, y + 14, INK, VENDOR[tag]))
    c.append('<text x="%d" y="%d" fill="%s" font-size="10" text-anchor="end">%s</text>' % (L2 - 10, y + 28, DIM, KLASS[tag]))
    c.append('<rect x="%.1f" y="%d" width="%.1f" height="14" rx="3" fill="%s"><title>%s stock, B=16: %.1f tok/s</title></rect>' % (X2(0), y, max(2, X2(s) - X2(0)), ORANGE, VENDOR[tag], s))
    c.append('<rect x="%.1f" y="%d" width="%.1f" height="14" rx="3" fill="%s"><title>%s patched, B=16: %.1f tok/s</title></rect>' % (X2(0), y + 17, max(2, X2(p) - X2(0)), BLUE, VENDOR[tag], p))
    c.append('<text x="%.1f" y="%d" fill="%s" font-size="11">%.0f</text>' % (X2(s) + 5, y + 11, DIM, s))
    c.append('<text x="%.1f" y="%d" fill="%s" font-size="12" font-weight="bold">%.0f&#8201;(x%.1f)</text>' % (X2(p) + 5, y + 29, INK, p, p / s))
c.append('<rect x="%d" y="34" width="12" height="10" rx="2" fill="%s"/><text x="%d" y="43" fill="%s" font-size="11">stock (limit 8)</text>' % (W2 - R2 - 300, ORANGE, W2 - R2 - 282, DIM))
c.append('<rect x="%d" y="34" width="12" height="10" rx="2" fill="%s"/><text x="%d" y="43" fill="%s" font-size="11">patched (16)</text>' % (W2 - R2 - 160, BLUE, W2 - R2 - 142, DIM))
write("roster.svg", c)

# ---------------------------------------------------------------- dyno sheet
dB = [1, 2, 4, 6, 8, 9, 10, 12, 16]
agg8 = [expY[8][b] for b in dB]; agg16 = [expY[16][b] for b in dB]
W3, H3 = 760, 448; L3, R3 = 60, 60
pw3 = W3 - L3 - R3
p1T, p1H = 40, 200; p2T, p2H = p1T + p1H + 44, 110
def X3(b): return L3 + pw3 * dB.index(b) / (len(dB) - 1)
def Y3a(v): return p1T + p1H * (1 - v / 170.0)
def Y3b(v): return p2T + p2H * (1 - v / 34.0)
c = [svg_open(W3, H3, "Dyno sheet: threads in flight versus total and per-thread throughput")]
c.append('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="%s" opacity="0.08"/>' % (X3(1), p1T, X3(16) - X3(1), p1H, BLUE))
c.append('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="%s" opacity="0.10"/>' % (X3(1), p1T, X3(8) - X3(1), p1H, ORANGE))
rl = X3(8) + (X3(9) - X3(8)) / 2
c.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % (rl, p1T, rl, p2T + p2H, RED))
c.append('<text x="%.1f" y="%d" fill="%s" font-size="11" text-anchor="middle">stock redline</text>' % (rl, p1T - 6, RED))
c.append('<text x="%.1f" y="%d" fill="%s" font-size="11" text-anchor="middle">patched redline: 16</text>' % (X3(16) - 30, p1T - 6, DIM))
for v in (0, 50, 100, 150):
    c.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>' % (L3, Y3a(v), W3 - R3, Y3a(v), GRID))
    c.append('<text x="%d" y="%.1f" fill="%s" font-size="11" text-anchor="end">%d</text>' % (L3 - 8, Y3a(v) + 4, DIM, v))
for v in (0, 10, 20, 30):
    c.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>' % (L3, Y3b(v), W3 - R3, Y3b(v), GRID))
    c.append('<text x="%d" y="%.1f" fill="%s" font-size="11" text-anchor="end">%d</text>' % (L3 - 8, Y3b(v) + 4, DIM, v))
c.append('<text x="%d" y="%d" fill="%s" font-size="12" font-weight="bold">TOTAL POWER  <tspan font-weight="normal" fill="%s">aggregate tok/s (all threads)</tspan></text>' % (L3, p1T - 22, INK, DIM))
c.append('<text x="%d" y="%d" fill="%s" font-size="12" font-weight="bold">TORQUE  <tspan font-weight="normal" fill="%s">tok/s each thread still feels</tspan></text>' % (L3, p2T - 8, INK, DIM))
for vals, col, wdt, ymap in ((agg8, ORANGE, 3, Y3a), (agg16, BLUE, 3, Y3a),
                             ([v / b for v, b in zip(agg8, dB)], ORANGE, 2.5, Y3b),
                             ([v / b for v, b in zip(agg16, dB)], BLUE, 2.5, Y3b)):
    pts = " ".join("%.1f,%.1f" % (X3(b), ymap(v)) for b, v in zip(dB, vals))
    c.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>' % (pts, col, wdt))
for vals, col, lbl in ((agg8, ORANGE, "stock (8)"), (agg16, BLUE, "patched (16)")):
    for b, v in zip(dB, vals):
        c.append('<circle cx="%.1f" cy="%.1f" r="4" fill="%s" stroke="%s" stroke-width="2"><title>%s: %d threads -&gt; %.1f tok/s total</title></circle>' % (X3(b), Y3a(v), col, PAPER, lbl, b, v))
c.append('<text x="%.1f" y="%.1f" fill="%s" font-size="13" font-weight="bold">the 9th thread: 125 &#8594; 20</text>' % (X3(9) + 6, Y3a(19.7) - 10, RED))
c.append('<text x="%.1f" y="%.1f" fill="%s" font-size="13" font-weight="bold" text-anchor="end">159 @ 16 threads</text>' % (X3(16) - 8, Y3a(158.5) + 24, BLUE))
for b in dB:
    c.append('<text x="%.1f" y="%d" fill="%s" font-size="11" text-anchor="middle">%d</text>' % (X3(b), p2T + p2H + 16, DIM, b))
c.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle" font-weight="bold">threads in flight</text>' % ((L3 + W3 - R3) / 2, H3 - 24, INK))
c.append('<text x="%.1f" y="%d" fill="%s" font-size="11" text-anchor="middle">same card - same watts - one line of code</text>' % ((L3 + W3 - R3) / 2, H3 - 6, DIM))
c.append('<rect x="%d" y="%d" width="12" height="4" rx="2" fill="%s"/><text x="%d" y="%d" fill="%s" font-size="11">stock (limit 8)</text>' % (L3 + 14, p1T + 8, ORANGE, L3 + 30, p1T + 13, DIM))
c.append('<rect x="%d" y="%d" width="12" height="4" rx="2" fill="%s"/><text x="%d" y="%d" fill="%s" font-size="11">patched (limit 16)</text>' % (L3 + 14, p1T + 26, BLUE, L3 + 30, p1T + 31, DIM))
write("dyno.svg", c)

# ---------------------------------------------------------------- frame strips
def fload(p):
    return [json.loads(x)["total_s"] for x in io.open(p, encoding="utf-8-sig") if x.strip()]
lat = {m: fload(os.path.join(RES, "expF-mistral24b-mmv%d.jsonl" % m)) for m in (8, 16)}
ymax = max(max(lat[8]), max(lat[16])) * 1.08
W4, H4 = 760, 430; L4, R4 = 56, 20
pH = 150; tops = {8: 44, 16: 44 + pH + 62}
c = [svg_open(W4, H4, "Frame pacing: per-request latency, stock versus patched, 10 threads in flight")]
for mmv, col, lbl in ((8, ORANGE, "stock (limit 8)"), (16, BLUE, "patched (limit 16)")):
    vals = lat[mmv]; top = tops[mmv]
    med = st.median(vals); n = len(vals)
    bw = (W4 - L4 - R4) / max(1, n)
    def Y4(v, _t=top): return _t + pH * (1 - v / ymax)
    for gv in range(0, int(ymax) + 1, 50):
        c.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>' % (L4, Y4(gv), W4 - R4, Y4(gv), GRID))
        c.append('<text x="%d" y="%.1f" fill="%s" font-size="10" text-anchor="end">%d</text>' % (L4 - 6, Y4(gv) + 3, DIM, gv))
    for i, v in enumerate(vals):
        x = L4 + i * bw
        c.append('<rect x="%.2f" y="%.1f" width="%.2f" height="%.1f" fill="%s"><title>request %d: %.2f s</title></rect>' % (x, Y4(v), max(0.8, bw - 0.6), top + pH - Y4(v), col, i + 1, v))
    c.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s" stroke-width="1.2" stroke-dasharray="4 4"/>' % (L4, Y4(med), W4 - R4, Y4(med), INK))
    c.append('<text x="%d" y="%d" fill="%s" font-size="12" font-weight="bold">%s  <tspan fill="%s" font-weight="normal">median %.1f s per request - %d requests, 10 in flight</tspan></text>' % (L4, top - 8, col, lbl, DIM, med, n))
c.append('<text x="%.1f" y="%d" fill="%s" font-size="11" text-anchor="middle">request index (completion order) - seconds per request, lower and flatter is better</text>' % ((L4 + W4 - R4) / 2, H4 - 8, DIM))
write("frame-strips.svg", c)

# ---------------------------------------------------------------- discovery knee
lad2 = [(1, 40), (2, 72), (4, 113), (6, 145), (8, 183), (10, 80)]
lad3 = [(1, 27), (8, 134), (10, 27)]
W5, H5 = 760, 320; pw5 = 320; gap = 60; L5 = 54; T5, B5 = 56, 60
ph5 = H5 - T5 - B5
c = [svg_open(W5, H5, "The knee that would not move: two machines, two model classes, same collapse at 9")]
panels = ((L5, lad2, 200, "30B MoE, two GPUs, 128 GB host", "aggregate tok/s"),
          (L5 + pw5 + gap, lad3, 150, "dense 14B, ONE GPU", ""))
for px, data, vmax, title, ylab in panels:
    def X5(slot, _px=px): return _px + pw5 * ([d[0] for d in data].index(slot)) / (len(data) - 1)
    def Y5(v, _vm=vmax): return T5 + ph5 * (1 - v / _vm)
    for gv in range(0, vmax + 1, 50):
        c.append('<line x1="%d" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s"/>' % (px, Y5(gv), px + pw5, Y5(gv), GRID))
        c.append('<text x="%d" y="%.1f" fill="%s" font-size="10" text-anchor="end">%d</text>' % (px - 5, Y5(gv) + 3, DIM, gv))
    kx = (X5(8) + X5(10)) / 2
    c.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="1.5" stroke-dasharray="5 4"/>' % (kx, T5, kx, H5 - B5, RED))
    pts = " ".join("%.1f,%.1f" % (X5(s), Y5(v)) for s, v in data)
    c.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="3" stroke-linejoin="round"/>' % (pts, ORANGE))
    for s, v in data:
        c.append('<circle cx="%.1f" cy="%.1f" r="4.5" fill="%s" stroke="%s" stroke-width="2"><title>%d slots: %d tok/s</title></circle>' % (X5(s), Y5(v), ORANGE, PAPER, s, v))
        c.append('<text x="%.1f" y="%d" fill="%s" font-size="10" text-anchor="middle">%d</text>' % (X5(s), H5 - B5 + 14, DIM, s))
    c.append('<text x="%.1f" y="%d" fill="%s" font-size="12" font-weight="bold" text-anchor="middle">%s</text>' % (px + pw5 / 2, T5 - 26, INK, title))
    if ylab:
        c.append('<text x="%d" y="%d" fill="%s" font-size="10">%s</text>' % (px - 40, T5 - 10, DIM, ylab))
    c.append('<text x="%.1f" y="%d" fill="%s" font-size="11" text-anchor="middle">knee at 8</text>' % (kx, T5 - 8, RED))
c.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle" font-weight="bold">concurrent sessions - different machine, model, and card count; identical knee</text>' % (W5 / 2, H5 - 12, INK))
write("discovery-knee.svg", c)
print("done")
