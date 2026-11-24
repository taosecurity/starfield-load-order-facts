<#
.SYNOPSIS
  Copy Starfield's load-order files after one test step, with times and checksums.

.DESCRIPTION
  Copies Plugins.txt and ContentCatalog.txt (by default from %LOCALAPPDATA%\Starfield) and StarfieldCustom.ini (by
  default from Documents\My Games\Starfield) into <OutDir>\<Step>\, and writes info.txt there with each file's modified time,
  size and SHA256. It only reads those files, except with -AddMarker.

  -AddMarker (use it on the first step only) backs up Plugins.txt to <OutDir>\Plugins.txt.backup, then adds one
  comment line. The game ignores lines that start with #, but when it rewrites Plugins.txt it writes only its own
  header and plugin lines, so the marker disappearing means the game rewrote the file. If the marker is still in
  Plugins.txt, the test is already running: the marker isn't added twice, and the backup is kept (or made from the
  file without the marker if it's missing). Otherwise a new test starts: the earlier test's backup and step folders
  move into <OutDir>\earlier-test-<date and time>, and a fresh backup is made.

  -PluginsDir, -CatalogDir and -IniDir change where Plugins.txt, ContentCatalog.txt and StarfieldCustom.ini are
  read from. MO2 users: close MO2 and keep the defaults. MO2 (2.5.2 and the 2.5.3 betas) never deploys, keeps its
  own plugins.txt in its profile, and keeps no copy of ContentCatalog.txt there.

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
  [string]$OutDir = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'PluginsTxtTest'),
  # Folder that holds Plugins.txt.
  [string]$PluginsDir = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Starfield'),
  # Folder that holds ContentCatalog.txt.
  [string]$CatalogDir = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Starfield'),
  # Folder that holds StarfieldCustom.ini.
  [string]$IniDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Starfield')
)
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$timeFmt = 'yyyy-MM-dd HH\:mm\:ss'   # literal colons on every regional setting (compare_snapshots.py reads them)
$log = Join-Path $OutDir 'snapshot.log'
# Every path goes through -LiteralPath, so [ and ] in a user name or folder are not read as wildcards.

function Write-Log([string]$Text) {
  Write-Verbose $Text
  if ($VerbosePreference -ne 'SilentlyContinue') {
    try {
      if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
      Add-Content -LiteralPath $log -Value "$((Get-Date).ToString($timeFmt, $inv)) [$Step] $Text"
    } catch { Write-Verbose "Could not write ${log}: $($_.Exception.Message)" }
  }
}

function Stop-Snapshot([string]$Text, [int]$Code) {
  [Console]::Error.WriteLine("PluginsTxtSnapshot: $Text")
  Write-Log "FAILED (exit $Code): $Text"
  exit $Code
}

$reserved = '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$'
$ownFiles = '^(snapshot\.log|compare\.log|Plugins\.txt\.backup.*)$'
if ($Step -notmatch '^[A-Za-z0-9._-]+$' -or $Step -notmatch '[A-Za-z0-9]' -or $Step.EndsWith('.') -or
    $Step -match $reserved -or $Step -match $ownFiles) {
  Stop-Snapshot ("step name '$Step' must use letters, digits, dots, dashes and underscores, contain a letter or " +
                 "digit, not end with a dot, and not be a reserved Windows name (such as CON) or a file name this " +
                 "script uses (snapshot.log, Plugins.txt.backup). Example: 01-menu.") 2
}

$app   = $PluginsDir
$docs  = $IniDir
$latin1 = [Text.Encoding]::GetEncoding(28591)   # maps every byte to one character and back unchanged
$files = @(
  (Join-Path $app  'Plugins.txt'),
  (Join-Path $catalogDir 'ContentCatalog.txt'),
  (Join-Path $docs 'StarfieldCustom.ini')
)
$plugins = $files[0]
$marker  = '# PluginsTxtSnapshot marker - safe to delete'
$out     = Join-Path $OutDir $Step

try {
  New-Item -ItemType Directory -Force -Path $out | Out-Null
} catch {
  Stop-Snapshot "could not create $out ($($_.Exception.Message)). Pick another folder with -OutDir." 1
}

function Test-Marker([string]$Path) {
  # True or False, or 'unknown' when the file is missing or can't be read.
  try {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'unknown' }
    return [bool]((Get-Content -LiteralPath $Path) | Where-Object { $_.Trim() -eq $marker })
  } catch { return 'unknown' }
}

Write-Log "Output folder: $out"
Write-Log "Reading Plugins.txt from $app; ContentCatalog.txt from $catalogDir; StarfieldCustom.ini from $docs"

if ($AddMarker) {
  if (-not (Test-Path -LiteralPath $plugins -PathType Leaf)) {
    Stop-Snapshot "no Plugins.txt at $plugins. Start Starfield once so it creates the file, then run this again." 1
  }
  $backup = Join-Path $OutDir 'Plugins.txt.backup'
  $hasMarker = Test-Marker $plugins
  if ($hasMarker -is [string]) {   # 'unknown' (a plain -eq would also match $true)
    Stop-Snapshot "could not read $plugins. Close the game and your mod manager, then try again." 1
  }
  try {
    if ($hasMarker) {
      Write-Host "The marker line is already in Plugins.txt, so this test is still running: the marker isn't added again."
      if (Test-Path -LiteralPath $backup -PathType Leaf) {
        Write-Host "Kept the backup at $backup."
        Write-Log "Marker already present; backup kept"
      } else {
        # No backup here (new folder, or it was deleted): save the file without the marker line, which is the original.
        # Remove only the marker line, byte for byte, so the encoding and line endings stay as they were.
        $text = [IO.File]::ReadAllText($plugins, $latin1)
        $orig = [regex]::Replace($text, '(?m)^[ \t]*' + [regex]::Escape($marker) + '[ \t]*(\r?\n|$)', '')
        [IO.File]::WriteAllText($backup, $orig, $latin1)
        Write-Host ("No backup was in this folder, so saved Plugins.txt without the marker line to $backup. It matches " +
                    "the original unless the original's last line had no line break (the game always writes one).")
        Write-Log "Marker already present; backup made from the file without the marker"
      }
    } else {
      # A new test starts: move the earlier test's backup and step folders into a dated folder, so the
      # comparison never mixes two tests. (compare_snapshots.py only reads folders that hold info.txt.)
      $earlierSteps = @(Get-ChildItem -LiteralPath $OutDir -Directory |
                        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'info.txt') })
      if ((Test-Path -LiteralPath $backup) -or $earlierSteps.Count -gt 0) {
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss', $inv)
        $archive = Join-Path $OutDir "earlier-test-$stamp"
        $n = 1
        while (Test-Path -LiteralPath $archive) { $archive = Join-Path $OutDir "earlier-test-$stamp-$n"; $n++ }
        New-Item -ItemType Directory -Path $archive | Out-Null
        if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $archive }
        foreach ($d in $earlierSteps) { Move-Item -LiteralPath $d.FullName -Destination $archive }
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        Write-Host "Moved the earlier test's backup and $($earlierSteps.Count) step folder(s) to $archive."
        Write-Log "Earlier test moved to $archive"
      }
      Copy-Item -LiteralPath $plugins -Destination $backup
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
  if (Test-Path -LiteralPath $copy) { Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue }
  if (Test-Path -LiteralPath $f -PathType Leaf) {
    try {
      Copy-Item -LiteralPath $f -Destination $copy -Force
      # Time, size and hash all come from the copy (Copy-Item keeps the modified time), so they always match.
      $i = Get-Item -LiteralPath $copy
      $line = "${name}: modified $($i.LastWriteTime.ToString($timeFmt, $inv)), ticks $($i.LastWriteTimeUtc.Ticks), $($i.Length) bytes, SHA256 $((Get-FileHash -LiteralPath $copy).Hash)"
      Write-Log "Copied $f"
    } catch {
      if (Test-Path -LiteralPath $copy) { Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue }
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
$infoFile = Join-Path $out 'info.txt'
try {
  Set-Content -LiteralPath $infoFile -Value $info
} catch {
  Stop-Snapshot "could not write $infoFile ($($_.Exception.Message)). Check that the drive has space and isn't read-only, or pick another folder with -OutDir." 1
}
$info | ForEach-Object { Write-Host $_ }
Write-Host "Saved to $out"
exit 0
