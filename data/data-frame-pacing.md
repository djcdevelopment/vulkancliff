# Dataset: frame pacing / threads-in-flow (expF)

The experiential measurement: 200 completion requests per config at concurrency 10 against a
patched `llama-server` (`-np 10 -c 40960 -fa on --no-mmap -fit off`), Mistral-Small-24B, one
B70. Identical prompt (~150 tok) and `n_predict=200` per request; one full-concurrency warmup
wave discarded; per-request timings from the server's own `timings` object, logged as JSONL
(one row per request, like a frame-time trace). No spill (PDH-checked post-warmup).

## Stock (GGML_VK_MMV_MAX_COLS=8)

| metric | value |
|---|---|
| requests | 200 |
| median latency | 204.12 s |
| p95 / p99 | 255.23 / 256.48 s |
| 1%-low (mean of slowest 1%) | 256.48 s |
| stutters (>2x own median) | 0 |
| per-stream decode, mean | 1.27 tok/s |
| latency deciles (s) | 89, 89, 148, 190, 198, 212, 223, 242, 249, 256 |

## Patched (GGML_VK_MMV_MAX_COLS=16)

| metric | value |
|---|---|
| requests | 200 |
| median latency | 37.93 s |
| p95 / p99 | 43.77 / 67.22 s |
| 1%-low (mean of slowest 1%) | 67.22 s |
| stutters (>2x own median) | 0 |
| per-stream decode, mean | 5.42 tok/s |
| latency deciles (s) | 29, 33, 34, 35, 38, 38, 41, 41, 42, 67 |

## Readings

- Stock past its cliff is not stuttery, it is uniformly broken: every request is slow together
  (median 204 s; ~1.3 tok/s per stream, below human reading speed).
- Patched runs the identical load at median 38 s and ~5.4 tok/s per stream: x5.4 per-request.
- Coined metric threads-in-flow (largest N with every stream at a usable rate): 8 stock -> 10+
  patched on the same silicon (16 is the new dispatch ceiling; 10 was the tested load).

Raw: `raw/expF-mistral24b-mmv{8,16}.jsonl` in this folder.
