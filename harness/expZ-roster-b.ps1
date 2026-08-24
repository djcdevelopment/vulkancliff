# Experiment Z (continuation b, rev 2) - remaining roster legs, CO-TENANT-FREE, SPILL-AWARE.
# History: rev 1 of this run found gemma27 at -c 65536 demands ~42 GB (16.6 GB
# model + ~24 GB KV: gemma-3's cache is huge at depth) and VidMm silently
# spilled 10.3 GB to shared memory even with no co-tenant server - the same trap
# at a different threshold. A -c32k fallback that only fires on HARD failure
# cannot catch silent demotion, so this rev watches the PDH GPU Adapter Memory
# counters DURING the run and kills any leg whose B70 shared usage exceeds
# 2 GB on two consecutive probes (F1 admission-control convention, enforced).
# Each model gets a context ladder; a spilled or failed rung drops one step.
# The full B sweep needs N_KV = 32 x 640 = 20480, so 24576 is the floor.
$ErrorActionPreference = 'Continue'
$Bench = 'E:\work\llamacpp-knee\build\bin\llama-batched-bench.exe'
$RES = 'E:\work\battlemage\burnin-2026-08\results'
Remove-Item Env:GGML_VK_DISABLE_COOPMAT -ErrorAction SilentlyContinue
$stageStart = Get-Date
Write-Host "=== Experiment Z-b rev2 roster sweep start $(Get-Date -Format 'HH:mm:ss') ==="

# B70 adapter LUID fragments (PDH instance names); iGPU 1679b deliberately absent.
$B70Luids = @('0x000170ad', '0x00016be5')

$roster = @(
    @{ Tag='gemma27';  Vendor='Google';    Vis='1';   Extra=@();            TimeoutS=2400; Ladder=@(32768, 24576);        Model='E:\work\battlemage\models\gemma-3-27b-it-Q4_K_M.gguf' },
    @{ Tag='qwen32';   Vendor='Alibaba';   Vis='1';   Extra=@();            TimeoutS=2400; Ladder=@(32768, 24576);        Model='E:\work\battlemage\models\qwen2.5-32b-instruct-q4_K_M.gguf' },
    @{ Tag='mistral24';Vendor='Mistral';   Vis='1';   Extra=@();            TimeoutS=2400; Ladder=@(65536, 32768);        Model='E:\work\battlemage\models\Mistral-Small-3.2-24B-Instruct-2506-Q4_K_M.gguf' },
    @{ Tag='moe30';    Vendor='Alibaba';   Vis='1,2'; Extra=@('-ts','1,1'); TimeoutS=2400; Ladder=@(65536, 32768);        Model='E:\work\battlemage\models\Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf' },
    @{ Tag='llama70';  Vendor='Meta';      Vis='1,2'; Extra=@('-ts','1,1'); TimeoutS=3600; Ladder=@(32768, 24576);        Model='E:\work\battlemage\models\Llama-3.3-70B-Instruct-Q4_K_M.gguf' }
)

function Assert-NoCoTenant {
    $srv = Get-Process llama-server -ErrorAction SilentlyContinue
    if ($srv) {
        Write-Host ("ABORT: llama-server co-tenant alive (pid {0}) - results would be poisoned" -f ($srv.Id -join ','))
        exit 2
    }
}

function Get-B70SharedGB {
    # Max shared usage across the two B70s, in GB. 0 on any probe failure.
    try {
        $c = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop
        $vals = $c.CounterSamples | Where-Object {
            $p = $_.Path; ($B70Luids | Where-Object { $p -match $_ }).Count -gt 0
        } | ForEach-Object CookedValue
        if (@($vals).Count -eq 0) { return 0 }
        return [Math]::Round((($vals | Measure-Object -Maximum).Maximum) / 1GB, 2)
    } catch { return 0 }
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
    $deadline = (Get-Date).AddSeconds($TimeoutS)
    $grace = (Get-Date).AddSeconds(60)   # ignore load-time staging traffic
    $hits = 0
    while (-not $p.HasExited) {
        Start-Sleep -Seconds 20
        if ((Get-Date) -gt $deadline) {
            Get-Process -Name llama-batched-bench -ErrorAction SilentlyContinue | Stop-Process -Force
            return 'timeout'
        }
        if ((Get-Date) -gt $grace) {
            $shared = Get-B70SharedGB
            if ($shared -gt 2) { $hits++ } else { $hits = 0 }
            if ($hits -ge 2) {
                Get-Process -Name llama-batched-bench -ErrorAction SilentlyContinue | Stop-Process -Force
                Write-Host ("    SPILL detected ({0} GB shared) - killed" -f $shared)
                return 'spilled'
            }
        }
    }
    $ok = (Test-Path "$OutBase.txt") -and ((Get-Item "$OutBase.txt").Length -gt 500)
    if ($ok) { return 'ok' } else { return 'failed' }
}

$suffix = @{ 65536 = ''; 32768 = '-c32k'; 24576 = '-c24k' }

foreach ($m in $roster) {
    $env:GGML_VK_VISIBLE_DEVICES = $m.Vis
    foreach ($mmv in 8, 16) {
        $env:GGML_VK_MMV_MAX_COLS = "$mmv"
        Assert-NoCoTenant
        Wait-Cool
        Write-Host (">>> {0} ({1}) mmv={2}" -f $m.Tag, $m.Vendor, $mmv)
        $r = 'unrun'
        foreach ($ctx in $m.Ladder) {
            $base = Join-Path $RES ("expZ-{0}-mmv{1}{2}" -f $m.Tag, $mmv, $suffix[$ctx])
            $r = Invoke-BenchRun -OutBase $base -Model $m.Model -Extra $m.Extra -Ctx $ctx -TimeoutS $m.TimeoutS
            Write-Host ("    ctx {0}: {1}" -f $ctx, $r)
            if ($r -eq 'ok' -or $r -eq 'timeout') { break }
            # spilled/failed results are misleading - remove before the retry
            Remove-Item "$base.txt" -ErrorAction SilentlyContinue
        }
    }
}
Remove-Item Env:GGML_VK_MMV_MAX_COLS -ErrorAction SilentlyContinue
$env:GGML_VK_VISIBLE_DEVICES = '1,2'
$bad = @()
foreach ($f in @(
    @{LogName='System'; Id=4101; StartTime=$stageStart},
    @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$stageStart}
)) { try { $bad += @(Get-WinEvent -FilterHashtable $f -ErrorAction Stop) } catch {} }
Write-Host ("=== Experiment Z-b rev2 complete; events: {0} ===" -f $(if (@($bad).Count) { "$(@($bad).Count) - INSPECT" } else { 'CLEAN' }))
