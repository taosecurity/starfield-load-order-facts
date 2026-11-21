<#
.SYNOPSIS
  Copy Starfield's load-order files after one test step, with times and checksums.

.DESCRIPTION
  Copies Plugins.txt and ContentCatalog.txt (from %LOCALAPPDATA%\Starfield) and StarfieldCustom.ini (from
  Documents\My Games\Starfield) into <OutDir>\<Step>\, and writes info.txt there with each file's modified time,
  size and SHA256. It only reads those files, except with -AddMarker.

  -AddMarker (use it on the first step only) backs up Plugins.txt to <OutDir>\Plugins.txt.backup, then adds one
  comment line. The game ignores lines that start with #, but when it rewrites Plugins.txt it writes only its own
  header and plugin lines, so the marker disappearing means the game rewrote the file. If the marker is still in
  Plugins.txt, the test is already running: the backup is kept and no second marker is added. Otherwise a new
  test starts: an older backup in the folder is renamed with its date, and a fresh backup is made.

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
$log = Join-Path $OutDir 'snapshot.log'

function Write-Log([string]$Text) {
  Write-Verbose $Text
  if ($VerbosePreference -ne 'SilentlyContinue') {
    try {
      if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
      Add-Content -Path $log -Value "$((Get-Date).ToString($timeFmt, $inv)) [$Step] $Text"
    } catch { Write-Verbose "Could not write ${log}: $($_.Exception.Message)" }
  }
}

function Stop-Snapshot([string]$Text, [int]$Code) {
  [Console]::Error.WriteLine("PluginsTxtSnapshot: $Text")
  Write-Log "FAILED (exit $Code): $Text"
  exit $Code
}

$reserved = '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$'
if ($Step -notmatch '^[A-Za-z0-9._-]+$' -or $Step -notmatch '[A-Za-z0-9]' -or $Step.EndsWith('.') -or $Step -match $reserved) {
  Stop-Snapshot ("step name '$Step' must use letters, digits, dots, dashes and underscores, contain a letter or " +
                 "digit, not end with a dot, and not be a reserved Windows name such as CON or NUL (for example 01-menu).") 2
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

try {
  New-Item -ItemType Directory -Force $out | Out-Null
} catch {
  Stop-Snapshot "could not create $out ($($_.Exception.Message)). Pick another folder with -OutDir." 1
}

function Test-Marker([string]$Path) {
  # True, False, or 'unknown' when the file can't be read.
  try {
    if (-not (Test-Path $Path)) { return $false }
    return [bool]((Get-Content $Path) | Where-Object { $_.Trim() -eq $marker })
  } catch { return 'unknown' }
}

Write-Log "Output folder: $out"
Write-Log "Reading Plugins.txt and ContentCatalog.txt from $app; StarfieldCustom.ini from $docs"

if ($AddMarker) {
  if (-not (Test-Path $plugins)) {
    Stop-Snapshot "no Plugins.txt at $plugins. Start Starfield once so it creates the file, then run this again." 1
  }
  $backup = Join-Path $OutDir 'Plugins.txt.backup'
  $hasMarker = Test-Marker $plugins
  if ($hasMarker -is [string]) {   # 'unknown' (a plain -eq would also match $true)
    Stop-Snapshot "could not read $plugins. Close the game and your mod manager, then try again." 1
  }
  try {
    if ($hasMarker) {
      Write-Host "The marker line is already in Plugins.txt, so this test is still running: kept the backup and the marker."
      Write-Log "Marker already present; backup and marker kept"
    } else {
      if (Test-Path $backup) {
        $old = Join-Path $OutDir ("Plugins.txt.backup-" + (Get-Item $backup).LastWriteTime.ToString('yyyyMMdd-HHmmss', $inv))
        Move-Item $backup $old -Force
        Write-Host "Renamed the backup from an earlier test to $old."
        Write-Log "Earlier backup renamed to $old"
      }
      Copy-Item $plugins $backup
      Write-Host "Backed up Plugins.txt to $backup."
      Write-Log "Backup written to $backup"
      # Start the marker on its own line even when the file doesn't end with a line break.
      $bytes = [IO.File]::ReadAllBytes($plugins)
      $prefix = if ($bytes.Length -gt 0 -and $bytes[-1] -ne 10) { "`r`n" } else { '' }
      [IO.File]::AppendAllText($plugins, "$prefix$marker`r`n")
      Write-Host "Added the marker line."
      Write-Log "Marker added"
    }
  } catch {
    Stop-Snapshot "could not back up or mark $plugins ($($_.Exception.Message)). Close the game and your mod manager, then try again." 1
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
  $copy = Join-Path $out $name
  # Remove a copy left by an earlier run of this step, so a failed read never leaves stale text behind.
  if (Test-Path $copy) { Remove-Item $copy -Force -ErrorAction SilentlyContinue }
  if (Test-Path $f) {
    try {
      $i = Get-Item $f
      Copy-Item $f $out -Force
      $line = "${name}: modified $($i.LastWriteTime.ToString($timeFmt, $inv)), $($i.Length) bytes, SHA256 $((Get-FileHash $copy).Hash)"
      Write-Log "Copied $f"
    } catch {
      if (Test-Path $copy) { Remove-Item $copy -Force -ErrorAction SilentlyContinue }
      $line = "${name}: could not read ($($_.Exception.Message)); take this step's snapshot again"
      Write-Log "Could not read ${f}: $($_.Exception.Message)"
    }
  } else {
    $line = "${name}: not found at $f"
    Write-Log "Not found: $f"
  }
  $info += $line
}
$info += '', "Marker line present: $(Test-Marker (Join-Path $out 'Plugins.txt'))"
$info | Set-Content (Join-Path $out 'info.txt')
$info | ForEach-Object { Write-Host $_ }
Write-Host "Saved to $out"
exit 0
