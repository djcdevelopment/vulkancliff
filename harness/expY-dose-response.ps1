# Experiment Y - THE DOSE-RESPONSE: one patched binary, GGML_VK_MMV_MAX_COLS in {4,8,16},
# thread-protocol batched-bench on a dense single-card model. Prediction: the throughput
# knee lands at exactly the env value in each run. Protocol matches llama.cpp issue
# #25356 for direct comparability: -c 65536 -ngl 999 -fa 1 -npp 512 -ntg 128, B swept.
param(
    [string]$Model = 'E:\work\battlemage\models\Mistral-Small-3.2-24B-Instruct-2506-Q4_K_M.gguf',
    [string]$Tag = 'mistral24b',
    [int]$Reps = 2
)
$ErrorActionPreference = 'Continue'
$Bench = 'E:\work\llamacpp-knee\build\bin\llama-batched-bench.exe'
$RES = 'E:\work\battlemage\burnin-2026-08\results'
$env:GGML_VK_VISIBLE_DEVICES = '1'    # ONE card; iGPU is Vulkan0 on this box
Remove-Item Env:GGML_VK_DISABLE_COOPMAT -ErrorAction SilentlyContinue
$stageStart = Get-Date
Write-Host "=== Experiment Y dose-response ($Tag) start $(Get-Date -Format 'HH:mm:ss') ==="

function Wait-Cool {
    # thread norm: start each leg below 50 C (GPU core, the sail makes this quick)
    foreach ($try in 1..40) {
        $out = & 'E:\work\b70tools\build\b70tools.exe' --run --ticks 1 --cadence-ms 300 --no-sleep --out "$env:TEMP\cooldown-probe" 2>$null
        $t = Get-Content "$env:TEMP\cooldown-probe\events.jsonl" -ErrorAction SilentlyContinue |
             Where-Object { $_ -match 'gpu.temperature_c' } | ForEach-Object { ($_ | ConvertFrom-Json).v } |
             Measure-Object -Maximum
        if ($null -eq $t.Maximum -or $t.Maximum -lt 50) { Write-Host "  (cool: $($t.Maximum) C)"; return }
        Write-Host "  (cooling: $($t.Maximum) C)"; Start-Sleep -Seconds 15
    }
}

foreach ($mmv in 4, 8, 16) {
    $env:GGML_VK_MMV_MAX_COLS = "$mmv"
    foreach ($rep in 1..$Reps) {
        Wait-Cool
        $out = Join-Path $RES ("expY-{0}-mmv{1}-rep{2}" -f $Tag, $mmv, $rep)
        Write-Host ">>> mmv=$mmv rep=$rep"
        $line = '"{0}" -m "{1}" -c 65536 -ngl 999 -fa 1 -npp 512 -ntg 128 -npl 1,2,4,6,8,9,10,12,16,24,32 1> "{2}.txt" 2> "{2}.stderr.log"' -f $Bench, $Model, $out
        $cmdFile = "$out.cmd"
        Set-Content -Path $cmdFile -Value $line -Encoding ascii
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmdFile -PassThru -WindowStyle Hidden
        Wait-Process -Id $p.Id -Timeout 2400 -ErrorAction SilentlyContinue | Out-Null
        if (-not $p.HasExited) { Get-Process -Name llama-batched-bench -ErrorAction SilentlyContinue | Stop-Process -Force; Write-Host "    TIMEOUT (40m)" }
        else { Write-Host "    done ($((Get-Item ""$out.txt"" -ErrorAction SilentlyContinue).Length) bytes)" }
    }
}
Remove-Item Env:GGML_VK_MMV_MAX_COLS -ErrorAction SilentlyContinue
$env:GGML_VK_VISIBLE_DEVICES = '1,2'
$bad = @()
foreach ($f in @(
    @{LogName='System'; Id=4101; StartTime=$stageStart},
    @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$stageStart}
)) { try { $bad += @(Get-WinEvent -FilterHashtable $f -ErrorAction Stop) } catch {} }
Write-Host ("=== Experiment Y complete; events: {0} ===" -f $(if (@($bad).Count) { "$(@($bad).Count) - INSPECT" } else { 'CLEAN' }))
