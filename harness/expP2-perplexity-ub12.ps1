# Experiment P2 - the CORRECTED perplexity A/B, after ftoleedo's catch on PR
# 27652: llama-perplexity defaults to -ub 512, so every dispatch has
# ne[1] = 512 > 16 and the MMV path is never selected - the original expP was a
# null test (identical digits guaranteed). This run forces dispatches inside
# the window with -ub 12 -b 12: knob 8 -> matmul path, knob 12/16 -> MMV path.
# knob 12 vs 16 is the control (same kernel, must agree exactly).
$ErrorActionPreference = 'Continue'
$Bin = 'E:\work\llamacpp-knee\build\bin\llama-perplexity.exe'
$Model = 'E:\work\battlemage\models\Mistral-Small-3.2-24B-Instruct-2506-Q4_K_M.gguf'
$RES = 'E:\work\battlemage\burnin-2026-08\results'
$env:GGML_VK_VISIBLE_DEVICES = '1'
Remove-Item Env:GGML_VK_DISABLE_COOPMAT -ErrorAction SilentlyContinue

$srv = Get-Process llama-server, llama-batched-bench -ErrorAction SilentlyContinue
if ($srv) { Write-Host "ABORT: GPU co-tenant alive"; exit 2 }

$txt = Join-Path $RES 'expP-input.txt'
if (-not (Test-Path $txt)) { Write-Host 'ABORT: expP-input.txt missing'; exit 2 }

foreach ($mmv in 8, 12, 16) {
    $env:GGML_VK_MMV_MAX_COLS = "$mmv"
    $base = Join-Path $RES "expP2-mistral24b-ub12-mmv$mmv"
    $line = '"{0}" -m "{1}" -f "{2}" -ngl 999 -c 512 -ub 12 -b 12 --chunks 12 1> "{3}.txt" 2> "{3}.stderr.log"' -f $Bin, $Model, $txt, $base
    Set-Content -Path "$base.cmd" -Value $line -Encoding ascii
    Write-Host ">>> perplexity ub=12 mmv=$mmv"
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "$base.cmd" -PassThru -WindowStyle Hidden
    Wait-Process -Id $p.Id -Timeout 1800 -ErrorAction SilentlyContinue | Out-Null
    if (-not $p.HasExited) { Get-Process llama-perplexity -ErrorAction SilentlyContinue | Stop-Process -Force; Write-Host "    timeout" }
}
Remove-Item Env:GGML_VK_MMV_MAX_COLS -ErrorAction SilentlyContinue
$env:GGML_VK_VISIBLE_DEVICES = '1,2'
Write-Host '=== final PPL lines ==='
foreach ($mmv in 8, 12, 16) {
    $f = @((Join-Path $RES "expP2-mistral24b-ub12-mmv$mmv.stderr.log"), (Join-Path $RES "expP2-mistral24b-ub12-mmv$mmv.txt"))
    $ppl = Select-String -Path $f -Pattern 'Final estimate' -ErrorAction SilentlyContinue | Select-Object -Last 1
    Write-Host ("mmv={0}: {1}" -f $mmv, $(if ($ppl) { $ppl.Line.Trim() } else { 'NOT FOUND - inspect logs' }))
}
Write-Host '=== Experiment P2 complete ==='
