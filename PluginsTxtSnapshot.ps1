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

if ($Step -notmatch '^[A-Za-z0-9._-]+$') {
  [Console]::Error.WriteLine("PluginsTxtSnapshot: step name '$Step' can only use letters, digits, dots, dashes and underscores (for example 01-menu).")
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

New-Item -ItemType Directory -Force $out | Out-Null

function Write-Log([string]$Text) {
  Write-Verbose $Text
  if ($VerbosePreference -ne 'SilentlyContinue') {
    Add-Content -Path $log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Step] $Text"
  }
}

Write-Log "Output folder: $out"
Write-Log "Reading Plugins.txt and ContentCatalog.txt from $app; StarfieldCustom.ini from $docs"

if ($AddMarker) {
  if (-not (Test-Path $plugins)) {
    [Console]::Error.WriteLine("PluginsTxtSnapshot: no Plugins.txt at $plugins. Start Starfield once so it creates the file, then run this again.")
    exit 1
  }
  $backup = Join-Path $OutDir 'Plugins.txt.backup'
  Copy-Item $plugins $backup -Force
  Add-Content -Path $plugins -Value $marker
  Write-Host "Backed up Plugins.txt to $backup and added the marker line."
  Write-Log "Marker added; backup at $backup"
}

$info = @(
  "Step: $Step",
  "Taken: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
  "Starfield running: $([bool](Get-Process Starfield -ErrorAction SilentlyContinue))",
  "Vortex running: $([bool](Get-Process Vortex -ErrorAction SilentlyContinue))",
  "Mod Organizer running: $([bool](Get-Process ModOrganizer -ErrorAction SilentlyContinue))",
  ""
)
foreach ($f in $files) {
  if (Test-Path $f) {
    $i = Get-Item $f
    Copy-Item $f $out -Force
    $line = "$($i.Name): modified $($i.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')), $($i.Length) bytes, SHA256 $((Get-FileHash $f).Hash)"
    Write-Log "Copied $f"
  } else {
    $line = "$(Split-Path $f -Leaf): not found at $f"
    Write-Log "Not found: $f"
  }
  $info += $line
}
if (Test-Path $plugins) {
  $info += '', "Marker line present: $((Get-Content $plugins) -contains $marker)"
}
$info | Set-Content (Join-Path $out 'info.txt')
$info | ForEach-Object { Write-Host $_ }
Write-Host "Saved to $out"
exit 0
