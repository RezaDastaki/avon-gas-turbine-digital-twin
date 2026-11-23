# release_naming.ps1 -- the release's naming grammar, dot-sourced by zip_release.ps1 and
# build_sample.ps1. PowerShell mirror of release_naming.py (keep the two in lockstep).
#
# Release layout (2026-11-23; must match GenerateScenarioInfo.m / RTFUnitPath.m). The data root IS
# the release tree:
#   <root>\DIAG_Healthy\DIAG_Healthy_E0001.h5
#   <root>\DIAG_F01_<code>\DIAG_F01_E0001.h5                          (42 single-fault folders)
#   <root>\DIAG_DualFault\DIAG_DualFault_F01F05\DIAG_F01F05_E0001.h5  (DIAG_TripleFault\, DIAG_QuadFault\)
#   <root>\RTF_F02_<code>\RTF_F02_U0001.h5 (+ _refchecks.csv)
#   <root>\DiagnosisTurndown\TD_Healthy\..., TD_DualFault_F01F05\TD_F01F05_E100001.h5  (turndown NOT grouped)
# One zip per top-level folder of the root: 60 archives (Get-TopLevelEntries) plus Sample.zip.
# Fault <code> tokens and RTF membership are read from fault_catalogue.csv (fault_id, code,
# rtf_member) at <repo>\FaultReference\fault_catalogue.csv (fallback <data root>\FaultReference\),
# not hand-maintained here. The 46
# multi-fault combinations are not in the catalogue, so they stay as a table (asserted for shape).

$RN_ToolsDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$RN_ReleaseRoot = Split-Path -Parent (Split-Path -Parent $RN_ToolsDir)   # repository root (tools\release -> two levels up)

$RN_DualCombos = @('F01F05','F02F26','F03F32','F04F19','F06F42','F07F40','F08F16',
    'F09F25','F10F41','F11F17','F12F30','F13F18','F14F22','F15F21',
    'F20F37','F23F36','F24F38','F27F33','F28F35','F29F39','F31F34')
$RN_TripleCombos = @('F01F20F36','F02F32F37','F03F22F34','F04F19F38','F05F10F41',
    'F06F27F29','F07F17F39','F08F16F28','F09F25F40','F11F15F23',
    'F12F14F30','F13F18F42','F21F24F35','F26F31F33')
$RN_QuadCombos = @('F01F06F20F34','F02F05F20F37','F03F10F32F41','F04F07F16F17',
    'F08F12F14F28','F09F16F33F40','F11F15F21F35','F13F19F30F39',
    'F18F27F31F42','F22F23F25F36','F24F26F29F38')
if ($RN_DualCombos.Count -ne 21 -or $RN_TripleCombos.Count -ne 14 -or $RN_QuadCombos.Count -ne 11) { throw 'combo tables must be 21 / 14 / 11' }

# Loose (unzipped) upload files: name -> config key, default path relative to the repository root.
$RN_LooseKeys = [ordered]@{
    'README.md'                    = @{ Key = 'AVON_README_PATH';           Default = 'upload_extras\README.md' }
    'Avon_Dataset_Description.pdf' = @{ Key = 'AVON_DESCRIPTION_PDF_PATH';  Default = 'upload_extras\Avon_Dataset_Description.pdf' }
    'channel_dictionary.csv'       = @{ Key = 'AVON_CHANNEL_DICT_PATH';     Default = 'upload_extras\channel_dictionary.csv' }
}

function Read-ReleaseConfig {
    # config.txt as a hashtable (KEY=VALUE, '#' comments); environment variables override.
    $cfg = @{}
    $path = Join-Path $RN_ReleaseRoot 'config.txt'
    if (Test-Path -LiteralPath $path) {
        foreach ($line in Get-Content -LiteralPath $path) {
            $l = ($line -split '#', 2)[0].Trim()
            if ($l -notmatch '=') { continue }
            $kv = $l -split '=', 2
            if ($kv[0].Trim() -and $kv[1].Trim()) { $cfg[$kv[0].Trim()] = $kv[1].Trim() }
        }
    }
    $keys = @('AVON_DATA_ROOT', 'AVON_RELEASE_OUT_DIR') + @($RN_LooseKeys.Values | ForEach-Object { $_.Key })
    foreach ($k in $keys) {
        $ev = [Environment]::GetEnvironmentVariable($k)
        if ($ev) { $cfg[$k] = $ev }
    }
    return $cfg
}

function Resolve-AvonDataRoot {
    param([string]$CliValue)
    if ($CliValue) { return [System.IO.Path]::GetFullPath($CliValue) }
    $cfg = Read-ReleaseConfig
    if (-not $cfg['AVON_DATA_ROOT']) { throw 'AVON_DATA_ROOT is not set: pass --data-root, set the environment variable, or put AVON_DATA_ROOT=... in config.txt.' }
    return [System.IO.Path]::GetFullPath($cfg['AVON_DATA_ROOT'])
}

function Get-FaultCataloguePath {
    # The repository's catalogue (a pure release tree does not carry one); fall back to the data root.
    param([string]$DataRoot)
    $code = Join-Path $RN_ReleaseRoot 'FaultReference\fault_catalogue.csv'
    if (Test-Path -LiteralPath $code) { return $code }
    return (Join-Path $DataRoot 'FaultReference\fault_catalogue.csv')
}

function Resolve-AvonOutDir {
    # Where zips (<out>\zips) and the sample (<out>\Sample) are written: --out-dir, else
    # AVON_RELEASE_OUT_DIR (env / config.txt), else build. Refuses a location inside
    # (or equal to) the data root, which may be read-only and must stay a pure release tree.
    param([string]$CliValue, [string]$DataRoot)
    $cfg = Read-ReleaseConfig
    $out = if ($CliValue) { $CliValue } elseif ($cfg['AVON_RELEASE_OUT_DIR']) { $cfg['AVON_RELEASE_OUT_DIR'] } else { Join-Path $RN_ReleaseRoot 'build' }
    $out = [System.IO.Path]::GetFullPath($out).TrimEnd('\', '/')
    $dr  = [System.IO.Path]::GetFullPath($DataRoot).TrimEnd('\', '/')
    if ($out -ieq $dr -or $out.StartsWith($dr + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write inside the data root: out dir $out is within $DataRoot. Pass --out-dir outside the data root (default: build)."
    }
    return $out
}

function Get-FaultCatalogue {
    param([string]$DataRoot)
    $p = Get-FaultCataloguePath -DataRoot $DataRoot
    if (-not (Test-Path -LiteralPath $p)) { throw "fault_catalogue.csv not found: $p" }
    $rows = @(Import-Csv -LiteralPath $p -Encoding UTF8)
    if ($rows.Count -ne 42) { throw "fault_catalogue.csv must have 42 rows, got $($rows.Count)" }
    for ($i = 0; $i -lt 42; $i++) {
        if ($rows[$i].fault_id -ne ('F{0:D2}' -f ($i + 1))) { throw 'fault_catalogue.csv rows out of order' }
    }
    $ids = @($rows | ForEach-Object { $_.fault_id })
    foreach ($combo in ($RN_DualCombos + $RN_TripleCombos + $RN_QuadCombos)) {
        for ($i = 0; $i -lt $combo.Length; $i += 3) {
            if ($ids -notcontains $combo.Substring($i, 3)) { throw "combo $combo names an unknown fault" }
        }
    }
    return $rows
}

function Get-ComboGroup {
    param([string]$Combo)
    return @{ 2 = 'DualFault'; 3 = 'TripleFault'; 4 = 'QuadFault' }[[int]($Combo.Length / 3)]
}

function Get-ComboFolder {
    param([string]$Combo)
    return ("{0}_{1}" -f (Get-ComboGroup -Combo $Combo), $Combo)
}

function Get-Scenarios {
    # The 89 diagnosis-shaped scenarios in canonical order: Folder (with prefix), Token, Kind, RelDir
    # (path relative to the family root: DIAG_ multi-fault folders sit under their group folder,
    # DIAG_DualFault\DIAG_DualFault_F01F05; TD_ is flat).
    param([string]$DataRoot, [string]$Prefix)
    $rows = Get-FaultCatalogue -DataRoot $DataRoot
    $out = New-Object System.Collections.Generic.List[object]
    $out.Add([PSCustomObject]@{ Folder = "${Prefix}Healthy"; Token = 'Healthy'; Kind = 'healthy'; RelDir = "${Prefix}Healthy" })
    foreach ($r in $rows) {
        $f = "$Prefix$($r.fault_id)_$($r.code)"
        $out.Add([PSCustomObject]@{ Folder = $f; Token = $r.fault_id; Kind = 'single'; RelDir = $f })
    }
    foreach ($pair in @(@('dual', $RN_DualCombos), @('triple', $RN_TripleCombos), @('quad', $RN_QuadCombos))) {
        foreach ($c in $pair[1]) {
            $f = "$Prefix$(Get-ComboFolder -Combo $c)"
            $rel = if ($Prefix -eq 'TD_') { $f } else { "$Prefix$(Get-ComboGroup -Combo $c)\$f" }
            $out.Add([PSCustomObject]@{ Folder = $f; Token = $c; Kind = $pair[0]; RelDir = $rel })
        }
    }
    if ($out.Count -ne 89) { throw "expected 89 scenarios, got $($out.Count)" }
    return $out
}

function Get-RtfFolders {
    param([string]$DataRoot)
    $rows = Get-FaultCatalogue -DataRoot $DataRoot
    $out = @($rows | Where-Object { $_.rtf_member -eq 'yes' } | ForEach-Object { "RTF_$($_.fault_id)_$($_.code)" })
    if ($out.Count -ne 13) { throw "expected 13 RTF mechanisms in the catalogue, got $($out.Count)" }
    return $out
}

function Get-TopLevelEntries {
    # The 60 top-level folders of the release root; each is exactly one zip (<Name>.zip with <Name>\
    # as its top-level entry): DIAG_Healthy, 42 DIAG_Fxx_<code>, DIAG_DualFault, DIAG_TripleFault,
    # DIAG_QuadFault, 13 RTF_Fxx_<code>, DiagnosisTurndown. Name, Family, Scenarios.
    param([string]$DataRoot)
    $diag = @(Get-Scenarios -DataRoot $DataRoot -Prefix 'DIAG_')
    $out = New-Object System.Collections.Generic.List[object]
    $out.Add([PSCustomObject]@{ Name = 'DIAG_Healthy'; Family = 'Diagnosis'; Scenarios = @('DIAG_Healthy') })
    foreach ($s in ($diag | Where-Object { $_.Kind -eq 'single' })) {
        $out.Add([PSCustomObject]@{ Name = $s.Folder; Family = 'Diagnosis'; Scenarios = @($s.Folder) })
    }
    foreach ($pair in @(@('dual', 'DIAG_DualFault'), @('triple', 'DIAG_TripleFault'), @('quad', 'DIAG_QuadFault'))) {
        $out.Add([PSCustomObject]@{ Name = $pair[1]; Family = 'Diagnosis'; Scenarios = @($diag | Where-Object { $_.Kind -eq $pair[0] } | ForEach-Object { $_.Folder }) })
    }
    foreach ($folder in (Get-RtfFolders -DataRoot $DataRoot)) {
        $out.Add([PSCustomObject]@{ Name = $folder; Family = 'RunToFailure'; Scenarios = @($folder) })
    }
    $out.Add([PSCustomObject]@{ Name = 'DiagnosisTurndown'; Family = 'DiagnosisTurndown'; Scenarios = @(Get-Scenarios -DataRoot $DataRoot -Prefix 'TD_' | ForEach-Object { $_.Folder }) })
    if ($out.Count -ne 60) { throw "expected 60 top-level folders, got $($out.Count)" }
    return $out
}

function Get-DiagFilename {
    param([string]$Prefix, [string]$Token, [int]$Epoch)
    return ('{0}{1}_E{2:D4}.h5' -f $Prefix, $Token, $Epoch)
}

function Get-LooseFiles {
    # The loose (unzipped) upload files: Name, Path, How.
    param([string]$DataRoot, [string]$ZipsDir)
    $cfg = Read-ReleaseConfig
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($name in $RN_LooseKeys.Keys) {
        $k = $RN_LooseKeys[$name]
        $p = if ($cfg[$k.Key]) { $cfg[$k.Key] } else { $k.Default }
        if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $RN_ReleaseRoot $p }
        $out.Add([PSCustomObject]@{ Name = $name; Path = [System.IO.Path]::GetFullPath($p); How = $k.Key })
    }
    $out.Add([PSCustomObject]@{ Name = 'fault_catalogue.csv'; Path = [System.IO.Path]::GetFullPath((Get-FaultCataloguePath -DataRoot $DataRoot)); How = '<repo>\FaultReference' })
    $out.Add([PSCustomObject]@{ Name = 'MANIFEST.csv'; Path = [System.IO.Path]::GetFullPath((Join-Path $ZipsDir 'MANIFEST.csv')); How = 'written by zip_release' })
    return $out
}
