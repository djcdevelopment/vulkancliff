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

## 3. Perplexity A/B (end-to-end numerical equivalence)

`llama-perplexity`, Mistral-Small-24B Q4_K_M, one B70, same 472,755-byte text input
(deterministic, 12 chunks), same binary, only the env var changed:

| setting | final estimate | time per pass |
|---|---|---|
| `GGML_VK_MMV_MAX_COLS=8` | PPL = 6.3139 +/- 0.28430 | 8.25 s |
| `GGML_VK_MMV_MAX_COLS=16` | PPL = 6.3139 +/- 0.28430 | 5.11 s |

**Identical to every printed digit** — and the raised limit makes perplexity's own
chunked evaluation 1.6x faster as a side effect.

Raw: `raw/expP-*` in this folder. Harness: `../harness/expP-perplexity-ab.ps1`.
