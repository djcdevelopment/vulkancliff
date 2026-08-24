# Dataset: discovery ladders (Campaigns 0-1 — how the knee was found)

The three concurrency ladders that established the knee is real, host-invariant, and
software-bound — before the source was ever read. Different machines, model classes,
and card counts; identical knee.

## Ladder 1 — May 2026, old box (AM4: Ryzen 9 5900X, 32 GB DDR4, Win10, driver 8801)

Server concurrency ladder, dual Arc Pro B70. Throughput peaked at 8 concurrent
sessions and collapsed by 10. Windows commit charge read 92% at the cliff, which
produced the (wrong) attribution: "the host RAM is the constraint; 8 is what 32 GB
buys you."

## Ladder 2 — 2026-08-21, rebuilt box (285K, 128 GB DDR5, Win11, driver 8974)

Qwen3-30B-A3B (MoE) split across both B70s, `llama-server` ladder, aggregate decode:

| slots | tok/s |
|---|---|
| 1 | 40 |
| 2 | 72 |
| 4 | 113 |
| 6 | 145 |
| 8 | 183 |
| 10 | 80 |

p95 latency 6 s -> 22 s at the cliff. **78 GB of commit headroom free at the moment
of collapse** — the May explanation was impossible. Same knee, new everything.

## Ladder 3 — 2026-08-22, the discriminator (dense 14B, ONE card, single tenant)

Designed to separate "bandwidth roofline" (knee should move with bytes/token and
card count) from "software capacity limit" (knee stays at 8):

| slots | tok/s |
|---|---|
| 1 | 27 |
| 8 | 134 |
| 10 | 27 |

p95 9 s -> 70 s. Knee at exactly 8 again — third configuration, most violent cliff
of the three. Conclusion: the limit lives in software. Source reading found
`mul_mat_vec_max_cols = 8` the same day.

## The cost model that predicted it (denning, May 2026)

```
N*_bw = SLO_TBT x B_vram / (k x L)     (bandwidth knee)
N*    = min( N*_bw , capacity_limit )
```

The binding branch is `capacity_limit`, and it is one line of source. The formula
sat in the public denning repo for three months next to the wrong attribution.

Full narrative: the companion article at
https://steppeintegrations.com/articles/vulkancliff/.
