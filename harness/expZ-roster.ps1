# Experiment Z - the name-brand roster sweep: 7 models x {mmv 8 stock, mmv 16},
# thread-protocol batched-bench. The article's chart: "Win11 + Intel B70 + [name]".
# Single-card for everything except the 70B (dual, labeled secondary).
# A 65536-ctx alloc failure retries at 32768 (tagged in the filename).
$ErrorActionPreference = 'Continue'
$Bench = 'E:\work\llamacpp-knee\build\bin\llama-batched-bench.exe'
$RES = 'E:\work\battlemage\burnin-2026-08\results'
Remove-Item Env:GGML_VK_DISABLE_COOPMAT -ErrorAction SilentlyContinue
$stageStart = Get-Date
Write-Host "=== Experiment Z roster sweep start $(Get-Date -Format 'HH:mm:ss') ==="

$roster = @(
    @{ Tag='phi4';     Vendor='Microsoft'; Vis='1';   Extra=@();            Model='E:\work\battlemage\models\phi-4-Q4_K_M.gguf' },
    @{ Tag='gemma27';  Vendor='Google';    Vis='1';   Extra=@();            Model='E:\work\battlemage\models\gemma-3-27b-it-Q4_K_M.gguf' },
    @{ Tag='gptoss20'; Vendor='OpenAI';    Vis='1';   Extra=@();            Model='E:\work\models\blobs\sha256-e7b273f9636059a689e3ddcab3716e4f65abe0143ac978e46673ad0e52d09efb' },
    @{ Tag='qwen32';   Vendor='Alibaba';   Vis='1';   Extra=@();            Model='E:\work\battlemage\models\qwen2.5-32b-instruct-q4_K_M.gguf' },
    @{ Tag='moe30';    Vendor='Alibaba';   Vis='1,2'; Extra=@('-ts','1,1'); Model='E:\work\battlemage\models\Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf' },
    @{ Tag='mistral24';Vendor='Mistral';   Vis='1';   Extra=@();            Model='E:\work\battlemage\models\Mistral-Small-3.2-24B-Instruct-2506-Q4_K_M.gguf' },
    @{ Tag='llama70';  Vendor='Meta';      Vis='1,2'; Extra=@('-ts','1,1'); Model='E:\work\battlemage\models\Llama-3.3-70B-Instruct-Q4_K_M.gguf' }
)

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
    param([string]$OutBase, [string]$Model, [string[]]$Extra, [int]$Ctx)
    $extraStr = ($Extra -join ' ')
    $line = '"{0}" -m "{1}" -c {2} -ngl 999 -fa 1 {3} -npp 512 -ntg 128 -npl 1,2,4,6,8,9,10,12,16,24,32 1> "{4}.txt" 2> "{4}.stderr.log"' -f $Bench, $Model, $Ctx, $extraStr, $OutBase
    Set-Content -Path "$OutBase.cmd" -Value $line -Encoding ascii
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "$OutBase.cmd" -PassThru -WindowStyle Hidden
    Wait-Process -Id $p.Id -Timeout 2400 -ErrorAction SilentlyContinue | Out-Null
    if (-not $p.HasExited) { Get-Process -Name llama-batched-bench -ErrorAction SilentlyContinue | Stop-Process -Force; return 'timeout' }
    $ok = (Test-Path "$OutBase.txt") -and ((Get-Item "$OutBase.txt").Length -gt 500)
    if ($ok) { return 'ok' } else { return 'failed' }
}

foreach ($m in $roster) {
    $env:GGML_VK_VISIBLE_DEVICES = $m.Vis
    foreach ($mmv in 8, 16) {
        $env:GGML_VK_MMV_MAX_COLS = "$mmv"
        Wait-Cool
        $base = Join-Path $RES ("expZ-{0}-mmv{1}" -f $m.Tag, $mmv)
        Write-Host (">>> {0} ({1}) mmv={2}" -f $m.Tag, $m.Vendor, $mmv)
        $r = Invoke-BenchRun -OutBase $base -Model $m.Model -Extra $m.Extra -Ctx 65536
        if ($r -eq 'failed') {
            Write-Host "    65536 failed - retrying at 32768"
            $r = Invoke-BenchRun -OutBase ($base + "-c32k") -Model $m.Model -Extra $m.Extra -Ctx 32768
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
Write-Host ("=== Experiment Z complete; events: {0} ===" -f $(if (@($bad).Count) { "$(@($bad).Count) - INSPECT" } else { 'CLEAN' }))
