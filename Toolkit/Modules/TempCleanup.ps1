# Temp file cleanup with freed-space reporting.
function Invoke-TempCleanup {
    param([string]$Target, [bool]$IsWinPE)

    $targets = @("$Target\Windows\Temp",
                 "$Target\Windows\SoftwareDistribution\Download")
    if ($IsWinPE) {
        # All user temp folders on the offline installation.
        $targets += Get-ChildItem "$Target\Users" -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { "$($_.FullName)\AppData\Local\Temp" }
    } else {
        $targets += $env:TEMP
    }

    $freed = 0L
    foreach ($t in $targets) {
        if (-not (Test-Path $t)) { continue }
        $items = Get-ChildItem $t -Force -ErrorAction SilentlyContinue
        $before = (Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue |
                   Where-Object { -not $_.PSIsContainer } |
                   Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
        # Files in use simply fail to delete and are skipped — that's expected and safe.
        $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $remaining = (Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue |
                      Where-Object { -not $_.PSIsContainer } |
                      Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
        $delta = [Math]::Max(0, ($before - $remaining))
        $freed += $delta
        Write-RLog ("  {0}: freed {1:N1} MB" -f $t, ($delta / 1MB))
    }

    if (-not $IsWinPE) {
        try { Clear-RecycleBin -Force -ErrorAction Stop; Write-RLog '  Recycle bin emptied.' } catch { }
    }
    Write-RLog ("Temp cleanup complete — total freed: {0:N1} MB (locked in-use files are skipped)." -f ($freed / 1MB))
}
