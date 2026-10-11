<#
.SYNOPSIS
    Produces a shareable INVENTORY of a GTA IV installation (names, sizes, hashes,
    format fingerprints). Produces NO game content.

.DESCRIPTION
    This exists so a 22 GB game installation can be analysed without moving,
    uploading, or redistributing a single game asset.

    Output (~1 MB of text, safe to commit or paste into a chat):
      summary.txt    - detected version, executable format/architecture/LAA flag,
                       archive magic numbers, per-extension counts and sizes,
                       presence of key marker files
      manifest.csv   - relative path, size in bytes, SHA-256 for every file
      tree.txt       - directory tree, two levels deep

    The installation root path is REDACTED from every output. Paths are written
    relative to the game root. Nothing here contains game content.

    Each output is written independently, and every section is fault-isolated:
    a failure in one section degrades that section and still writes the rest.

.PARAMETER GameDir
    Path to the GTA IV installation root (the folder containing GTAIV.exe).
    If omitted, common Steam / Rockstar / Epic paths are probed.

.PARAMETER OutDir
    Where to write the inventory. Defaults to .\gta4-inventory next to this script.

.PARAMETER NoHash
    Skip SHA-256 (much faster; ~seconds instead of minutes). Sizes and names only.

.PARAMETER ReuseManifest
    Do NOT re-scan or re-hash. Load the existing manifest.csv from OutDir and
    regenerate tree.txt and summary.txt from it. Use this after a crash so the
    expensive hashing pass is not repeated.

.PARAMETER SkipManifest
    Skip writing manifest.csv but still walk the tree (fast). Use when you want
    tree.txt and summary.txt without paying for hashes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1 `
      -GameDir "D:\Games\Grand Theft Auto IV\GTAIV"

.EXAMPLE
    # after a crash - regenerate the reports without re-hashing anything
    powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1 -ReuseManifest

.NOTES
    Read-only. Opens files, reads at most a few header bytes, never executes
    anything. Safe to run against an untrusted installation.
#>

[CmdletBinding()]
param(
    [string] $GameDir,
    [string] $OutDir,
    [switch] $NoHash,
    [switch] $ReuseManifest,
    [switch] $SkipManifest
)

# NOTE: StrictMode is deliberately NOT enabled. Under Set-StrictMode, reading
# .Count (or any property) on $null throws - and Get-ChildItem returns $null for
# an empty directory. That turned a harmless empty folder into a fatal crash that
# discarded tree.txt and summary.txt after the slow hashing pass had already
# completed. Every count and sum below is now explicitly null-safe instead.

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ------------------------------------------------------------- null-safe utils

function Get-SafeCount {
    param([object] $Value)
    if ($null -eq $Value) { return 0 }
    try { return @($Value).Count } catch { return 0 }
}

function Get-SafeSum {
    param([object] $Items)
    if ($null -eq $Items) { return [int64]0 }
    try {
        $s = ($Items | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $s) { return [int64]0 }
        return [int64]$s
    } catch { return [int64]0 }
}

function Add-Section {
    param(
        [System.Collections.Generic.List[string]] $Target,
        [string] $Name,
        [scriptblock] $Body
    )
    try { & $Body }
    catch {
        $Target.Add("")
        $Target.Add("  [section '$Name' failed: $($_.Exception.Message)]")
        $Target.Add("  The rest of this report is unaffected.")
        Write-Warning "Section '$Name' failed: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------- locate game

function Resolve-GameDir {
    param([string] $Hint)

    if ($Hint) {
        if (-not (Test-Path -LiteralPath $Hint)) { throw "GameDir not found: $Hint" }
        return (Resolve-Path -LiteralPath $Hint).Path
    }

    $candidates = @(
        'C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto IV\GTAIV'
        'C:\Program Files\Steam\steamapps\common\Grand Theft Auto IV\GTAIV'
        'D:\Steam\steamapps\common\Grand Theft Auto IV\GTAIV'
        'C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto IV Episodes from Liberty City\EFLC'
        'C:\Program Files (x86)\Rockstar Games\Grand Theft Auto IV'
        'C:\Program Files\Rockstar Games\Grand Theft Auto IV'
        'C:\Program Files (x86)\Epic Games\GrandTheftAutoIV\GTAIV'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c 'GTAIV.exe')) { return $c }
    }

    throw @"
GTA IV installation not found automatically.

Re-run with the path explicitly, e.g.:

  powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1 -GameDir "D:\Games\Grand Theft Auto IV\GTAIV"

The folder you want is the one containing GTAIV.exe (on Steam it is usually the
'GTAIV' SUBFOLDER of 'Grand Theft Auto IV').
"@
}

$root = Resolve-GameDir -Hint $GameDir

# NOTE: do NOT join 'gta4-inventory' twice here. An earlier build did
# (Join-Path (Join-Path $PSScriptRoot 'gta4-inventory') 'gta4-inventory'), which
# silently wrote everything one directory deeper than documented and made
# -ReuseManifest look in the wrong place.
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'gta4-inventory' }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$csvPath  = Join-Path $OutDir 'manifest.csv'
$treePath = Join-Path $OutDir 'tree.txt'
$sumPath  = Join-Path $OutDir 'summary.txt'

Write-Host ""
Write-Host "  GTA IV inventory" -ForegroundColor Cyan
Write-Host "  root : $root"
Write-Host "  out  : $OutDir"
Write-Host ""

# ------------------------------------------------------------- PE header read

function Get-PEHeader {
    param([string] $Path)

    $result = [ordered]@{
        File              = Split-Path -Leaf $Path
        SizeBytes         = 0
        Format            = 'unknown'
        Machine           = 'unknown'
        Bitness           = 'unknown'
        LargeAddressAware = 'unknown'
        Subsystem         = 'unknown'
        LinkTimestamp     = 'unknown'
        ProductVersion    = 'unknown'
        FileVersion       = 'unknown'
    }

    try { $result.SizeBytes = (Get-Item -LiteralPath $Path).Length } catch { }

    try {
        $vi = (Get-Item -LiteralPath $Path).VersionInfo
        if ($vi.ProductVersion) { $result.ProductVersion = $vi.ProductVersion }
        if ($vi.FileVersion)    { $result.FileVersion    = $vi.FileVersion }
    } catch { }

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'Read')
        if ($fs.Length -lt 0x40) { $result.Format = 'too small to be a PE'; return $result }
        $br = New-Object System.IO.BinaryReader($fs)

        $fs.Position = 0
        if ($br.ReadUInt16() -ne 0x5A4D) { $result.Format = 'not a PE/DOS executable'; return $result }

        $fs.Position = 0x3C
        $lfanew = $br.ReadUInt32()
        if ($lfanew -eq 0 -or ($lfanew + 24) -gt $fs.Length) { $result.Format = 'DOS header only'; return $result }

        $fs.Position = $lfanew
        if ($br.ReadUInt32() -ne 0x00004550) { $result.Format = 'MZ without PE signature'; return $result }

        $machine         = $br.ReadUInt16()
        $null            = $br.ReadUInt16()   # NumberOfSections
        $timeStamp       = $br.ReadUInt32()
        $null            = $br.ReadUInt32()   # PointerToSymbolTable
        $null            = $br.ReadUInt32()   # NumberOfSymbols
        $sizeOfOptHdr    = $br.ReadUInt16()
        $characteristics = $br.ReadUInt16()

        $result.Format = 'PE (Portable Executable)'
        $result.Machine = switch ($machine) {
            0x014c { 'i386 (x86 32-bit)' }
            0x8664 { 'AMD64 (x86-64)' }
            0x01c0 { 'ARM' }
            0xaa64 { 'ARM64' }
            default { ('0x{0:x4}' -f $machine) }
        }
        $result.Bitness = if ($machine -eq 0x8664 -or $machine -eq 0xaa64) { '64-bit' } else { '32-bit' }
        $result.LargeAddressAware = if ($characteristics -band 0x0020) { 'YES' } else { 'no' }

        if ($timeStamp -gt 0) {
            try { $result.LinkTimestamp = ([datetime]'1970-01-01T00:00:00Z').AddSeconds($timeStamp).ToString('u') }
            catch { $result.LinkTimestamp = "$timeStamp (raw)" }
        }

        if ($sizeOfOptHdr -ge 70) {
            $optStart = $lfanew + 24
            $fs.Position = $optStart
            $magic = $br.ReadUInt16()
            $fs.Position = $optStart + 68
            $subsystem = $br.ReadUInt16()
            $result.Subsystem = switch ($subsystem) {
                2 { 'GUI (Windows)' }
                3 { 'Console (CUI)' }
                9 { 'Windows CE' }
                default { ('0x{0:x}' -f $subsystem) }
            }
            if ($magic -eq 0x20b)      { $result.Bitness = '64-bit (PE32+)' }
            elseif ($magic -eq 0x10b)  { $result.Bitness = '32-bit (PE32)' }
        }
    }
    catch { $result.Format = "read error: $($_.Exception.Message)" }
    finally { if ($fs) { $fs.Dispose() } }

    return $result
}

# --------------------------------------------------- archive magic fingerprint

function Get-ArchiveMagic {
    param([string] $Path)

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'Read')
        $buf = New-Object byte[] 16
        $read = $fs.Read($buf, 0, 16)
        if ($read -lt 4) { return '(too small)' }

        $ascii = [System.Text.Encoding]::ASCII.GetString($buf, 0, 4)
        switch ($ascii) {
            'RPF2' { return 'RPF2  - GTA IV standard archive' }
            'RPF3' { return 'RPF3  - GTA IV AUDIO archive' }
            'RPF0' { return 'RPF0  - Table Tennis archive' }
            'RPF4' { return 'RPF4  - Max Payne 3 archive' }
            'RPF6' { return 'RPF6  - Red Dead Redemption archive' }
            'RPF7' { return 'RPF7  - GTA V archive' }
            'RPF8' { return 'RPF8  - RDR2 archive' }
        }

        $u32 = [System.BitConverter]::ToUInt32($buf, 0)
        switch ($u32) {
            0x32524556 { return 'IMG2  (VER2) - RenderWare-era archive' }
            0x33524556 { return 'IMG3  (VER3) - RAGE archive' }
            0xA94E2A52 { return 'IMG3  (alternative magic)' }
        }

        if ($buf[0] -eq 0x52 -and $buf[1] -eq 0x49 -and $buf[2] -eq 0x46 -and $buf[3] -eq 0x46) {
            return 'RIFF  - audio container'
        }
        if ($buf[0] -eq 0x1A -and $buf[1] -eq 0x45 -and $buf[2] -eq 0xDF -and $buf[3] -eq 0xA3) {
            return 'EBML/Matroska - video container'
        }
        if ($buf[0] -eq 0x50 -and $buf[1] -eq 0x4B) { return 'ZIP' }
        if ($buf[0] -eq 0x7F -and $buf[1] -eq 0x45 -and $buf[2] -eq 0x4C -and $buf[3] -eq 0x46) {
            return 'ELF - Linux executable'
        }

        $hex = ('0x{0:x2}{1:x2}{2:x2}{3:x2}' -f $buf[0], $buf[1], $buf[2], $buf[3])
        # GTA IV .img files carry a header value that is not one of the known IMG
        # magics. They are still valid RAGE archives - gta4-webmap and RageLib read
        # them - so say so rather than reporting a bare "unknown".
        if ($Path -match '\.img$') { return "IMG  - RAGE archive (magic $hex not in table)" }
        return "unknown ($hex)"
    }
    catch { return "(unreadable: $($_.Exception.Message))" }
    finally { if ($fs) { $fs.Dispose() } }
}

# =========================================================== 1. manifest.csv

$files = @()

if ($ReuseManifest) {
    # An earlier build wrote one directory deeper than documented. Rather than
    # make the user move files, look in the expected place, then the legacy
    # nested location, then anywhere underneath OutDir.
    if (-not (Test-Path -LiteralPath $csvPath)) {
        $candidates = @(
            (Join-Path $OutDir 'gta4-inventory\manifest.csv')
            (Join-Path $OutDir '..\*\manifest.csv')
        )
        foreach ($c in $candidates) {
            $hit = @(Get-ChildItem -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ((Get-SafeCount $hit) -gt 0) { $csvPath = $hit[0].FullName; break }
        }
    }
    if (-not (Test-Path -LiteralPath $csvPath)) {
        $hit = @(Get-ChildItem -LiteralPath $OutDir -Recurse -Filter 'manifest.csv' -ErrorAction SilentlyContinue |
                 Select-Object -First 1)
        if ((Get-SafeCount $hit) -gt 0) { $csvPath = $hit[0].FullName }
    }
    if (-not (Test-Path -LiteralPath $csvPath)) {
        throw @"
-ReuseManifest was requested but no manifest.csv was found under:
  $OutDir

Searched the expected location, the legacy nested 'gta4-inventory' subfolder,
and everything beneath OutDir. Either run a full scan first (without
-ReuseManifest), or pass -OutDir pointing at the folder holding manifest.csv.
"@
    }
    if ($csvPath -ne (Join-Path $OutDir 'manifest.csv')) {
        Write-Host "  Found manifest at: $csvPath" -ForegroundColor DarkGray
    }
    Write-Host "  Reusing existing manifest.csv (no re-hashing)." -ForegroundColor Yellow
    $rows = @(Import-Csv -LiteralPath $csvPath)
    # Build into a List: repeated array += is O(n^2) and painfully slow at 5-6k rows.
    $reused = New-Object System.Collections.Generic.List[object]
    foreach ($r in $rows) {
        $rel = [string]$r.relative_path
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        $sz = [int64]0
        [void][int64]::TryParse([string]$r.size_bytes, [ref]$sz)
        $reused.Add([pscustomobject]@{
            FullName = (Join-Path $root $rel)
            Length   = $sz
        })
    }
    $files = $reused.ToArray()
    Write-Host "  Loaded $(Get-SafeCount $files) entries from manifest.csv." -ForegroundColor Gray
}
else {
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
               Sort-Object FullName)
    Write-Host "  Found $(Get-SafeCount $files) files." -ForegroundColor Gray

    if (-not $SkipManifest) {
        $csv = New-Object System.Collections.Generic.List[string]
        $csv.Add('relative_path,size_bytes,sha256')

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $i = 0
        $total = Get-SafeCount $files
        foreach ($f in $files) {
            $i++
            $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
            $sha = ''
            if (-not $NoHash) {
                try { $sha = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
                catch { $sha = 'ERROR' }
            }
            $relEsc = '"' + ($rel -replace '"', '""') + '"'
            $csv.Add("$relEsc,$($f.Length),$sha")

            if ($i % 250 -eq 0) {
                Write-Progress -Activity 'Inventorying GTA IV' -Status "$i / $total" `
                               -PercentComplete ([int]($i / [math]::Max(1,$total) * 100))
            }
        }
        Write-Progress -Activity 'Inventorying GTA IV' -Completed
        $sw.Stop()

        try {
            $csv | Set-Content -LiteralPath $csvPath -Encoding UTF8
            Write-Host "  manifest.csv   written ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green
        }
        catch { Write-Warning "Could not write manifest.csv: $($_.Exception.Message)" }
    }
    else {
        Write-Host "  manifest.csv   skipped (-SkipManifest)" -ForegroundColor Yellow
    }
}

# =============================================================== 2. tree.txt

Write-Host "  Building tree.txt ..." -ForegroundColor Gray
$treeLines = New-Object System.Collections.Generic.List[string]

Add-Section -Target $treeLines -Name 'tree' -Body {
    $treeLines.Add("GTA IV installation tree (2 levels, sizes summed). Root path redacted.")
    $treeLines.Add("Generated: $((Get-Date).ToString('u'))")
    $treeLines.Add("")

    $topDirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($d in $topDirs) {
        $sub  = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue)
        $nSub = Get-SafeCount $sub
        $bSub = Get-SafeSum  $sub
        $treeLines.Add(("{0,-42} {1,7} files {2,14:N0} bytes" -f ($d.Name + '\'), $nSub, $bSub))

        $subDirs = @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($d2 in $subDirs) {
            $sub2  = @(Get-ChildItem -LiteralPath $d2.FullName -Recurse -File -ErrorAction SilentlyContinue)
            $nSub2 = Get-SafeCount $sub2
            $bSub2 = Get-SafeSum  $sub2
            $treeLines.Add(("  {0,-40} {1,7} files {2,14:N0} bytes" -f ($d2.Name + '\'), $nSub2, $bSub2))
        }
    }
}

try {
    $treeLines | Set-Content -LiteralPath $treePath -Encoding UTF8
    Write-Host "  tree.txt       written" -ForegroundColor Green
}
catch { Write-Warning "Could not write tree.txt: $($_.Exception.Message)" }

# ============================================================ 3. summary.txt

Write-Host "  Building summary.txt ..." -ForegroundColor Gray
$out = New-Object System.Collections.Generic.List[string]
function Add($s) { $out.Add($s) }

$totalBytes = Get-SafeSum $files
$fileCount  = Get-SafeCount $files

Add-Section -Target $out -Name 'header' -Body {
    Add '================================================================================'
    Add ' GTA IV INSTALLATION INVENTORY'
    Add '================================================================================'
    Add " Generated          : $((Get-Date).ToString('u'))"
    Add " Scanner            : tools/gta4-inventory.ps1"
    Add " Root path          : (redacted - not recorded)"
    Add " Total files        : $fileCount"
    Add " Total size         : $([math]::Round($totalBytes / 1GB, 2)) GB  ($('{0:N0}' -f $totalBytes) bytes)"
    Add ''
    Add ' NOTE ON SHARING'
    Add ' ----------------'
    Add ' This file contains filenames, sizes and hashes ONLY. It contains no game'
    Add ' content and is safe to commit to a public repository or paste into a chat.'
    Add ' The installation root path has been deliberately redacted.'
    Add ''
}

# --- executables
Add-Section -Target $out -Name 'executables' -Body {
    Add '================================================================================'
    Add ' EXECUTABLES'
    Add '================================================================================'
    $foundAny = $false
    foreach ($name in @('GTAIV.exe', 'LaunchGTAIV.exe', 'EFLC.exe', 'LaunchEFLC.exe')) {
        $p = Join-Path $root $name
        if (Test-Path -LiteralPath $p) {
            $foundAny = $true
            $pe = Get-PEHeader -Path $p
            Add ''
            Add " $name"
            foreach ($k in $pe.Keys) { Add ("   {0,-20} {1}" -f ($k + ':'), $pe[$k]) }
        }
    }
    if (-not $foundAny) {
        Add ''
        Add ' No GTAIV.exe / EFLC.exe found at this root.'
        Add ' The manifest root may be one level too high or too low.'
    }
    Add ''
}

# --- native DLL dependencies
Add-Section -Target $out -Name 'dlls' -Body {
    Add '================================================================================'
    Add ' NATIVE DLL DEPENDENCIES / MIDDLEWARE MARKERS'
    Add '================================================================================'
    $markers = @(
        'binkw32.dll', 'bink2w32.dll', 'xlive.dll', 'd3d9.dll', 'd3dx9_40.dll',
        'd3dx9_41.dll', 'd3dx9_42.dll', 'd3dx9_43.dll', 'xinput1_3.dll', 'x3daudio1_7.dll',
        'dsound.dll', 'GTAIVGDF.dll', 'LiveTokenHelper.dll', 'GameuxInstallHelper.dll',
        'Paul.dll', 'DFA.dll', '1911.dll', 'openal32.dll', 'OpenAL32.dll',
        'vorbisfile.dll', 'libspeex.dll', 'GFWLDownload.dll', 'ScriptHook.dll',
        'ScriptHookDotNet.dll', 'dinput8.dll', 'winmm.dll'
    )
    foreach ($m in $markers) {
        $p = Join-Path $root $m
        if (Test-Path -LiteralPath $p) {
            $len = 0
            try { $len = (Get-Item -LiteralPath $p).Length } catch { }
            Add ("   {0,-26} present   {1,12:N0} bytes" -f $m, $len)
        }
    }
    $dllList = @(Get-ChildItem -LiteralPath $root -Filter '*.dll' -File -ErrorAction SilentlyContinue |
                 Select-Object -ExpandProperty Name | Sort-Object)
    Add ''
    if ((Get-SafeCount $dllList) -gt 0) {
        Add "   All DLLs in root: $($dllList -join ', ')"
    }
    else { Add '   No DLLs in root.' }
    Add ''
}

# --- archive fingerprints
Add-Section -Target $out -Name 'archive-magic' -Body {
    Add '================================================================================'
    Add ' ARCHIVE FINGERPRINTS (first 16 bytes; identifies the container format)'
    Add '================================================================================'
    $rpf = @($files | Where-Object { $_.FullName -match '\.(rpf|img)$' } | Sort-Object FullName)
    Add ''
    $rpfCount = Get-SafeCount $rpf
    Add " Scanning $rpfCount .rpf / .img archives..."
    Add ''

    $magicTally = @{}
    $samples    = @{}
    foreach ($a in $rpf) {
        if (-not (Test-Path -LiteralPath $a.FullName)) { continue }
        $rel = $a.FullName.Substring($root.Length).TrimStart('\', '/')
        $m   = Get-ArchiveMagic -Path $a.FullName
        $key = ($m -split '\s+')[0]
        if (-not $magicTally.ContainsKey($key)) {
            $magicTally[$key] = 0
            $samples[$key]    = @()
        }
        $magicTally[$key]++
        if ((Get-SafeCount $samples[$key]) -lt 3) { $samples[$key] += $rel }
    }

    Add ' Summary by magic:'
    foreach ($k in ($magicTally.Keys | Sort-Object { -$magicTally[$_] })) {
        Add ("   {0,-12} {1,5} file(s)   e.g. {2}" -f $k, $magicTally[$k], ($samples[$k] -join ', '))
    }
    Add ''
    Add ' Largest 15 archives:'
    foreach ($a in ($rpf | Sort-Object Length -Descending | Select-Object -First 15)) {
        $rel = $a.FullName.Substring($root.Length).TrimStart('\', '/')
        $m   = Get-ArchiveMagic -Path $a.FullName
        Add ("   {0,-52} {1,12:N0} bytes   {2}" -f $rel, $a.Length, $m)
    }
    Add ''
}

# --- extension breakdown
Add-Section -Target $out -Name 'extensions' -Body {
    Add '================================================================================'
    Add ' FILE COUNT AND SIZE BY EXTENSION (top 40 by count)'
    Add '================================================================================'
    Add ("   {0,-14} {1,8} {2,16} {3,12}" -f 'EXT', 'COUNT', 'BYTES', 'GB')
    $byExt = @($files | Group-Object { if ($_.FullName -match '\.([^.\\/]+)$') { $Matches[1].ToLowerInvariant() } else { '(none)' } })
    foreach ($g in ($byExt | Sort-Object Count -Descending | Select-Object -First 40)) {
        $s = Get-SafeSum $g.Group
        Add ("   {0,-14} {1,8} {2,16:N0} {3,12:N3}" -f $g.Name, $g.Count, $s, ($s / 1GB))
    }
    Add ''
}

# --- edition / version detection
Add-Section -Target $out -Name 'edition' -Body {
    Add '================================================================================'
    Add ' EDITION AND VERSION MARKERS'
    Add '================================================================================'
    $checks = @(
        @{ Label = 'GTA IV base (common\data)';          Path = 'common\data' }
        @{ Label = 'TLAD episode (Lost and Damned)';     Path = 'TLAD' }
        @{ Label = 'TBoGT episode (Ballad of Gay Tony)'; Path = 'TBoGT' }
        @{ Label = 'EFLC root';                          Path = 'EFLC' }
        @{ Label = 'PC data tree';                       Path = 'pc' }
        @{ Label = 'Common tree';                        Path = 'common' }
        @{ Label = 'Shaders (common\shaders)';           Path = 'common\shaders' }
        @{ Label = 'Shader DB (common\shaders\db)';      Path = 'common\shaders\db' }
        @{ Label = 'Audio (pc\audio)';                   Path = 'pc\audio' }
        @{ Label = 'SFX (pc\audio\sfx)';                 Path = 'pc\audio\sfx' }
        @{ Label = 'Radio (pc\audio\radio)';             Path = 'pc\audio\radio' }
        @{ Label = 'Models (pc\models\cdimages)';        Path = 'pc\models\cdimages' }
        @{ Label = 'Textures (pc\textures)';             Path = 'pc\textures' }
        @{ Label = 'Map data (pc\data\cdimages)';        Path = 'pc\data\cdimages' }
        @{ Label = 'Installers';                         Path = 'Installers' }
        @{ Label = 'DirectX redist';                     Path = 'Installers\DirectX' }
    )
    foreach ($c in $checks) {
        $present = Test-Path -LiteralPath (Join-Path $root $c.Path)
        Add ("   {0,-40} {1}" -f $c.Label, $(if ($present) { 'PRESENT' } else { '-' }))
    }
    Add ''
    $filesTxt = Join-Path $root 'files.txt'
    if (Test-Path -LiteralPath $filesTxt) {
        Add " files.txt exists ($((Get-Item -LiteralPath $filesTxt).Length) bytes) - first 5 lines:"
        Get-Content -LiteralPath $filesTxt -TotalCount 5 -ErrorAction SilentlyContinue | ForEach-Object { Add "   | $_" }
    }
    $cmdline = Join-Path $root 'commandline.txt'
    if (Test-Path -LiteralPath $cmdline) {
        Add ''
        Add ' commandline.txt contents:'
        Get-Content -LiteralPath $cmdline -ErrorAction SilentlyContinue | ForEach-Object { Add "   | $_" }
    }
    Add ''
}

# --- key data files
Add-Section -Target $out -Name 'key-files' -Body {
    Add '================================================================================'
    Add ' KEY DATA FILES USED BY THE BROWSER PORT (presence + size)'
    Add '================================================================================'
    # Timecycle lives under pc\data in the Complete Edition, NOT common\data -
    # checking only common\data produced a false MISSING. Both are probed.
    # Peds are assembled from componentpeds.img; there is no peds.img in GTA IV.
    $keyFiles = [ordered]@{
        'World definition (gta.dat)'           = 'common\data\gta.dat'
        'Vehicle handling'                     = 'common\data\handling.dat'
        'Timecycle / lighting (pc\data)'       = 'pc\data\timecyc.dat'
        'Timecycle / lighting (common\data)'   = 'common\data\timecyc.dat'
        'Weapon stats'                         = 'common\data\WeaponInfo.xml'
        'Vehicle catalogue'                    = 'common\data\vehicles.ide'
        'Vehicle colours'                      = 'common\data\carcols.dat'
        'Ped catalogue'                        = 'common\data\peds.ide'
        'Item definitions'                     = 'common\data\default.ide'
        'Road network 1'                       = 'common\data\maps\paths.ipl'
        'Road network 2'                       = 'common\data\maps\paths2.ipl'
        'Boat lanes'                           = 'common\data\maps\paths3.ipl'
        'Network paths 4'                      = 'common\data\maps\paths4.ipl'
        'Ped navmesh'                          = 'pc\data\cdimages\navmeshes.img'
        'Vehicles'                             = 'pc\models\cdimages\vehicles.img'
        'Weapons'                              = 'pc\models\cdimages\weapons.img'
        'Player model'                         = 'pc\models\cdimages\playerped.rpf'
        'Ped components'                       = 'pc\models\cdimages\componentpeds.img'
        'Cutscene animation'                   = 'pc\anim\cuts.img'
        'Sky textures'                         = 'pc\textures\skydome.wtd'
        'Audio SFX'                            = 'pc\audio\sfx'
        'Audio radio'                          = 'pc\audio\radio'
    }
    foreach ($entry in $keyFiles.GetEnumerator()) {
        $label = $entry.Key
        $k     = $entry.Value
        $p = Join-Path $root $k
        if (Test-Path -LiteralPath $p) {
            $item = Get-Item -LiteralPath $p
            if ($item.PSIsContainer) {
                $inner = @(Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue)
                Add ("   {0,-34} {1,-46} DIR, {2,5} files, {3,12:N0} bytes" -f $label, $k, (Get-SafeCount $inner), (Get-SafeSum $inner))
            }
            else {
                Add ("   {0,-34} {1,-46} {2,12:N0} bytes" -f $label, $k, $item.Length)
            }
        }
        else { Add ("   {0,-34} {1,-46} MISSING" -f $label, $k) }
    }
    Add ''
}

Add-Section -Target $out -Name 'footer' -Body {
    Add '================================================================================'
    Add ' END OF INVENTORY'
    Add '================================================================================'
}

try {
    $out | Set-Content -LiteralPath $sumPath -Encoding UTF8
    Write-Host "  summary.txt    written" -ForegroundColor Green
}
catch { Write-Warning "Could not write summary.txt: $($_.Exception.Message)" }

# --------------------------------------------------------------------- wrap up

Write-Host ""
Write-Host "  Done. Output in:" -ForegroundColor Cyan
Write-Host "    $OutDir"
Write-Host ""
Get-ChildItem -LiteralPath $OutDir -File -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("      {0,-16} {1,12:N0} bytes" -f $_.Name, $_.Length)
}
Write-Host ""
Write-Host "  NEXT STEP" -ForegroundColor Yellow
Write-Host "  Read summary.txt first, then commit the folder:"
Write-Host "      git add tools/gta4-inventory"
Write-Host "      git commit -m 'Add GTA IV installation inventory'"
Write-Host "      git push"
Write-Host ""
Write-Host "  Do NOT upload the game itself, and do not commit web/assets or web/data."
Write-Host ""
