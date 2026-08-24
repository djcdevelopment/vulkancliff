# Dataset: correctness and equivalence (the reviewer-facing checks)

Three independent checks that the patch changes *dispatch*, not *math* — and that the
default is a true no-op.

## 1. Kernel correctness vs CPU reference

`test-backend-ops.exe -o MUL_MAT -b Vulkan0` with `GGML_VK_MMV_MAX_COLS=16`:
**ALL PASS**. This exercises the MMV kernel at column counts 9-16 (unreachable in
stock builds) against the CPU reference implementation with tolerance checks.

## 2. Stock equivalence at default

Patched binary with the knob left at its default (8) vs the b10549 prebuilt release,
14B sanity bench: pp 1490.8 / tg 47.1 tok/s, within +-3% of the prebuilt — the
default path is behaviorally stock.

## 3. Perplexity A/B (end-to-end numerical comparison) — CORRECTED 2026-08-24

**The original run was a null test** (caught by
[ftoleedo](https://github.com/ftoleedo), reporter of issue #25356, while reviewing
PR #27652 — credit where due). `llama-perplexity` defaults to `-ub 512`,
so every dispatch had `ne[1] = 512`, above every legal value of the knob; the MMV
path was never selected and identical digits were guaranteed regardless of kernel
behavior. The original rows are preserved at the bottom as a record. The apparent
"1.6x faster per pass" in that run is likewise retracted: both configs ran the same
code path, so the timing delta was warm-up/cache, not the patch.

**Corrected run**: `-ub 12 -b 12` forces dispatches inside the window (knob 8 ->
general matmul path, knob 12/16 -> MMV path). Same input, `-c 512 --chunks 12`,
Mistral-Small-24B Q4_K_M, one B70:

| knob | path at ub=12 | final estimate | s/pass |
|---|---|---|---|
| 8 | matmul | PPL = 6.3148 +/- 0.28436 | 40.7 |
| 12 | MMV | PPL = 6.3130 +/- 0.28423 | 5.8 |
| 16 | MMV | PPL = 6.3130 +/- 0.28423 | 3.1 |

- **Control passes**: knob 12 and 16 agree to every printed digit (same kernel at
  `ne[1]=12`).
- **The two paths are not bit-identical**: delta 0.0018 PPL (~0.03%), far inside
  the +/-0.284 standard error, MMV favorable. Accumulation-order difference between
  kernels — the same shape reported on RDNA3.5/RADV in the PR thread (0.32% there).
  Kernel correctness vs the CPU reference is check #1's job, and it passes.
- The s/pass column is single-rep and order-confounded (run order 8, 12, 16;
  first-use pipeline compile tax) — the 40.7 vs 3-6 s/pass matmul-vs-MMV gap at
  12-token dispatches is consistent with the B=9 cliff mechanism, but is not a
  controlled timing claim.

Original (null) run, `-ub 512` default, both configs on the matmul path:

| setting | final estimate | s/pass |
|---|---|---|
| knob 8 | PPL = 6.3139 +/- 0.28430 | 8.25 |
| knob 16 | PPL = 6.3139 +/- 0.28430 | 5.11 |

Raw: `raw/expP-*` (null test) and `raw/expP2-*` (corrected) in this folder.
Harnesses: `../harness/expP-perplexity-ab.ps1`, `../harness/expP2-perplexity-ub12.ps1`.
