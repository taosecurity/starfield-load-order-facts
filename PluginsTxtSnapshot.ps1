<#
.SYNOPSIS
  Copy Starfield's load-order files after one test step, with times and checksums.

.DESCRIPTION
  Copies Plugins.txt and ContentCatalog.txt (from %LOCALAPPDATA%\Starfield) and StarfieldCustom.ini (from
  Documents\My Games\Starfield) into <OutDir>\<Step>\, and writes info.txt there with each file's modified time,
  size and SHA256. It only reads those files, except with -AddMarker.

  -AddMarker (use it on the first step only) backs up Plugins.txt to <OutDir>\Plugins.txt.backup, then adds one
  comment line. The game ignores lines that start with #, but when it rewrites Plugins.txt it writes only its own
  header and plugin lines, so the marker disappearing means the game rewrote the file.

  Run it from the Windows account you play on: it reads that account's own folders.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\PluginsTxtSnapshot.ps1 00-start -AddMarker

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\PluginsTxtSnapshot.ps1 01-menu -Verbose
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Step,
  [switch]$AddMarker,
  [string]$OutDir = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'PluginsTxtTest')
)
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$timeFmt = 'yyyy-MM-dd HH\:mm\:ss'   # literal colons on every regional setting (compare_snapshots.py reads them)

if ($Step -notmatch '^[A-Za-z0-9._-]+$' -or $Step -notmatch '[A-Za-z0-9]') {
  [Console]::Error.WriteLine("PluginsTxtSnapshot: step name '$Step' must use letters, digits, dots, dashes and underscores, with at least one letter or digit (for example 01-menu).")
  exit 2
}

$app   = Join-Path $env:LOCALAPPDATA 'Starfield'
$docs  = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Starfield'
$files = @(
  (Join-Path $app  'Plugins.txt'),
  (Join-Path $app  'ContentCatalog.txt'),
  (Join-Path $docs 'StarfieldCustom.ini')
)
$plugins = $files[0]
$marker  = '# PluginsTxtSnapshot marker - safe to delete'
$out     = Join-Path $OutDir $Step
$log     = Join-Path $OutDir 'snapshot.log'

try {
  New-Item -ItemType Directory -Force $out | Out-Null
} catch {
  [Console]::Error.WriteLine("PluginsTxtSnapshot: could not create $out ($($_.Exception.Message)). Pick another folder with -OutDir.")
  exit 1
}

function Write-Log([string]$Text) {
  Write-Verbose $Text
  if ($VerbosePreference -ne 'SilentlyContinue') {
    Add-Content -Path $log -Value "$((Get-Date).ToString($timeFmt, $inv)) [$Step] $Text"
  }
}

function Test-Marker {
  if (-not (Test-Path $plugins)) { return $false }
  return [bool]((Get-Content $plugins) | Where-Object { $_.Trim() -eq $marker })
}

Write-Log "Output folder: $out"
Write-Log "Reading Plugins.txt and ContentCatalog.txt from $app; StarfieldCustom.ini from $docs"

if ($AddMarker) {
  if (-not (Test-Path $plugins)) {
    [Console]::Error.WriteLine("PluginsTxtSnapshot: no Plugins.txt at $plugins. Start Starfield once so it creates the file, then run this again.")
    exit 1
  }
  $backup = Join-Path $OutDir 'Plugins.txt.backup'
  try {
    if (Test-Path $backup) {
      Write-Host "Kept the existing backup at $backup (it is not overwritten)."
      Write-Log "Backup already exists; not overwritten"
    } else {
      Copy-Item $plugins $backup
      Write-Host "Backed up Plugins.txt to $backup."
      Write-Log "Backup written to $backup"
    }
    if (Test-Marker) {
      Write-Host "The marker line is already in Plugins.txt; not adding it again."
      Write-Log "Marker already present"
    } else {
      # Start the marker on its own line even when the file doesn't end with a line break.
      $bytes = [IO.File]::ReadAllBytes($plugins)
      $prefix = if ($bytes.Length -gt 0 -and $bytes[-1] -ne 10) { "`r`n" } else { '' }
      [IO.File]::AppendAllText($plugins, "$prefix$marker`r`n")
      Write-Host "Added the marker line."
      Write-Log "Marker added"
    }
  } catch {
    [Console]::Error.WriteLine("PluginsTxtSnapshot: could not back up or mark $plugins ($($_.Exception.Message)). Close the game and your mod manager, then try again.")
    exit 1
  }
}

$info = @(
  "Step: $Step",
  "Taken: $((Get-Date).ToString($timeFmt, $inv))",
  "Starfield running: $([bool](Get-Process Starfield -ErrorAction SilentlyContinue))",
  "Vortex running: $([bool](Get-Process Vortex -ErrorAction SilentlyContinue))",
  "Mod Organizer running: $([bool](Get-Process ModOrganizer -ErrorAction SilentlyContinue))",
  ""
)
foreach ($f in $files) {
  $name = Split-Path $f -Leaf
  if (Test-Path $f) {
    try {
      $i = Get-Item $f
      Copy-Item $f $out -Force
      $line = "${name}: modified $($i.LastWriteTime.ToString($timeFmt, $inv)), $($i.Length) bytes, SHA256 $((Get-FileHash $f).Hash)"
      Write-Log "Copied $f"
    } catch {
      $line = "${name}: could not read ($($_.Exception.Message)); take this step's snapshot again"
      Write-Log "Could not read ${f}: $($_.Exception.Message)"
    }
  } else {
    $line = "${name}: not found at $f"
    Write-Log "Not found: $f"
  }
  $info += $line
}
if (Test-Path $plugins) {
  $info += '', "Marker line present: $(Test-Marker)"
}
$info | Set-Content (Join-Path $out 'info.txt')
$info | ForEach-Object { Write-Host $_ }
Write-Host "Saved to $out"
exit 0
