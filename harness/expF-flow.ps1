# Experiment F - FRAME PACING: the gamer's view of the knee. 200 requests at
# concurrency 10 (right ON the stock cliff), per-request latency persisted like a
# frame-time trace. Stock (mmv=8) vs patched (mmv=16), same binary, same model.
# Outputs per-request JSONL -> median / p95 / p99 / 1%-low / stutter count
# (stutter = request slower than 2x the config's own median).
param([int]$Requests = 200, [int]$Conc = 10)
$ErrorActionPreference = 'Continue'
$Bin = 'E:\work\llamacpp-knee\build\bin\llama-server.exe'
$Model = 'E:\work\battlemage\models\Mistral-Small-3.2-24B-Instruct-2506-Q4_K_M.gguf'
$RES = 'E:\work\battlemage\burnin-2026-08\results'
$env:GGML_VK_VISIBLE_DEVICES = '1'
Remove-Item Env:GGML_VK_DISABLE_COOPMAT -ErrorAction SilentlyContinue
$stageStart = Get-Date
Write-Host "=== Experiment F frame-pacing start $(Get-Date -Format 'HH:mm:ss') ==="

# Co-tenant guard (the gemma27 lesson): no other VRAM holder may be alive.
$srv = Get-Process llama-server -ErrorAction SilentlyContinue
if ($srv) { Write-Host ("ABORT: llama-server co-tenant alive (pid {0})" -f ($srv.Id -join ',')); exit 2 }

function Get-B70SharedGB {
    try {
        $c = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop
        $vals = $c.CounterSamples | Where-Object { $_.Path -match '0x000170ad|0x00016be5' } | ForEach-Object CookedValue
        if (@($vals).Count -eq 0) { return 0 }
        return [Math]::Round((($vals | Measure-Object -Maximum).Maximum) / 1GB, 2)
    } catch { return 0 }
}

foreach ($mmv in 8, 16) {
    $env:GGML_VK_MMV_MAX_COLS = "$mmv"
    $outJl = Join-Path $RES "expF-mistral24b-mmv$mmv.jsonl"
    Remove-Item $outJl -ErrorAction SilentlyContinue
    Write-Host ">>> mmv=$mmv : starting server (-np $Conc)"
    # 4096/slot: requests use ~350 tokens; 8192/slot would put the model at
    # ~30.5 GB - the silent-spill zone that poisoned gemma27/qwen32 at 65k.
    $ctx = 4096 * $Conc
    $slog = Join-Path $RES "expF-server-mmv$mmv"
    $sp = Start-Process -FilePath $Bin -ArgumentList @('-m',$Model,'-ngl','99','-fa','on','--no-mmap','-fit','off','-c',"$ctx",'-np',"$Conc",'--port','8094','--slots') `
        -RedirectStandardOutput "$slog.stdout.log" -RedirectStandardError "$slog.stderr.log" -PassThru -WindowStyle Hidden
    $ready = $false
    foreach ($i in 1..120) {
        Start-Sleep -Seconds 3
        if ($sp.HasExited) { break }
        try { if ((Invoke-WebRequest -Uri 'http://127.0.0.1:8094/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ready = $true; break } } catch {}
    }
    if (-not $ready) { Write-Host "  mmv=$mmv server failed"; if (-not $sp.HasExited) { Stop-Process -Id $sp.Id -Force }; continue }
    Write-Host "  healthy; warmup wave"

    $body = Join-Path $env:TEMP "expF-body.json"
    $prompt = ("The wind over the steppe carries the sound of engines and old fires. " * 12).Trim()
    @{ prompt = $prompt; n_predict = 200 } | ConvertTo-Json -Compress | Out-File -Encoding ascii $body

    # warmup: one full-concurrency wave, discarded (pipeline first-use tax)
    $warm = @()
    foreach ($i in 1..$Conc) {
        $o = Join-Path $env:TEMP "expF-warm-$i.json"
        $warm += Start-Process -FilePath 'C:\Windows\system32\curl.exe' -ArgumentList @('-s','-m','900','-X','POST','-H','Content-Type: application/json','-d',"@$body",'http://127.0.0.1:8094/completion') -RedirectStandardOutput $o -PassThru -WindowStyle Hidden
    }
    $warm | Wait-Process -Timeout 900 -ErrorAction SilentlyContinue

    # spill assert: server allocation is static after load, one check suffices
    $shared = Get-B70SharedGB
    if ($shared -gt 2) {
        Write-Host ("  ABORT mmv=$mmv leg: SPILL ({0} GB shared) - data would be poisoned" -f $shared)
        Stop-Process -Id $sp.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        continue
    }
    Write-Host ("  no spill ({0} GB shared); measured waves begin" -f $shared)

    # measured waves
    $waves = [math]::Ceiling($Requests / $Conc)
    $reqIdx = 0
    try {
        foreach ($w in 1..$waves) {
            $procs = @(); $outs = @()
            foreach ($i in 1..$Conc) {
                $o = Join-Path $env:TEMP "expF-r-$w-$i.json"
                $outs += $o
                $procs += Start-Process -FilePath 'C:\Windows\system32\curl.exe' -ArgumentList @('-s','-m','900','-X','POST','-H','Content-Type: application/json','-d',"@$body",'http://127.0.0.1:8094/completion') -RedirectStandardOutput $o -PassThru -WindowStyle Hidden
            }
            $procs | Wait-Process -Timeout 900 -ErrorAction SilentlyContinue
            $procs | Where-Object { -not $_.HasExited } | Stop-Process -Force -ErrorAction SilentlyContinue
            foreach ($o in $outs) {
                try {
                    $j = Get-Content $o -Raw -ErrorAction Stop | ConvertFrom-Json
                    if ($j.timings) {
                        $reqIdx++
                        @{ i = $reqIdx; wave = $w
                           total_s = [math]::Round(($j.timings.prompt_ms + $j.timings.predicted_ms)/1000, 3)
                           tg_tok_s = [math]::Round($j.timings.predicted_per_second, 2)
                           pp_ms = [math]::Round($j.timings.prompt_ms, 1)
                           n_gen = $j.timings.predicted_n } | ConvertTo-Json -Compress | Add-Content -Path $outJl -Encoding utf8
                    }
                } catch {}
                Remove-Item $o -ErrorAction SilentlyContinue
            }
            if ($w % 5 -eq 0) { Write-Host "  wave $w/$waves ($reqIdx requests logged)" }
        }
    } finally {
        Stop-Process -Id $sp.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
    Write-Host "  mmv=$mmv complete: $reqIdx requests -> $outJl"
}
Remove-Item Env:GGML_VK_MMV_MAX_COLS -ErrorAction SilentlyContinue
$env:GGML_VK_VISIBLE_DEVICES = '1,2'
$bad = @()
foreach ($f in @(
    @{LogName='System'; Id=4101; StartTime=$stageStart},
    @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$stageStart}
)) { try { $bad += @(Get-WinEvent -FilterHashtable $f -ErrorAction Stop) } catch {} }
Write-Host ("=== Experiment F complete; events: {0} ===" -f $(if (@($bad).Count) { "$(@($bad).Count) - INSPECT" } else { 'CLEAN' }))
