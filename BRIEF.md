# The Knee: llama.cpp Vulkan's hard-coded 8-thread ceiling, found, proven, and moved

*The complete technical brief for this repo. Every number is reproduced in the
per-dataset files under `data/`; the charts in `charts/` regenerate from `data/raw/`
via `charts/gen_charts_light.py`.*

## What we found

llama.cpp's Vulkan backend hard-codes the batch width of its fast decode kernel:

```cpp
static constexpr uint32_t mul_mat_vec_max_cols = 8;
```

(`ggml/src/ggml-vulkan/ggml-vulkan.cpp`, master `e85caa8`, ~line 389.)

Decode batches of 8 or fewer sequences ride the fast matrix-vector (MMV) kernel. The
9th sequence pushes the whole batch onto a general matrix-multiply path that is
catastrophic at decode shapes: aggregate throughput collapses ~6x and does not fully
recover until batch sizes far beyond interactive use. The result is a hard
multitasking ceiling of exactly 8 concurrent streams on affected GPUs, independent of
host, RAM, card count, or model.

We patched the constant into a runtime knob (`GGML_VK_MMV_MAX_COLS`, default 8 =
byte-identical stock behavior, clamped 1..16; one file, +24/-3 lines) and proved
causality by dose-response: set the limit to 4/8/16 and the cliff lands at exactly
4/8/16.

## Why it's important

- It is a **software wall wearing a hardware costume**. We (and others upstream)
  attributed it to RAM, bandwidth, and host limits. It survived a complete machine
  rebuild (new CPU, 4x the RAM, new OS, new driver) untouched, because it is a
  compile-time constant that is blind to all of that.
- It caps what a local-AI box *is*: how many assistants/agents/users one machine can
  serve at once. Moving 8 -> 16 roughly **doubles the parallel-agent capacity of the
  same silicon** at zero hardware cost.
- The 9th thread is where every multi-user or multi-agent deployment quietly dies
  today: aggregate 6x collapse, per-stream rates below human reading speed.

## What it impacts

- **Backend**: llama.cpp Vulkan only. The CUDA backend merged the same shape of fix
  in Aug 2026 (`GGML_CUDA_MMVQ_MAX`, PR #26079). NVIDIA-on-Vulkan shows no cliff
  (its coopmat path wins anyway), so the landable form is an env knob with a
  conservative default, not a blanket raise.
- **Hardware**: measured on Intel Arc Pro B70 (Xe2, Windows 11, driver 32.0.101.8974);
  the same cliff is reported upstream on AMD Strix Halo (gfx1151) in issue #25356.
- **Models**: dense architectures take the full hit and the full fix (x6.6-6.9 at
  B=9). MoE models are hit on their dense attention projections only; their expert
  FFNs sit behind a separate dispatch gate (`MUL_MAT_ID`), which is the half already
  under discussion upstream. Our data cleanly separates the two.
- **Serving**: any `llama-server -np > 8`, batched inference, or multi-client host on
  the Vulkan backend.

## How we tested

One patched binary; only the env var changes between runs. Protocol matches the
upstream thread for comparability: `llama-batched-bench -c 65536 -ngl 999 -fa 1
-npp 512 -ntg 128`, B swept 1..32. Rigor rules enforced by the harnesses:

- **Warm reps cited** (first use of each batch-width pipeline pays a one-time
  shader-compile tax; rep 1 is warmup).
- **Cool-start gate**: every leg starts below 50 C (IGCL telemetry).
- **Spill guard**: Windows VidMm demotes oversized allocations to shared memory
  *silently* and the benchmark keeps running at 1/15th speed. Harnesses watch the
  PDH `GPU Adapter Memory\Shared Usage` counters during every leg and kill anything
  over 2 GB shared on two consecutive probes. Two poisoned runs were caught exactly
  this way and are preserved in quarantine. Context sizes per model are the largest
  that fit fully resident (footnoted in every table).
- **No co-tenant**: harnesses refuse to run if any other llama-server holds VRAM.
- **Event sweep**: zero TDR (Event 4101) / WHEA across the entire campaign.

Four experiments, one per data file in this folder:

| dataset | file | one-line result |
|---|---|---|
| Discovery ladders | [`data/data-discovery-ladders.md`](data/data-discovery-ladders.md) | knee at exactly 8 across 3 configs, 2 machines, 3 model classes |
| Dose-response | [`data/data-dose-response.md`](data/data-dose-response.md) | cliff follows the knob: 4 -> 6, 8 -> 9, 16 -> 24 (first sample past each) |
| Name-brand roster | [`data/data-roster.md`](data/data-roster.md) | 7 vendors; dense x6.6-6.9 at B=9; MoE gains only its dense share |
| Frame pacing | [`data/data-frame-pacing.md`](data/data-frame-pacing.md) | 10-concurrent median 204 s -> 38 s per request (x5.4) |
| Correctness | [`data/data-correctness.md`](data/data-correctness.md) | kernel tests pass; PPL identical to every digit; stock-identical at default |

## The change result (headline numbers)

Mistral-Small-24B, one Arc Pro B70, warm, stock (8) vs patched (16):

| measure | stock | patched | gain |
|---|---|---|---|
| 9th thread, aggregate | 19.7 tok/s | 131.5 tok/s | **x6.7** |
| 16 threads, aggregate | 45.4 tok/s | 158.5 tok/s | **x3.5** |
| 16-on-MMV vs 32-on-matmul | 139.5 (B=32) | 158.5 (B=16) | MMV wins |
| 10-concurrent request latency (median) | 204 s | 38 s | **x5.4** |
| per-stream decode at 10 threads | 1.3 tok/s | 5.4 tok/s | x4.2 |

## The line of code and the patch

- Stock: `static constexpr uint32_t mul_mat_vec_max_cols = 8;`
  (`ggml/src/ggml-vulkan/ggml-vulkan.cpp`, ~line 389 at master `e85caa8`)
- Patch: compile-time max raised to 16; `GGML_VK_MMV_MAX_COLS` read once (default 8 =
  stock, clamped 1..16) and applied at both dispatch gates. +24/-3, one file.
- The patch is [`patch/GGML_VK_MMV_MAX_COLS.diff`](patch/GGML_VK_MMV_MAX_COLS.diff)
  in this repo; it applies to llama.cpp master (`-DGGML_VULKAN=ON` build).

## Links

- Upstream issue (the conversation our data joins):
  https://github.com/ggml-org/llama.cpp/issues/25356
- CUDA precedent (merged 2026-08-20): https://github.com/ggml-org/llama.cpp/pull/26079
- Constant's origin: https://github.com/ggml-org/llama.cpp/pull/10991
- **Our PR: not yet opened.** Sequence: a comment with this data lands on #25356
  first, then the PR is cut from this patch with title
  `vulkan : add GGML_VK_MMV_MAX_COLS override for mul_mat_vec dispatch (#25356)`
  and AI disclosure per CONTRIBUTING.md. The link will be added here once it exists.
- Companion article: https://steppeintegrations.com/articles/vulkancliff/

## Provenance

Investigation, patch, and harnesses built with an AI assistant (Claude); Derek
Ciula directed the work and reviews every number and line before anything is
posted upstream. Raw data: [`data/raw/`](data/raw/) in this repo.
