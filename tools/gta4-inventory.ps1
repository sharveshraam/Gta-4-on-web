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

.PARAMETER GameDir
    Path to the GTA IV installation root (the folder containing GTAIV.exe).
    If omitted, common Steam / Rockstar / Epic paths are probed.

.PARAMETER OutDir
    Where to write the inventory. Defaults to .\gta4-inventory next to this script.

.PARAMETER NoHash
    Skip SHA-256 (much faster; ~seconds instead of minutes). Sizes and names only.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\gta4-inventory.ps1 -GameDir "D:\Games\Grand Theft Auto IV\GTAIV"

.NOTES
    Read-only. Opens files, reads at most a few header bytes, never executes
    anything. Safe to run against an untrusted installation.
#>

[CmdletBinding()]
param(
    [string] $GameDir,
    [string] $OutDir,
    [switch] $NoHash
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'gta4-inventory' }
$OutDir = Join-Path $OutDir 'gta4-inventory'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host ""
Write-Host "  GTA IV inventory" -ForegroundColor Cyan
Write-Host "  root : $root"
Write-Host "  out  : $OutDir"
Write-Host ""

# ------------------------------------------------------------- PE header read

function Get-PEHeader {
    param([string] $Path)

    $result = [ordered]@{
        File            = Split-Path -Leaf $Path
        SizeBytes       = (Get-Item -LiteralPath $Path).Length
        Format          = 'unknown'
        Machine         = 'unknown'
        Bitness         = 'unknown'
        LargeAddressAware = 'unknown'
        Subsystem       = 'unknown'
        LinkTimestamp   = 'unknown'
        ProductVersion  = 'unknown'
        FileVersion     = 'unknown'
    }

    try {
        $vi = (Get-Item -LiteralPath $Path).VersionInfo
        if ($vi.ProductVersion) { $result.ProductVersion = $vi.ProductVersion }
        if ($vi.FileVersion)    { $result.FileVersion    = $vi.FileVersion }
    } catch { }

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'Read')
        if ($fs.Length -lt 0x40) { return $result }
        $br = New-Object System.IO.BinaryReader($fs)

        $fs.Position = 0
        if ($br.ReadUInt16() -ne 0x5A4D) { $result.Format = 'not a PE/DOS executable'; return $result }

        $fs.Position = 0x3C
        $lfanew = $br.ReadUInt32()
        if ($lfanew -eq 0 -or ($lfanew + 24) -gt $fs.Length) { $result.Format = 'DOS header only'; return $result }

        $fs.Position = $lfanew
        if ($br.ReadUInt32() -ne 0x00004550) { $result.Format = 'MZ without PE signature'; return $result }

        $machine        = $br.ReadUInt16()
        $null           = $br.ReadUInt16()   # NumberOfSections
        $timeStamp      = $br.ReadUInt32()
        $null           = $br.ReadUInt32()   # PointerToSymbolTable
        $null           = $br.ReadUInt32()   # NumberOfSymbols
        $sizeOfOptHdr   = $br.ReadUInt16()
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
            $result.LinkTimestamp = ([datetime]'1970-01-01T00:00:00Z').AddSeconds($timeStamp).ToString('u')
        }

        # Optional header: magic at +0, Subsystem at +68 (PE32) / +68 (PE32+ too)
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
            if ($magic -eq 0x20b) { $result.Bitness = '64-bit (PE32+)' }
            elseif ($magic -eq 0x10b) { $result.Bitness = '32-bit (PE32)' }
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

        # IMG v2/v3 magic is the Jenkins hash of "V"/"VER2"/"VER3"
        #   VER2 = 0x32524556, VER3 = 0x33524556
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

        return ('unknown (0x{0:x2}{1:x2}{2:x2}{3:x2})' -f $buf[0], $buf[1], $buf[2], $buf[3])
    }
    catch { return "(unreadable: $($_.Exception.Message))" }
    finally { if ($fs) { $fs.Dispose() } }
}

# ------------------------------------------------------------------ inventory

$files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
         Sort-Object FullName

Write-Host "  Found $($files.Count) files." -ForegroundColor Gray

# manifest.csv -----------------------------------------------------------------

$csvPath = Join-Path $OutDir 'manifest.csv'
$csv = New-Object System.Collections.Generic.List[string]
$csv.Add('relative_path,size_bytes,sha256')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$i = 0
foreach ($f in $files) {
    $i++
    $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
    $sha = ''
    if (-not $NoHash) {
        try { $sha = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
        catch { $sha = 'ERROR' }
    }
    # Quote and escape for CSV
    $relEsc = '"' + ($rel -replace '"', '""') + '"'
    $csv.Add("$relEsc,$($f.Length),$sha")

    if ($i % 250 -eq 0) {
        $pct = [int]($i / $files.Count * 100)
        Write-Progress -Activity 'Inventorying GTA IV' -Status "$i / $($files.Count)" -PercentComplete $pct
    }
}
Write-Progress -Activity 'Inventorying GTA IV' -Completed

$csv | Set-Content -LiteralPath $csvPath -Encoding UTF8
$sw.Stop()
Write-Host "  manifest.csv   written ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green

# tree.txt ---------------------------------------------------------------------

$treePath = Join-Path $OutDir 'tree.txt'
$tree = New-Object System.Collections.Generic.List[string]
$tree.Add("GTA IV installation tree (2 levels, sizes summed). Root path redacted.")
$tree.Add("Generated: $((Get-Date).ToString('u'))")
$tree.Add("")
foreach ($d in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $sub = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue
    $sum = ($sub | Measure-Object -Property Length -Sum).Sum
    if (-not $sum) { $sum = 0 }
    $tree.Add(("{0,-42} {1,7} files {2,12:N0} bytes" -f ($d.Name + '\'), $sub.Count, $sum))
    foreach ($d2 in (Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $sub2 = Get-ChildItem -LiteralPath $d2.FullName -Recurse -File -ErrorAction SilentlyContinue
        $sum2 = ($sub2 | Measure-Object -Property Length -Sum).Sum
        if (-not $sum2) { $sum2 = 0 }
        $tree.Add(("  {0,-40} {1,7} files {2,12:N0} bytes" -f ($d2.Name + '\'), $sub2.Count, $sum2))
    }
}
$tree | Set-Content -LiteralPath $treePath -Encoding UTF8
Write-Host "  tree.txt       written" -ForegroundColor Green

# summary.txt ------------------------------------------------------------------

$sum = New-Object System.Collections.Generic.List[string]
$total = ($files | Measure-Object -Property Length -Sum).Sum

function Add($s) { $sum.Add($s) }

Add '================================================================================'
Add ' GTA IV INSTALLATION INVENTORY'
Add '================================================================================'
Add " Generated          : $((Get-Date).ToString('u'))"
Add " Scanner            : tools/gta4-inventory.ps1"
Add " Root path          : (redacted - not recorded)"
Add " Total files        : $($files.Count)"
Add " Total size         : $([math]::Round($total / 1GB, 2)) GB  ($('{0:N0}' -f $total) bytes)"
Add ''
Add ' NOTE ON SHARING'
Add ' ----------------'
Add ' This file contains filenames, sizes and hashes ONLY. It contains no game'
Add ' content and is safe to commit to a public repository or paste into a chat.'
Add ' The installation root path has been deliberately redacted.'
Add ''

# --- executables
Add '================================================================================'
Add ' EXECUTABLES'
Add '================================================================================'
foreach ($name in @('GTAIV.exe', 'LaunchGTAIV.exe', 'EFLC.exe', 'LaunchEFLC.exe')) {
    $p = Join-Path $root $name
    if (Test-Path -LiteralPath $p) {
        $pe = Get-PEHeader -Path $p
        Add ''
        Add " $name"
        foreach ($k in $pe.Keys) { Add ("   {0,-20} {1}" -f ($k + ':'), $pe[$k]) }
    }
}
Add ''

# --- native DLL dependencies
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
    if (Test-Path -LiteralPath (Join-Path $root $m)) {
        $fi = Get-Item -LiteralPath (Join-Path $root $m)
        Add ("   {0,-26} present   {1,12:N0} bytes" -f $m, $fi.Length)
    }
}
$foundDlls = Get-ChildItem -LiteralPath $root -Filter '*.dll' -File -ErrorAction SilentlyContinue |
             Select-Object -ExpandProperty Name | Sort-Object
if ($foundDlls) {
    Add ''
    Add "   All DLLs in root: $($foundDlls -join ', ')"
}
Add ''

# --- archive fingerprints
Add '================================================================================'
Add ' ARCHIVE FINGERPRINTS (first 16 bytes; identifies the container format)'
Add '================================================================================'
$rpf = $files | Where-Object { $_.Extension -match '^\.(rpf|img)$' } | Sort-Object FullName
Add ''
Add " Scanning $($rpf.Count) .rpf / .img archives..."
Add ''
$magicTally = @{}
$samples = @{}
foreach ($a in $rpf) {
    $rel = $a.FullName.Substring($root.Length).TrimStart('\', '/')
    $m = Get-ArchiveMagic -Path $a.FullName
    $key = ($m -split '\s+')[0]
    if (-not $magicTally.ContainsKey($key)) {
        $magicTally[$key] = 0
        $samples[$key] = @()
    }
    $magicTally[$key]++
    if ($samples[$key].Count -lt 3) { $samples[$key] += $rel }
}
Add ' Summary by magic:'
foreach ($k in ($magicTally.Keys | Sort-Object { -$magicTally[$_] })) {
    Add ("   {0,-12} {1,5} file(s)   e.g. {2}" -f $k, $magicTally[$k], ($samples[$k] -join ', '))
}
Add ''
Add ' Largest 15 archives:'
foreach ($a in ($rpf | Sort-Object Length -Descending | Select-Object -First 15)) {
    $rel = $a.FullName.Substring($root.Length).TrimStart('\', '/')
    $m = Get-ArchiveMagic -Path $a.FullName
    Add ("   {0,-52} {1,10:N0} bytes   {2}" -f $rel, $a.Length, $m)
}
Add ''

# --- extension breakdown
Add '================================================================================'
Add ' FILE COUNT AND SIZE BY EXTENSION (top 40 by count)'
Add '================================================================================'
Add ("   {0,-14} {1,8} {2,16} {3,12}" -f 'EXT', 'COUNT', 'BYTES', 'GB')
$byExt = $files | Group-Object { if ($_.Extension) { $_.Extension.ToLowerInvariant() } else { '(none)' } }
foreach ($g in ($byExt | Sort-Object Count -Descending | Select-Object -First 40)) {
    $s = ($g.Group | Measure-Object -Property Length -Sum).Sum
    Add ("   {0,-14} {1,8} {2,16:N0} {3,12:N3}" -f $g.Name, $g.Count, $s, ($s / 1GB))
}
Add ''

# --- edition / version detection
Add '================================================================================'
Add ' EDITION AND VERSION MARKERS'
Add '================================================================================'
$checks = @(
    @{ Label = 'GTA IV base (common/data)';        Path = 'common\data' }
    @{ Label = 'TLAD episode (The Lost and Damned)'; Path = 'TLAD' }
    @{ Label = 'TBoGT episode (Ballad of Gay Tony)'; Path = 'TBoGT' }
    @{ Label = 'EFLC root';                        Path = 'EFLC' }
    @{ Label = 'PC data tree';                     Path = 'pc' }
    @{ Label = 'Common tree';                      Path = 'common' }
    @{ Label = 'Shaders (common/shaders)';         Path = 'common\shaders' }
    @{ Label = 'Shader DB (common/shaders/db)';    Path = 'common\shaders\db' }
    @{ Label = 'Audio (pc/audio)';                 Path = 'pc\audio' }
    @{ Label = 'SFX (pc/audio/sfx)';               Path = 'pc\audio\sfx' }
    @{ Label = 'Radio (pc/audio/radio)';           Path = 'pc\audio\radio' }
    @{ Label = 'Models (pc/models/cdimages)';      Path = 'pc\models\cdimages' }
    @{ Label = 'Textures (pc/textures)';           Path = 'pc\textures' }
    @{ Label = 'Map data (pc/data/cdimages)';      Path = 'pc\data\cdimages' }
    @{ Label = 'Navmeshes dir';                    Path = 'pc\data\cdimages' }
    @{ Label = 'Installers';                       Path = 'Installers' }
    @{ Label = 'DirectX redist';                   Path = 'Installers\DirectX' }
)
foreach ($c in $checks) {
    $p = Join-Path $root $c.Path
    $present = Test-Path -LiteralPath $p
    Add ("   {0,-40} {1}" -f $c.Label, $(if ($present) { 'PRESENT' } else { '-' }))
}
Add ''
$filesTxt = Join-Path $root 'files.txt'
if (Test-Path -LiteralPath $filesTxt) {
    Add " files.txt exists ($((Get-Item -LiteralPath $filesTxt).Length) bytes) - first 5 lines:"
    Get-Content -LiteralPath $filesTxt -TotalCount 5 | ForEach-Object { Add "   | $_" }
}
$cmdline = Join-Path $root 'commandline.txt'
if (Test-Path -LiteralPath $cmdline) {
    Add ''
    Add ' commandline.txt contents:'
    Get-Content -LiteralPath $cmdline | ForEach-Object { Add "   | $_" }
}
Add ''

# --- key data files the port cares about
Add '================================================================================'
Add ' KEY DATA FILES USED BY THE BROWSER PORT (presence + size)'
Add '================================================================================'
$keyFiles = @(
    'common\data\gta.dat', 'common\data\handling.dat', 'common\data\timecyc.dat',
    'common\data\WeaponInfo.xml', 'common\data\vehicles.ide', 'common\data\carcols.dat',
    'common\data\peds.ide', 'common\data\default.ide', 'common\data\maps\paths.ipl',
    'common\data\maps\paths2.ipl', 'common\data\maps\paths3.ipl', 'common\data\maps\paths4.ipl',
    'common\text\*.gxt', 'pc\data\cdimages\navmeshes.img',
    'pc\models\cdimages\vehicles.img', 'pc\models\cdimages\weapons.img',
    'pc\models\cdimages\playerped.rpf', 'pc\models\cdimages\peds.img',
    'pc\textures\skydome.wtd', 'pc\audio\sfx', 'pc\audio\radio'
)
foreach ($k in $keyFiles) {
    $matches = @()
    if ($k -like '*`**') {
        $dir = Split-Path $k
        $pat = Split-Path $k -Leaf
        if (Test-Path -LiteralPath (Join-Path $root $dir)) {
            $matches = Get-ChildItem -LiteralPath (Join-Path $root $dir) -Filter $pat -File -ErrorAction SilentlyContinue
        }
    } else {
        $p = Join-Path $root $k
        if (Test-Path -LiteralPath $p) { $matches = @(Get-Item -LiteralPath $p) }
    }
    if ($matches.Count -gt 0) {
        foreach ($m in ($matches | Select-Object -First 3)) {
            $rel = $m.FullName.Substring($root.Length).TrimStart('\', '/')
            if ($m.PSIsContainer) {
                $n = (Get-ChildItem -LiteralPath $m.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
                $s = (Get-ChildItem -LiteralPath $m.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                Add ("   {0,-46} DIR, {1,5} files, {2,12:N0} bytes" -f $rel, $n, $s)
            } else {
                Add ("   {0,-46} {1,12:N0} bytes" -f $rel, $m.Length)
            }
        }
        if ($matches.Count -gt 3) { Add ("     ... and $($matches.Count - 3) more") }
    } else {
        Add ("   {0,-46} MISSING" -f $k)
    }
}
Add ''
Add '================================================================================'
Add ' END OF INVENTORY'
Add '================================================================================'

$sum | Set-Content -LiteralPath (Join-Path $OutDir 'summary.txt') -Encoding UTF8
Write-Host "  summary.txt    written" -ForegroundColor Green

# --------------------------------------------------------------------- wrap up

Write-Host ""
Write-Host "  Done. Output in:" -ForegroundColor Cyan
Write-Host "    $OutDir"
Write-Host ""
Get-ChildItem -LiteralPath $OutDir -File | ForEach-Object {
    Write-Host ("      {0,-16} {1,10:N0} bytes" -f $_.Name, $_.Length)
}
Write-Host ""
Write-Host "  NEXT STEP" -ForegroundColor Yellow
Write-Host "  Read summary.txt first. Then share either:"
Write-Host "    - summary.txt + tree.txt  (small, paste straight into chat), or"
Write-Host "    - the whole gta4-inventory folder (commit it, or paste the text)."
Write-Host ""
Write-Host "  Do NOT upload the game itself, and do not commit web/assets or web/data."
Write-Host ""
