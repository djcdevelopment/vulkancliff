# Experiment Z (continuation c) - the OpenAI slot, official ggml-org GGUF.
# The Ollama blob failed with unknown arch 'gptoss' (Ollama fork); this is the
# upstream-compatible gpt-oss-20b-MXFP4.gguf downloaded 2026-08-22. Same
# protocol and guard as expZ-roster-b.ps1. Runs AFTER the main sweep.
$ErrorActionPreference = 'Continue'
$Bench = 'E:\work\llamacpp-knee\build\bin\llama-batched-bench.exe'
$RES = 'E:\work\battlemage\burnin-2026-08\results'
Remove-Item Env:GGML_VK_DISABLE_COOPMAT -ErrorAction SilentlyContinue
$stageStart = Get-Date
Write-Host "=== Experiment Z-c (gptoss20 official) start $(Get-Date -Format 'HH:mm:ss') ==="

$roster = @(
    @{ Tag='gptoss20'; Vendor='OpenAI'; Vis='1'; Extra=@(); TimeoutS=2400; Model='E:\work\battlemage\models\gpt-oss-20b-MXFP4.gguf' }
)

function Assert-NoCoTenant {
    $srv = Get-Process llama-server -ErrorAction SilentlyContinue
    if ($srv) {
        Write-Host ("ABORT: llama-server co-tenant alive (pid {0}) - results would be poisoned" -f ($srv.Id -join ','))
        exit 2
    }
    $bench = @(Get-Process llama-batched-bench -ErrorAction SilentlyContinue)
    if ($bench.Count -gt 0) {
        Write-Host ("ABORT: another llama-batched-bench is running (pid {0}) - main sweep not finished" -f ($bench.Id -join ','))
        exit 2
    }
}

function Wait-Cool {
    foreach ($try in 1..40) {
        & 'E:\work\b70tools\build\b70tools.exe' --run --ticks 1 --cadence-ms 300 --no-sleep --out "$env:TEMP\cooldown-probe" 2>$null | Out-Null
        $t = Get-Content "$env:TEMP\cooldown-probe\events.jsonl" -ErrorAction SilentlyContinue |
             Where-Object { $_ -match 'gpu.temperature_c' } | ForEach-Object { ($_ | ConvertFrom-Json).v } |
             Measure-Object -Maximum
        if ($null -eq $t.Maximum -or $t.Maximum -lt 50) { return }
        Start-Sleep -Seconds 15
    }
}

function Invoke-BenchRun {
    param([string]$OutBase, [string]$Model, [string[]]$Extra, [int]$Ctx, [int]$TimeoutS)
    $extraStr = ($Extra -join ' ')
    $line = '"{0}" -m "{1}" -c {2} -ngl 999 -fa 1 {3} -npp 512 -ntg 128 -npl 1,2,4,6,8,9,10,12,16,24,32 1> "{4}.txt" 2> "{4}.stderr.log"' -f $Bench, $Model, $Ctx, $extraStr, $OutBase
    Set-Content -Path "$OutBase.cmd" -Value $line -Encoding ascii
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "$OutBase.cmd" -PassThru -WindowStyle Hidden
    Wait-Process -Id $p.Id -Timeout $TimeoutS -ErrorAction SilentlyContinue | Out-Null
    if (-not $p.HasExited) { Get-Process -Name llama-batched-bench -ErrorAction SilentlyContinue | Stop-Process -Force; return 'timeout' }
    $ok = (Test-Path "$OutBase.txt") -and ((Get-Item "$OutBase.txt").Length -gt 500)
    if ($ok) { return 'ok' } else { return 'failed' }
}

foreach ($m in $roster) {
    $env:GGML_VK_VISIBLE_DEVICES = $m.Vis
    foreach ($mmv in 8, 16) {
        $env:GGML_VK_MMV_MAX_COLS = "$mmv"
        Assert-NoCoTenant
        Wait-Cool
        $base = Join-Path $RES ("expZ-{0}-mmv{1}" -f $m.Tag, $mmv)
        Write-Host (">>> {0} ({1}) mmv={2}" -f $m.Tag, $m.Vendor, $mmv)
        $r = Invoke-BenchRun -OutBase $base -Model $m.Model -Extra $m.Extra -Ctx 65536 -TimeoutS $m.TimeoutS
        if ($r -eq 'failed') {
            Write-Host "    65536 failed - retrying at 32768"
            $r = Invoke-BenchRun -OutBase ($base + "-c32k") -Model $m.Model -Extra $m.Extra -Ctx 32768 -TimeoutS $m.TimeoutS
        }
        Write-Host "    $r"
    }
}
Remove-Item Env:GGML_VK_MMV_MAX_COLS -ErrorAction SilentlyContinue
$env:GGML_VK_VISIBLE_DEVICES = '1,2'
$bad = @()
foreach ($f in @(
    @{LogName='System'; Id=4101; StartTime=$stageStart},
    @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$stageStart}
)) { try { $bad += @(Get-WinEvent -FilterHashtable $f -ErrorAction Stop) } catch {} }
Write-Host ("=== Experiment Z-c complete; events: {0} ===" -f $(if (@($bad).Count) { "$(@($bad).Count) - INSPECT" } else { 'CLEAN' }))
