# build_sample.ps1 -- build the sample subset, PowerShell 5.1 /
# zero-dependency port of build_sample.py.
#
# Copies the first N epochs (default 100) of every diagnosis scenario folder (Healthy + 42
# single-fault + 46 multi-fault = 89 folders) from the release tree (the data root) into
# <out dir>\Sample\, preserving the release layout (multi-fault scenarios stay under their
# DIAG_DualFault / DIAG_TripleFault / DIAG_QuadFault group folders). The out dir must be OUTSIDE the
# data root (default build); the tool refuses otherwise and never writes into the data root.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File build_sample.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File build_sample.ps1 --data-root PATH --out-dir PATH --epochs 100
#   powershell -NoProfile -ExecutionPolicy Bypass -File build_sample.ps1 --dry-run

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SuperRoot = Split-Path -Parent $ScriptDir

$DataRootArg = $null
$OutDirArg   = $null
$Epochs      = 100
$DryRun      = $false

$rawArgs = $args
for ($i = 0; $i -lt $rawArgs.Count; $i++) {
    switch ($rawArgs[$i]) {
        '--data-root' { $DataRootArg = $rawArgs[++$i] }
        '--out-dir'   { $OutDirArg   = $rawArgs[++$i] }
        '--epochs'    { $Epochs      = [int]$rawArgs[++$i] }
        '--dry-run'   { $DryRun      = $true }
        default {
            Write-Host "WARNING: unrecognized argument '$($rawArgs[$i])' -- ignored." -ForegroundColor Yellow
        }
    }
}

# Naming scheme: folders DIAG_Healthy / DIAG_Fxx_<code> / DIAG_DualFault_<combo>...;
# files DIAG_<token>_E####.h5 (the file prefix is NOT the folder name). Codes come from
# <data root>\FaultReference\fault_catalogue.csv via release_naming.ps1.
. (Join-Path $ScriptDir 'release_naming.ps1')

# Measured per-record size ( figures table, decimal MB).
$MEASURED_MB_PER_RECORD = 0.3063

$dataRoot = Resolve-AvonDataRoot -CliValue $DataRootArg
$SCENARIOS = @(Get-Scenarios -DataRoot $dataRoot -Prefix 'DIAG_')
$outDir  = Resolve-AvonOutDir -CliValue $OutDirArg -DataRoot $dataRoot
$srcRoot = $dataRoot
$dstRoot = Join-Path $outDir 'Sample'

$items = New-Object System.Collections.Generic.List[object]
foreach ($sc in $SCENARIOS) {
    $folder = $sc.Folder
    for ($epoch = 1; $epoch -le $Epochs; $epoch++) {
        $fname = Get-DiagFilename -Prefix 'DIAG_' -Token $sc.Token -Epoch $epoch
        $items.Add([PSCustomObject]@{
            Folder = $folder; Epoch = $epoch
            Src = Join-Path (Join-Path $srcRoot $sc.RelDir) $fname
            Dst = Join-Path (Join-Path $dstRoot $sc.RelDir) $fname
        })
    }
}

Write-Host "Data root:        $dataRoot"
Write-Host "Source:            $srcRoot  (DIAG_* folders)"
Write-Host "Destination:       $dstRoot"
Write-Host "Scenario folders:  $($SCENARIOS.Count) (Healthy + 42 single + 46 multi)"
Write-Host "Epochs/scenario:   $Epochs"
Write-Host "Planned files:     $($items.Count)"
Write-Host ""
Write-Host "Note: 'exactly 20 per severity' is true for the 42"
Write-Host "single-fault scenarios only, not for Healthy or the 46 multi-fault combos."
Write-Host ""

$found = 0; $missing = 0; $copied = 0; $skippedExisting = 0; $foundBytes = [int64]0

foreach ($item in $items) {
    $exists = Test-Path -LiteralPath $item.Src -PathType Leaf
    if ($exists) {
        $found++
        $foundBytes += (Get-Item -LiteralPath $item.Src).Length
    } else {
        $missing++
        continue
    }

    if ($DryRun) { continue }

    if ((Test-Path -LiteralPath $item.Dst -PathType Leaf) -and
        ((Get-Item -LiteralPath $item.Dst).Length -eq (Get-Item -LiteralPath $item.Src).Length)) {
        $skippedExisting++
        continue
    }

    $dstDir = Split-Path -Parent $item.Dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $item.Src -Destination $item.Dst -Force
    $copied++
}

if ($foundBytes -gt 0) {
    $projectedMb = $foundBytes / 1MB
    $basis = 'measured (files found on disk)'
} else {
    $projectedMb = $items.Count * $MEASURED_MB_PER_RECORD
    $basis = 'projected (0.3063 MB/record -- no source files found yet)'
}
$projectedGb = $projectedMb / 1024

Write-Host "Source files found:    $found / $($items.Count)"
Write-Host "Source files missing:  $missing"
Write-Host ("Projected size:        {0:N3} GB  [{1}]" -f $projectedGb, $basis)

if ($DryRun) {
    Write-Host "`n--dry-run: nothing copied."
    exit 0
}

Write-Host "Copied:                $copied"
Write-Host "Skipped (already present, same size): $skippedExisting"
if ($missing -gt 0) {
    Write-Host "`nWARNING: $missing source file(s) not found -- Sample/ is partial until the diagnosis family finishes generating those records."
}
exit 0
