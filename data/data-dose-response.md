# Dataset: dose-response (expY)

Mistral-Small-3.2-24B-Instruct Q4_K_M, one Arc Pro B70 (`GGML_VK_VISIBLE_DEVICES=1`),
`llama-batched-bench -c 65536 -ngl 999 -fa 1 -npp 512 -ntg 128 -npl 1,2,4,6,8,9,10,12,16,24,32`,
same patched binary, only `GGML_VK_MMV_MAX_COLS` changes. Two reps per limit; rep 1 pays the
first-use pipeline-compile tax for each new column count, so **rep 2 (warm) is the citable set**.
Cool-start gated (<50 C), no co-tenant, no VRAM spill (PDH-verified).

## Aggregate decode S_TG (tok/s), warm rep 2

| B | limit 4 | limit 8 | limit 16 |
|---|---|---|---|
| 1 | 30.53 | 30.47 | 30.50 |
| 2 | 47.02 | 46.93 | 46.99 |
| 4 | 78.30 | 78.20 | 78.36 |
| 6 | 23.34 | 106.37 | 106.97 |
| 8 | 29.85 | 124.96 | 125.19 |
| 9 | 19.72 | 19.71 | 131.47 |
| 10 | 22.45 | 22.44 | 137.87 |
| 12 | 29.41 | 29.37 | 147.41 |
| 16 | 45.48 | 45.40 | 158.52 |
| 24 | 92.35 | 92.08 | 92.30 |
| 32 | 140.14 | 139.53 | 139.52 |

## Same, rep 1 (cold/warmup - for completeness)

| B | limit 4 | limit 8 | limit 16 |
|---|---|---|---|
| 1 | 28.62 | 30.49 | 30.49 |
| 2 | 47.39 | 46.98 | 46.96 |
| 4 | 78.87 | 78.16 | 78.24 |
| 6 | 22.82 | 88.70 | 106.60 |
| 8 | 29.86 | 98.18 | 125.18 |
| 9 | 19.72 | 19.71 | 105.36 |
| 10 | 22.45 | 22.44 | 107.37 |
| 12 | 29.41 | 29.38 | 110.30 |
| 16 | 45.46 | 45.42 | 158.49 |
| 24 | 92.31 | 92.14 | 92.19 |
| 32 | 139.85 | 139.58 | 139.45 |

## Readings

- The cliff lands at the first sampled batch past each limit: 4 -> 6, 8 -> 9, 16 -> 24.
- Off-cliff values agree across all three limits to within noise (same matmul floor).
- MMV path at B=16 (158.5) beats the matmul path at B=32 (139.5).
- 9th-thread recovery at limit 16: 19.71 -> 131.47 (x6.7). B=16: 45.40 -> 158.52 (x3.5).
- Both reps agree on every knee location (rep 1 only depresses first-use rows).

Raw: `raw/expY-mistral24b-mmv{4,8,16}-rep{1,2}.txt` in this folder.
