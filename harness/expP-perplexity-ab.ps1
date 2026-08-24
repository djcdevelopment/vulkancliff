# Experiment P - perplexity A/B: env GGML_VK_MMV_MAX_COLS 8 vs 16, same binary,
# same text, same seed-free deterministic eval. The dispatch knob changes WHICH
# kernel runs, not the math; test-backend-ops already proves kernel correctness
# vs CPU reference. This is the reviewer-facing cross-check: final PPL must
# match (bit-identical if chunk tails never differ in dispatch; otherwise equal
# to reported precision - report exactly what is observed).
$ErrorActionPreference = 'Continue'
$Bin = 'E:\work\llamacpp-knee\build\bin\llama-perplexity.exe'
$Model = 'E:\work\battlemage\models\Mistral-Small-3.2-24B-Instruct-2506-Q4_K_M.gguf'
$RES = 'E:\work\battlemage\burnin-2026-08\results'
$env:GGML_VK_VISIBLE_DEVICES = '1'
Remove-Item Env:GGML_VK_DISABLE_COOPMAT -ErrorAction SilentlyContinue

$srv = Get-Process llama-server, llama-batched-bench -ErrorAction SilentlyContinue
if ($srv) { Write-Host "ABORT: GPU co-tenant alive"; exit 2 }

# Build a ~200 KB deterministic text input from the clone's own docs.
$txt = Join-Path $RES 'expP-input.txt'
if (-not (Test-Path $txt)) {
    Get-ChildItem 'E:\work\llamacpp-knee\docs' -Recurse -Filter *.md |
        Sort-Object FullName | Get-Content -Raw |
        Out-File -FilePath $txt -Encoding utf8
}
Write-Host ("input: {0} bytes" -f (Get-Item $txt).Length)

foreach ($mmv in 8, 16) {
    $env:GGML_VK_MMV_MAX_COLS = "$mmv"
    $base = Join-Path $RES "expP-mistral24b-mmv$mmv"
    $line = '"{0}" -m "{1}" -f "{2}" -ngl 999 --chunks 12 1> "{3}.txt" 2> "{3}.stderr.log"' -f $Bin, $Model, $txt, $base
    Set-Content -Path "$base.cmd" -Value $line -Encoding ascii
    Write-Host ">>> perplexity mmv=$mmv"
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "$base.cmd" -PassThru -WindowStyle Hidden
    Wait-Process -Id $p.Id -Timeout 1800 -ErrorAction SilentlyContinue | Out-Null
    if (-not $p.HasExited) { Get-Process llama-perplexity -ErrorAction SilentlyContinue | Stop-Process -Force; Write-Host "    timeout" }
}
Remove-Item Env:GGML_VK_MMV_MAX_COLS -ErrorAction SilentlyContinue
$env:GGML_VK_VISIBLE_DEVICES = '1,2'
Write-Host '=== final PPL lines ==='
foreach ($mmv in 8, 16) {
    $f = Join-Path $RES "expP-mistral24b-mmv$mmv.stderr.log"
    $ppl = Select-String -Path $f, (Join-Path $RES "expP-mistral24b-mmv$mmv.txt") -Pattern 'Final estimate|PPL' -ErrorAction SilentlyContinue | Select-Object -Last 1
    Write-Host ("mmv={0}: {1}" -f $mmv, $(if ($ppl) { $ppl.Line.Trim() } else { 'NOT FOUND - inspect logs' }))
}
Write-Host '=== Experiment P complete ==='
