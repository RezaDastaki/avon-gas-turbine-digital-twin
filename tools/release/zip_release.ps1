# zip_release.ps1 -- build the release zips (release naming scheme).
# PowerShell 5.1 / zero-dependency twin of zip_release.py -- keep the two in lockstep.
#
# The Zenodo layout: exactly ONE zip per top-level folder of the release root (60 archives), plus
# Sample.zip, plus the loose files. Each zip is <folder>.zip and holds that folder as its top-level entry:
#   DIAG_Healthy.zip                        DIAG_Healthy\...
#   DIAG_Fxx_<code>.zip        x 42         DIAG_Fxx_<code>\...
#   DIAG_DualFault.zip                      DIAG_DualFault\DIAG_DualFault_<combo>\...   (21 scenarios)
#   DIAG_TripleFault.zip                    (14)
#   DIAG_QuadFault.zip                      (11)
#   RTF_Fxx_<code>.zip         x 13         RTF_Fxx_<code>\...
#   DiagnosisTurndown.zip                   DiagnosisTurndown\TD_<...>\...         (89 scenarios, flat)
#   Sample.zip                              Sample\<same layout as the release>\<file>
# Zips and the sample are written to an OUTPUT folder outside the data root (default build:
# <out>\zips\*.zip + MANIFEST.csv, <out>\Sample\); the tool refuses an out dir inside the data root.
# There is NO Code.zip (code is on GitHub).
#
# Loose (unzipped) upload files: README.md, the dataset-description PDF, fault_catalogue.csv,
# channel_dictionary.csv (paths: AVON_README_PATH / AVON_DESCRIPTION_PDF_PATH / AVON_CHANNEL_DICT_PATH
# in config.txt) and MANIFEST.csv, written here (zip_name, family, scenarios, record_count,
# bytes, sha256). A missing loose file is a WARNING in --list mode and a hard error in the uploader.
#
# Fault codes and RTF membership come from <repo>\FaultReference\fault_catalogue.csv
# (release_naming.ps1). Uses [System.IO.Compression] with CompressionLevel Optimal (deflate).
# The old shard filtering (moot) is not carried; this script and the Python
# twin both build the whole release.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File zip_release.ps1 --list [--data-root D] [--out-dir O]
#   powershell -NoProfile -ExecutionPolicy Bypass -File zip_release.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File zip_release.ps1 --only "RTF_*"
#   powershell -NoProfile -ExecutionPolicy Bypass -File zip_release.ps1 --measure PATH_TO_FOLDER
#   powershell -NoProfile -ExecutionPolicy Bypass -File zip_release.ps1 --list --as-json   # used by zenodo_upload.ps1

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'release_naming.ps1')
$ReleaseRoot = $RN_ReleaseRoot

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------
$DataRootArg   = $null
$OutDirArg     = $null
$ListFlag      = $false
$OnlyGlob      = $null
$NoTurndown    = $false
$StoredFlag    = $false
$MeasureFolder = $null
$AsJson        = $false

$rawArgs = $args
for ($i = 0; $i -lt $rawArgs.Count; $i++) {
    switch ($rawArgs[$i]) {
        '--data-root'    { $DataRootArg   = $rawArgs[++$i] }
        '--out-dir'      { $OutDirArg     = $rawArgs[++$i] }
        '--list'         { $ListFlag      = $true }
        '--only'         { $OnlyGlob      = $rawArgs[++$i] }
        '--no-turndown'  { $NoTurndown    = $true }
        '--stored'       { $StoredFlag    = $true }
        '--measure'      { $MeasureFolder = $rawArgs[++$i] }
        '--as-json'      { $AsJson        = $true }
        default {
            # Hard stop: an ignored typo (e.g. -h) used to fall through to a full zip build.
            Write-Host "ERROR: unrecognized argument '$($rawArgs[$i])'. Valid: --data-root <dir> --out-dir <dir> --list --only <glob> --no-turndown --stored --measure <folder> --as-json" -ForegroundColor Red
            exit 2
        }
    }
}

# ---------------------------------------------------------------------------
# Catalogue
# ---------------------------------------------------------------------------
function Build-ZipCatalog {
    # One entry per top-level folder of the data root (60), then Sample.zip, whose base is the
    # output folder (the sample is built there, never inside the data root). 'base' is the directory
    # the archive paths are relative to; source_subdirs are relative to it.
    param([string]$DataRoot, [string]$OutDir, [bool]$IncludeTurndown = $true)
    $cat = New-Object System.Collections.Generic.List[object]
    foreach ($e in (Get-TopLevelEntries -DataRoot $DataRoot)) {
        if ($e.Name -eq 'DiagnosisTurndown' -and -not $IncludeTurndown) { continue }
        $cat.Add([PSCustomObject]@{ zip_name = "$($e.Name).zip"; family = $e.Family; scenarios = @($e.Scenarios); base = $DataRoot; source_subdirs = @($e.Name) })
    }
    $cat.Add([PSCustomObject]@{ zip_name = 'Sample.zip'; family = 'Sample'; scenarios = @('Sample'); base = $OutDir; source_subdirs = @('Sample') })
    return $cat
}

# ---------------------------------------------------------------------------
# Hashing / file iteration
# ---------------------------------------------------------------------------
function Get-Sha256Hex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

function Get-FilesUnder {
    # (Full, Arc) pairs; Arc is relative to ArcBase with forward slashes.
    param([string]$RootDir, [string]$ArcBase)
    if (-not (Test-Path -LiteralPath $RootDir -PathType Container)) { return @() }
    $base = $ArcBase.TrimEnd('\', '/')
    return @(Get-ChildItem -LiteralPath $RootDir -Recurse -File | Sort-Object FullName | ForEach-Object {
        [PSCustomObject]@{ Full = $_.FullName; Arc = ($_.FullName.Substring($base.Length).TrimStart('\', '/') -replace '\\', '/') }
    })
}

function Get-EntryFiles {
    param($Entry)
    $files = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($sub in $Entry.source_subdirs) {
        $d = Join-Path $Entry.base $sub
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { $missing.Add($d); continue }
        foreach ($f in (Get-FilesUnder -RootDir $d -ArcBase $Entry.base)) { $files.Add($f) }
    }
    return @{ Files = $files; Missing = $missing }
}

function Test-ExistingZipMatchesSource {
    param([string]$ZipPath, $Files)
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { return $false }
    if ($Files.Count -eq 0) { return $false }
    $srcBytes = [int64]0
    foreach ($f in $Files) { $srcBytes += (Get-Item -LiteralPath $f.Full).Length }
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            $zipCount = $zip.Entries.Count
            $zipBytes = [int64]0
            foreach ($e in $zip.Entries) { $zipBytes += $e.Length }
        } finally { $zip.Dispose() }
    } catch { return $false }
    return ($zipCount -eq $Files.Count) -and ($zipBytes -eq $srcBytes)
}

function Build-OneZip {
    param([string]$ZipPath, $Files, [System.IO.Compression.CompressionLevel]$Level)
    $tmpPath = "$ZipPath.partial"
    if (Test-Path -LiteralPath $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($tmpPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $Files) {
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.Full, $f.Arc, $Level)
        }
    } finally { $zip.Dispose() }
    Move-Item -LiteralPath $tmpPath -Destination $ZipPath -Force
    return @{ NFiles = $Files.Count; Size = (Get-Item -LiteralPath $ZipPath).Length; Digest = (Get-Sha256Hex -Path $ZipPath) }
}

# ---------------------------------------------------------------------------
# --measure : stored vs deflated, on real data
# ---------------------------------------------------------------------------
function Measure-Compression {
    param([string]$Folder)
    $folder = [System.IO.Path]::GetFullPath($Folder)
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { Write-Host "Not a directory: $folder"; return 1 }
    $files = Get-FilesUnder -RootDir $folder -ArcBase $folder
    if ($files.Count -eq 0) { Write-Host "No files found under $folder"; return 1 }
    $rawTotal = ($files | ForEach-Object { (Get-Item -LiteralPath $_.Full).Length } | Measure-Object -Sum).Sum
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    try {
        $t0 = Get-Date
        $r1 = Build-OneZip -ZipPath (Join-Path $tmpDir 'stored.zip') -Files $files -Level ([System.IO.Compression.CompressionLevel]::NoCompression)
        $tStored = ((Get-Date) - $t0).TotalSeconds
        $t0 = Get-Date
        $r2 = Build-OneZip -ZipPath (Join-Path $tmpDir 'deflate.zip') -Files $files -Level ([System.IO.Compression.CompressionLevel]::Optimal)
        $tDeflate = ((Get-Date) - $t0).TotalSeconds
        $ratio = if ($r1.Size) { $r2.Size / $r1.Size } else { [double]::NaN }
        $pctSaved = (1 - $ratio) * 100
        Write-Host "Folder:          $folder"
        Write-Host "Files:           $($files.Count)"
        Write-Host "Raw bytes:       $rawTotal"
        Write-Host ("STORED   zip:    {0} bytes  ({1:N2}s)" -f $r1.Size, $tStored)
        Write-Host ("DEFLATED zip:    {0} bytes  ({1:N2}s)" -f $r2.Size, $tDeflate)
        Write-Host ("Deflate / stored ratio: {0:N6}  ({1:N2} % size change vs stored)" -f $ratio, $pctSaved)
        if ($pctSaved -gt 10) { Write-Host 'RESULT: deflate wins by more than 10% -- default should be DEFLATED for this data.' }
        else { Write-Host 'RESULT: deflate does NOT win by more than 10% -- STORED default stands.' }
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return 0
}

# ---------------------------------------------------------------------------
# release_files.py (read by the uploaders; same shape as the Python twin writes)
# ---------------------------------------------------------------------------
function Write-ReleaseFilesModule {
    param([string[]]$ExistingNames, $Loose, [string]$ZipsDir, [string]$OutPath, [int]$CatalogTotal)
    # No UploadToZenodo folder in this tree: there is no uploader to feed.
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $OutPath) -PathType Container)) { return }
    $q = { param($s) ConvertTo-Json -InputObject ([string]$s) -Compress }
    $namesJson = if ($ExistingNames.Count -eq 0) { '[]' } else { "[`n" + (($ExistingNames | ForEach-Object { '    ' + (& $q $_) }) -join ",`n") + "`n]" }
    $looseJson = "{`n" + (($Loose | ForEach-Object { '    ' + (& $q $_.Name) + ': ' + (& $q $_.Path) }) -join ",`n") + "`n}"
    $body = @"
"""release_files.py -- AUTO-GENERATED by tools/release/zip_release.ps1 (or .py). Do not hand-edit.

RELEASE_FILES: the zips that ACTUALLY EXIST in ZIPS_DIR as of the last zip_release run
(--list included), so the uploader never queues a zip that is not there yet. The full catalogue
is $CatalogTotal archives; run 'zip_release --list' to see it.
LOOSE_FILES: the unzipped upload files (name -> absolute path), whether or not they exist yet;
the uploader FAILS in upload mode if any is missing.
"""

ZIPS_DIR = $(& $q $ZipsDir)

RELEASE_FILES = $namesJson

LOOSE_FILES = $looseJson
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutPath, ($body -replace "`r`n", "`n") + "`n", $utf8NoBom)
}

function Update-ReleaseFiles {
    param($CatalogFull, $Loose, [string]$ZipsDir, [string]$ReleaseFilesPath)
    $existing = @($CatalogFull | Where-Object { Test-Path -LiteralPath (Join-Path $ZipsDir $_.zip_name) -PathType Leaf } | ForEach-Object { $_.zip_name })
    Write-ReleaseFilesModule -ExistingNames $existing -Loose $Loose -ZipsDir $ZipsDir -OutPath $ReleaseFilesPath -CatalogTotal $CatalogFull.Count
    return $existing
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
if ($MeasureFolder) { exit (Measure-Compression -Folder $MeasureFolder) }

$dataRoot    = Resolve-AvonDataRoot -CliValue $DataRootArg
$outDir      = Resolve-AvonOutDir -CliValue $OutDirArg -DataRoot $dataRoot
$zipsDir     = Join-Path $outDir 'zips'
$fullCatalog = @(Build-ZipCatalog -DataRoot $dataRoot -OutDir $outDir -IncludeTurndown $true)
$catalog     = @(Build-ZipCatalog -DataRoot $dataRoot -OutDir $outDir -IncludeTurndown (-not $NoTurndown))
if ($OnlyGlob) { $catalog = @($catalog | Where-Object { $_.zip_name -like $OnlyGlob }) }
$loose = @(Get-LooseFiles -DataRoot $dataRoot -ZipsDir $zipsDir)
$releaseFilesPath = Join-Path $ReleaseRoot 'UploadToZenodo\release_files.py'
$existingNow = Update-ReleaseFiles -CatalogFull $fullCatalog -Loose $loose -ZipsDir $zipsDir -ReleaseFilesPath $releaseFilesPath

if ($ListFlag) {
    if ($AsJson) {
        $obj = [PSCustomObject]@{
            data_root = $dataRoot
            entries   = @($catalog | ForEach-Object { [PSCustomObject]@{ zip_name = $_.zip_name; family = $_.family; base = $_.base; source_subdirs = @($_.source_subdirs) } })
            loose     = @($loose | ForEach-Object { [PSCustomObject]@{ name = $_.Name; path = $_.Path } })
        }
        $obj | ConvertTo-Json -Depth 5 -Compress
        exit 0
    }
    Write-Host "Data root: $dataRoot"
    Write-Host "Out dir:   $outDir"
    Write-Host "Zips dir:  $zipsDir"
    Write-Host "Archives in CATALOGUE: $($catalog.Count)"
    $byFamily = [ordered]@{}
    foreach ($c in $catalog) { $byFamily[$c.family] = ([int]$byFamily[$c.family]) + 1 }
    foreach ($fam in $byFamily.Keys) { Write-Host "  $fam`: $($byFamily[$fam])" }
    foreach ($c in $catalog) { Write-Host "  [zip]   $($c.zip_name)  ($($c.scenarios.Count) folder(s))" }
    Write-Host "Loose files: $($loose.Count)"
    $nMissing = 0
    foreach ($l in $loose) {
        $ok = Test-Path -LiteralPath $l.Path -PathType Leaf
        if (-not $ok) { $nMissing++ }
        $suffix = if ($ok) { '' } else { '   WARNING: NOT FOUND' }
        Write-Host "  [loose] $($l.Name)  <- $($l.Path)  [$($l.How)]$suffix"
    }
    Write-Host "TOTAL catalogue entries: $($catalog.Count + $loose.Count) ($($catalog.Count) archives + $($loose.Count) loose files)"
    if ($nMissing -gt 0) { Write-Host "WARNING: $nMissing loose file(s) missing -- the uploader will refuse to upload until they exist." }
    Write-Host "`n$($existingNow.Count) zip(s) found on disk (of $($fullCatalog.Count) in the full catalogue)"
    exit 0
}

$level = if ($StoredFlag) { [System.IO.Compression.CompressionLevel]::NoCompression } else { [System.IO.Compression.CompressionLevel]::Optimal }
if (-not (Test-Path -LiteralPath $zipsDir)) { New-Item -ItemType Directory -Path $zipsDir -Force | Out-Null }

$manifestPath = Join-Path $zipsDir 'MANIFEST.csv'
$manifestRows = New-Object System.Collections.Generic.List[object]
$built = 0; $skipped = 0; $missingSource = 0

foreach ($entry in $catalog) {
    $zipName = $entry.zip_name
    $zipPath = Join-Path $zipsDir $zipName
    $ef = Get-EntryFiles -Entry $entry
    $files = $ef.Files
    if ($ef.Missing.Count -gt 0 -or $files.Count -eq 0) {
        $missingSource++
        $eg = if ($ef.Missing.Count -gt 0) { $ef.Missing[0] } else { 'no files' }
        Write-Host "[skip] $zipName`: source not found ($($ef.Missing.Count) missing folder(s), e.g. $eg)"
        continue
    }
    if (Test-ExistingZipMatchesSource -ZipPath $zipPath -Files $files) {
        $skipped++
        Write-Host "[skip-exists] $zipName  size=$((Get-Item -LiteralPath $zipPath).Length)"
    } else {
        $r = Build-OneZip -ZipPath $zipPath -Files $files -Level $level
        $built++
        Write-Host "[built] $zipName  files=$($r.NFiles)  size=$($r.Size)  sha256=$($r.Digest.Substring(0,12))..."
    }
    $nScen = if ($entry.family -eq 'Sample') { 89 } else { $entry.scenarios.Count }
    $manifestRows.Add([PSCustomObject]@{
        zip_name = $zipName; family = $entry.family; scenarios = $nScen
        record_count = @($files | Where-Object { $_.Arc.EndsWith('.h5') }).Count
        bytes = (Get-Item -LiteralPath $zipPath).Length
        sha256 = Get-Sha256Hex -Path $zipPath
    })
}

$csvLines = New-Object System.Collections.Generic.List[string]
$csvLines.Add('zip_name,family,scenarios,record_count,bytes,sha256')
foreach ($row in $manifestRows) {
    $csvLines.Add("$($row.zip_name),$($row.family),$($row.scenarios),$($row.record_count),$($row.bytes),$($row.sha256)")
}
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($manifestPath, ($csvLines -join "`r`n") + "`r`n", $utf8NoBom)

[void](Update-ReleaseFiles -CatalogFull $fullCatalog -Loose $loose -ZipsDir $zipsDir -ReleaseFilesPath $releaseFilesPath)

Write-Host "`nBuilt: $built  Skipped (already correct): $skipped  Missing source: $missingSource"
Write-Host "Manifest: $manifestPath"
exit 0
