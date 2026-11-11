<#
.SYNOPSIS
  Updates a Worldwide Trucking BeamMP server to the newest BeamNG.Earth and trucking releases, safely.

.DESCRIPTION
  Run it from the server folder (double-click update-server.bat), or let Windows run it every night (-Schedule 05:00).
  It looks for a newer BeamNG.Earth host release and a newer trucking release on GitHub. If there is one:

    1. it downloads and unpacks it into a staging folder, puts your BeamNG.Earth settings (MEET_M, SHARE_OUT_KBPS ...)
       back into BeamNG.Earth's new main.lua and your trucking settings (season, welcome, Ship Day ...) into the new
       trucking main.lua, all while the server keeps running. If anything is wrong here, it stops and the server is
       never touched;
    2. it warns everyone in chat and on Discord, and every player's game saves itself a minute before the restart;
    3. it stops the server, backs up the whole server folder (keeping the newest few backups), copies the new files
       in (never ServerConfig.toml) and starts the server again;
    4. it checks the server's log for both "plugin loaded" lines. If they don't show, it puts the backup back,
       starts the old version again and says so on Discord.

  Settings, including the Discord webhook, are in update-settings.json next to this script. It is made from
  update-settings.example.json the first time, and updates never overwrite it. See SERVER-UPDATES.md.

.PARAMETER CheckOnly
  Only says what's new. Changes nothing.
.PARAMETER Force
  Updates even when the versions match (to repair a server, or to apply changed settings).
.PARAMETER Now
  No countdown: players get about 15 seconds' warning.
.PARAMETER Minutes
  Countdown length, overriding WarningMinutes in the settings.
.PARAMETER Schedule
  Makes Windows run this script every day at this time, for example -Schedule 05:00. -Unschedule removes it.
.PARAMETER Scheduled
  Set by the scheduled task: nothing asks for a key press.
#>
[CmdletBinding()]
param(
  [switch]$CheckOnly,
  [switch]$Force,
  [switch]$Now,
  [int]$Minutes = -1,
  [string]$Schedule,
  [switch]$Unschedule,
  [switch]$Scheduled,
  [string]$SettingsFile,
  # For testing: a folder with earth.json and trucking.json (GitHub's release JSON) to use instead of GitHub.
  [string]$ReleasesFrom,
  # For testing: defines the functions below and does nothing else.
  [switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Windows PowerShell downloads very slowly while it draws a progress bar

$EarthRepo = 'TecnaGamer/BeamNG.Earth'
$TruckingRepo = 'MadMerick01/BeamNG-Worldwide-Trucking-Career-Dangerous-Contracts'
$TaskName = 'Worldwide Trucking server update'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

# The trucking plugin's settings (top of Resources\Server\WorldwideTrucking\main.lua) that an update keeps as you set them.
$DefaultTruckingSettings = @('W.SEASON', 'W.WELCOME', 'W.STATS_REPO', 'W.STATS_BRANCH', 'W.STATS_EVERY_SECONDS',
  'W.SHIP_START', 'W.SHIP_EVERY_HOURS', 'W.SHIP_CONTAINERS', 'W.PORTS', 'W.SHIP_NAMES', 'W.REQUIRE_LATEST',
  'W.ANNOUNCE', 'W.ANNOUNCE_EVERY_MINUTES')
# Folders that updates never replace and that are too big to back up every time (BeamNG.Earth's shared road store
# can grow to 2 GB, and baked packs are yours).
$Untouched = @('Resources/Server/BeamNGEarth/store', 'Resources/Server/BeamNGEarth/bake')

# ----- Small helpers -------------------------------------------------------------------------------------------------

function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path, $Utf8) }
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $Utf8) }
function Say([string]$Text) { Write-Host ('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $Text) }
function Unix-Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

# Finds a top-level Lua assignment such as "W.SEASON = 1" or a whole table "W.PORTS = { ... }" that may run over
# many lines. Strings and -- comments are skipped, so braces inside them don't count. Returns @{Start; Length}.
function Find-LuaAssignment([string]$Text, [string]$Name) {
  $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '[ \t]*=')
  if (-not $m.Success) { return $null }
  $i = $m.Index + $m.Length
  $n = $Text.Length
  $depth = 0
  while ($i -lt $n) {
    $ch = $Text[$i]
    if ($ch -eq [char]39 -or $ch -eq [char]34) {
      $quote = $ch
      $i++
      while ($i -lt $n -and $Text[$i] -ne $quote -and $Text[$i] -ne "`n") {
        if ($Text[$i] -eq [char]92) { $i++ }
        $i++
      }
      $i++
      continue
    }
    if ($ch -eq '-' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '-') {
      while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }
      continue
    }
    if ($ch -eq '{') { $depth++ }
    elseif ($ch -eq '}') { $depth-- }
    elseif ($ch -eq "`n" -and $depth -le 0) { break }
    $i++
  }
  if ($i -gt $n) { $i = $n }
  $end = $i
  if ($end -gt $m.Index -and $Text[$end - 1] -eq "`r") { $end-- }
  return @{ Start = $m.Index; Length = $end - $m.Index }
}

# Puts the named settings from the old main.lua into the new one. Returns @{ Text; Carried = names }.
function Copy-LuaSettings([string]$Old, [string]$New, [string[]]$Names) {
  $carried = @()
  foreach ($name in $Names) {
    $a = Find-LuaAssignment $Old $name
    $b = Find-LuaAssignment $New $name
    if ($null -eq $a -or $null -eq $b) { continue }
    $was = $Old.Substring($a.Start, $a.Length)
    if ($New.Substring($b.Start, $b.Length) -ne $was) {
      $New = $New.Substring(0, $b.Start) + $was + $New.Substring($b.Start + $b.Length)
      $carried += $name
    }
  }
  return @{ Text = $New; Carried = $carried }
}

# Sets values in BeamNG.Earth's main.lua, such as G.MEET_M = 100000000. Throws if a setting isn't there, so a
# BeamNG.Earth update that renames one stops the update before the server is touched.
function Set-LuaValues([string]$Text, $Values) {
  foreach ($p in $Values.GetEnumerator()) {
    $key = [string]$p.Key
    $value = [string]$p.Value
    $re = New-Object System.Text.RegularExpressions.Regex(('(?m)^([ \t]*' + [regex]::Escape($key) + '[ \t]*=[ \t]*)(''[^''\r\n]*''|"[^"\r\n]*"|[^\s]+)'))
    if (-not $re.IsMatch($Text)) { throw "BeamNG.Earth's main.lua has no setting $key any more." }
    $Text = $re.Replace($Text, { param($m) $m.Groups[1].Value + $value }, 1)
  }
  return $Text
}

# Settings from update-settings.json, as a hashtable with every default filled in.
function Read-Settings([string]$Path) {
  $s = @{
    ServerFolder = ''; BackupFolder = ''; KeepBackups = 5; WarningMinutes = 10
    UpdateEarth = $true; UpdateTrucking = $true; EarthDevBuilds = $false; EarthMinAgeHours = 0
    EarthSettings = [ordered]@{ 'G.MEET_M' = '100000000'; 'G.SHARE_OUT_KBPS' = '256' }
    TruckingSettings = $DefaultTruckingSettings
    DiscordWebhook = ''; StartSeconds = 120; LogFile = 'Server.log'
    ServerExe = $(if ($OnWindows) { 'BeamMP-Server.exe' } else { 'BeamMP-Server' })
    MustSeeInLog = @('[BeamNG.Earth] plugin loaded', '[Trucking] plugin loaded')
  }
  if ($Path -and (Test-Path -LiteralPath $Path)) {
    $json = (Read-Text $Path) | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) {
      if ($p.Name -like '_*') { continue }   # notes
      if ($p.Name -eq 'EarthSettings' -and $null -ne $p.Value) {
        $e = [ordered]@{}
        foreach ($q in $p.Value.PSObject.Properties) { $e[$q.Name] = [string]$q.Value }
        $s.EarthSettings = $e
      } else { $s[$p.Name] = $p.Value }
    }
  }
  return $s
}

function Test-Skipped([string]$Rel, [string[]]$Skip) {
  $r = $Rel -replace '\\', '/'
  foreach ($x in $Skip) { if ($x -and ($r -eq $x -or $r.StartsWith($x + '/'))) { return $true } }
  return $false
}

# Every file under Root, as paths relative to it with /, never going into a skipped folder.
function Get-TreeFiles([string]$Root, [string[]]$Skip = @(), [string]$Rel = '') {
  $here = if ($Rel) { Join-Path $Root $Rel } else { $Root }
  foreach ($item in @(Get-ChildItem -LiteralPath $here -Force)) {
    $r = if ($Rel) { $Rel + '/' + $item.Name } else { $item.Name }
    if (Test-Skipped $r $Skip) { continue }
    if ($item.PSIsContainer) { Get-TreeFiles $Root $Skip $r } else { $r }
  }
}

function Copy-Tree([string]$From, [string]$To, [string[]]$Skip = @()) {
  foreach ($rel in @(Get-TreeFiles $From $Skip)) {
    $dest = Join-Path $To $rel
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $From $rel) -Destination $dest -Force
  }
}

# Makes To the same as From (outside the skipped folders): copies everything back and removes what wasn't there.
function Restore-Tree([string]$From, [string]$To, [string[]]$Skip = @()) {
  $keep = @{}
  foreach ($rel in @(Get-TreeFiles $From $Skip)) { $keep[$rel] = $true }
  foreach ($rel in @(Get-TreeFiles $To $Skip)) {
    if (-not $keep.ContainsKey($rel)) { Remove-Item -LiteralPath (Join-Path $To $rel) -Force }
  }
  Copy-Tree $From $To $Skip
}

# Reads a log the server still has open.
function Read-Log([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return '' }
  $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  try { (New-Object IO.StreamReader($fs, $Utf8)).ReadToEnd() } finally { $fs.Dispose() }
}

function Get-ServerProcess([string]$Exe) {
  $windows = $OnWindows
  $list = if ($windows) { @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Exe)) -ErrorAction SilentlyContinue) }
          else { @(Get-Process) }
  $list | Where-Object {
    try { $_.Path -eq $Exe -or ((-not $windows) -and $_.CommandLine -and $_.CommandLine.Contains($Exe)) } catch { $false }
  }
}

function Send-Discord([string]$Hook, [string]$Text) {
  if (-not $Hook) { return }
  try {
    $body = @{ username = 'Trucking server'; content = $Text } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post -Uri $Hook -ContentType 'application/json; charset=utf-8' `
      -Body $Utf8.GetBytes($body) | Out-Null
  } catch { Say "Couldn't post to Discord: $($_.Exception.Message)" }
}

# The newest release of a repo: @{ Tag; Version; Url; Asset; Published }, or $null when it has no matching download.
function Get-Release([string]$Repo, [string]$AssetPattern, [bool]$Dev, [string]$OfflineFile) {
  if ($OfflineFile) {
    $rel = (Read-Text $OfflineFile) | ConvertFrom-Json
  } else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'worldwide-trucking-server-updater'; 'Accept' = 'application/vnd.github+json' }
    if ($Dev) {
      $rel = @(Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=20" -Headers $headers -UseBasicParsing) |
        ForEach-Object { $_ } | Where-Object { -not $_.draft } | Select-Object -First 1
    } else {
      $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -UseBasicParsing
    }
  }
  $asset = @($rel.assets) | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
  if (-not $asset) { return $null }
  return @{
    Tag = [string]$rel.tag_name; Version = ([string]$rel.tag_name -replace '^v', '')
    Url = [string]$asset.browser_download_url; Asset = [string]$asset.name
    Published = if ($rel.published_at) { ([datetime]$rel.published_at).ToLocalTime() } else { Get-Date }
  }
}

function Save-Download([string]$Url, [string]$Path) {
  if ($Url -match '^https?://') {
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -Headers @{ 'User-Agent' = 'worldwide-trucking-server-updater' }
  } else { Copy-Item -LiteralPath $Url -Destination $Path -Force }
}

# The folder in an unpacked zip that holds its Resources folder (the zip itself, or a single folder inside it).
function Get-ZipRoot([string]$Dir) {
  if (Test-Path -LiteralPath (Join-Path $Dir 'Resources')) { return $Dir }
  $sub = @(Get-ChildItem -LiteralPath $Dir -Directory)
  if ($sub.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $sub[0].FullName 'Resources'))) { return $sub[0].FullName }
  throw "The download has no Resources folder: $Dir"
}

function Get-TruckingName([string]$Tag) { if ($Tag -match '^build-(\d+)$') { "trucking build $($Matches[1])" } else { "trucking $Tag" } }

# Starts the server and waits for every MustSeeInLog line in its log. True when they all showed.
function Start-AndCheck {
  if (Test-Path -LiteralPath $LogPath) { Move-Item -LiteralPath $LogPath -Destination ($LogPath + '.before-update') -Force }
  Say 'Starting the server'
  if (-not $OnWindows) { & chmod +x -- $Exe }   # unzipping loses it on Linux
  if ($OnWindows) {
    $proc = Start-Process -FilePath $Exe -WorkingDirectory $ServerDir -PassThru   # in a window of its own
  } else {
    $proc = Start-Process -FilePath $Exe -WorkingDirectory $ServerDir -PassThru `
      -RedirectStandardOutput (Join-Path $ServerDir 'console.txt') -RedirectStandardError (Join-Path $ServerDir 'console-errors.txt')
  }
  $deadline = (Get-Date).AddSeconds([int]$S.StartSeconds)
  $missing = @($S.MustSeeInLog)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $log = Read-Log $LogPath
    $missing = @($S.MustSeeInLog | Where-Object { -not $log.Contains($_) })
    if ($missing.Count -eq 0) { return $true }
    if ($proc.HasExited) { Say 'The server closed by itself.'; return $false }
  }
  Say ('Not in the log after ' + $S.StartSeconds + ' seconds: ' + ($missing -join ', '))
  return $false
}

if ($LibraryOnly) { return }

# ----- The update ----------------------------------------------------------------------------------------------------

$here = Split-Path -Parent $PSCommandPath
if (-not $SettingsFile) { $SettingsFile = Join-Path $here 'update-settings.json' }
if (-not (Test-Path -LiteralPath $SettingsFile)) {
  $example = Join-Path $here 'update-settings.example.json'
  if (Test-Path -LiteralPath $example) {
    Copy-Item -LiteralPath $example -Destination $SettingsFile
    Write-Host "Made $SettingsFile from the example. Open it in Notepad to add your Discord webhook."
  }
}
$S = Read-Settings $SettingsFile

$ServerDir = if ($S.ServerFolder) { $S.ServerFolder } else { $here }
$ServerDir = (Resolve-Path -LiteralPath $ServerDir).Path.TrimEnd('\', '/')
$BackupDir = if ($S.BackupFolder) { $S.BackupFolder } else { $ServerDir + '-backups' }
if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
$BackupDir = (Resolve-Path -LiteralPath $BackupDir).Path.TrimEnd('\', '/')
$Exe = Join-Path $ServerDir $S.ServerExe
if (-not (Test-Path -LiteralPath $Exe)) {
  # Never update a folder that isn't a server: the script would fill it with server files.
  Write-Host "There's no $($S.ServerExe) in $ServerDir, so this isn't a server folder."
  Write-Host 'Put the script in your server folder, or set "ServerFolder" in update-settings.json. See SERVER-UPDATES.md.'
  exit 2
}
$LogPath = Join-Path $ServerDir $S.LogFile
$StatePath = Join-Path $ServerDir 'update-state.json'
$RestartPath = Join-Path $ServerDir 'Resources/Server/WorldwideTrucking/restart.json'
$Skip = @($Untouched)
if ($BackupDir.StartsWith($ServerDir + [IO.Path]::DirectorySeparatorChar)) {
  $Skip += ($BackupDir.Substring($ServerDir.Length + 1) -replace '\\', '/')
}

if ($Schedule -or $Unschedule) {
  if ($Unschedule) {
    schtasks.exe /Delete /F /TN $TaskName
    exit $LASTEXITCODE
  }
  $shell = (Get-Process -Id $PID).Path
  $run = "`"$shell`" -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Scheduled"
  schtasks.exe /Create /F /TN $TaskName /SC DAILY /ST $Schedule /TR $run
  if ($LASTEXITCODE -eq 0) { Write-Host "Windows will check for server updates every day at $Schedule." }
  exit $LASTEXITCODE
}

$transcript = $false
if (-not $CheckOnly) {
  try { Start-Transcript -Path (Join-Path $BackupDir 'update-log.txt') -Append | Out-Null; $transcript = $true } catch { }
}
$exitCode = 0
$countdown = $false
$touched = $false
$backup = $null
$backedUp = $false
try {
  # --- What's new
  $state = @{ earth = ''; trucking = '' }
  if (Test-Path -LiteralPath $StatePath) {
    $j = (Read-Text $StatePath) | ConvertFrom-Json
    $state.earth = [string]$j.earth; $state.trucking = [string]$j.trucking
  }
  $earth = $null; $trucking = $null
  if ($S.UpdateEarth) {
    $hostZip = if ($OnWindows) { '^BeamNG\.Earth-Host-.+-Windows\.zip$' } else { '^BeamNG\.Earth-Host-.+-Linux-x86_64\.zip$' }
    $earth = Get-Release $EarthRepo $hostZip ([bool]$S.EarthDevBuilds) `
      $(if ($ReleasesFrom) { Join-Path $ReleasesFrom 'earth.json' })
    if (-not $earth) { Say 'The newest BeamNG.Earth release has no host zip for this system yet. Skipping BeamNG.Earth.' }
    elseif ($earth.Tag -eq $state.earth -and -not $Force) { $earth = $null }
    elseif (((Get-Date) - $earth.Published).TotalHours -lt [double]$S.EarthMinAgeHours) {
      Say "BeamNG.Earth $($earth.Version) is newer than $($S.EarthMinAgeHours) hours. Waiting for it to settle."
      $earth = $null
    }
  }
  if ($S.UpdateTrucking) {
    $trucking = Get-Release $TruckingRepo '^worldwide-trucking-server\.zip$' $false `
      $(if ($ReleasesFrom) { Join-Path $ReleasesFrom 'trucking.json' })
    if (-not $trucking) { Say 'The newest trucking release has no server download. Skipping trucking.' }
    elseif ($trucking.Tag -eq $state.trucking -and -not $Force) { $trucking = $null }
  }
  $was = @()
  if ($state.earth) { $was += "BeamNG.Earth $($state.earth -replace '^v', '')" }
  if ($state.trucking) { $was += (Get-TruckingName $state.trucking) }
  $what = @()
  if ($earth) { $what += "BeamNG.Earth $($earth.Version)" }
  if ($trucking) { $what += (Get-TruckingName $trucking.Tag) }
  if ($what.Count -eq 0) {
    Say ('Up to date' + $(if ($was.Count) { ': ' + ($was -join ' and ') } else { '.' }))
    return
  }
  $whatText = $what -join ' and '
  Say ("New: $whatText" + $(if ($was.Count) { " (this server has " + ($was -join ' and ') + ')' } else { " (this server's versions aren't known yet)" }))
  if ($CheckOnly) { return }

  # --- Download and prepare everything while the server keeps running
  $stage = Join-Path $BackupDir 'staging'
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
  $merged = Join-Path $stage 'new'
  New-Item -ItemType Directory -Path $merged -Force | Out-Null
  if ($earth) {
    Say "Downloading $($earth.Asset)"
    $zip = Join-Path $stage 'earth.zip'
    Save-Download $earth.Url $zip
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $stage 'earth') -Force
    $root = Get-ZipRoot (Join-Path $stage 'earth')
    foreach ($need in @($S.ServerExe, 'Resources/Server/BeamNGEarth/main.lua')) {
      if (-not (Test-Path -LiteralPath (Join-Path $root $need))) { throw "The BeamNG.Earth download has no $need." }
    }
    # Never ServerConfig.toml: it has your AuthKey and server name, and the zip's own has an empty key.
    Copy-Tree $root $merged @('ServerConfig.toml')
    $lua = Join-Path $merged 'Resources/Server/BeamNGEarth/main.lua'
    Write-Text $lua (Set-LuaValues (Read-Text $lua) $S.EarthSettings)
    Say ('BeamNG.Earth settings put back: ' + (($S.EarthSettings.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }) -join ', '))
  }
  if ($trucking) {
    Say "Downloading $($trucking.Asset)"
    $zip = Join-Path $stage 'trucking.zip'
    Save-Download $trucking.Url $zip
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $stage 'trucking') -Force
    $root = Get-ZipRoot (Join-Path $stage 'trucking')
    foreach ($need in @('Resources/Server/WorldwideTrucking/main.lua', 'Resources/Client/worldwide-trucking-dangerous-contracts.zip')) {
      if (-not (Test-Path -LiteralPath (Join-Path $root $need))) { throw "The trucking download has no $need." }
    }
    Copy-Tree $root $merged @('update-settings.json')
    $old = Join-Path $ServerDir 'Resources/Server/WorldwideTrucking/main.lua'
    if (Test-Path -LiteralPath $old) {
      $lua = Join-Path $merged 'Resources/Server/WorldwideTrucking/main.lua'
      $c = Copy-LuaSettings (Read-Text $old) (Read-Text $lua) ([string[]]$S.TruckingSettings)
      Write-Text $lua $c.Text
      if ($c.Carried.Count) { Say ('Your trucking settings kept: ' + ($c.Carried -join ', ')) }
    }
  }

  # --- Warn everyone, and let every game save
  $running = @(Get-ServerProcess $Exe).Count -gt 0
  $wait = if ($Now) { 0 } elseif ($Minutes -ge 0) { $Minutes } else { [int]$S.WarningMinutes }
  if ($running) {
    $at = (Unix-Now) + 60 * $wait
    # The trucking plugin reads this: it warns everyone in chat, has every game save, then sends everyone off and
    # deletes the file. Without the plugin (or an old one), the script just waits for the time.
    if (Test-Path -LiteralPath (Split-Path -Parent $RestartPath)) {
      Write-Text $RestartPath (@{ at = $at; why = $whatText } | ConvertTo-Json -Compress)
      $countdown = $true
    }
    Send-Discord $S.DiscordWebhook ("**Server update** in about $wait minute(s): $whatText. Careers are kept on the server. " +
      'Back in a few minutes.')
    Say "Players warned. Waiting for the server to send everyone off (up to $wait minute(s) and a bit). Ctrl+C calls the update off."
    $lastSaid = 0
    while ((-not $countdown -or (Test-Path -LiteralPath $RestartPath)) -and (Unix-Now) -lt ($at + $(if ($countdown) { 90 } else { 0 })) -and
           @(Get-ServerProcess $Exe).Count -gt 0) {
      if ((Unix-Now) - $lastSaid -ge 60) {
        $left = $at - (Unix-Now)
        if ($left -gt 0) { Say "About $([math]::Ceiling($left / 60)) minute(s) to go." }
        $lastSaid = Unix-Now
      }
      Start-Sleep -Seconds 5
    }
  }

  # --- Stop, back up, copy in, start
  $touched = $true
  foreach ($p in @(Get-ServerProcess $Exe)) {
    Say "Stopping the server (process $($p.Id))"
    Stop-Process -Id $p.Id -Force
    try { $p.WaitForExit(30000) | Out-Null } catch { }
  }
  $countdown = $false
  if (Test-Path -LiteralPath $RestartPath) { Remove-Item -LiteralPath $RestartPath -Force }
  Start-Sleep -Seconds 2
  $backup = Join-Path $BackupDir (Get-Date -Format 'yyyy-MM-dd_HHmmss')
  Say "Backing up the server folder to $backup"
  Copy-Tree $ServerDir $backup $Skip
  $backedUp = $true
  @(Get-ChildItem -LiteralPath $BackupDir -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{6}$' } |
    Sort-Object Name -Descending | Select-Object -Skip ([int]$S.KeepBackups)) |
    ForEach-Object { Say "Removing old backup $($_.Name)"; Remove-Item -LiteralPath $_.FullName -Recurse -Force }

  Say 'Copying in the new files'
  Copy-Tree $merged $ServerDir

  if (Start-AndCheck) {
    $newState = @{ earth = $(if ($earth) { $earth.Tag } else { $state.earth }); trucking = $(if ($trucking) { $trucking.Tag } else { $state.trucking }); updated = (Get-Date -Format 's') }
    Write-Text $StatePath ($newState | ConvertTo-Json)
    Say "Done. The server is up on $whatText."
    $msg = "**The server is back up** with $whatText."
    if ($earth) { $msg += " Update your BeamNG.Earth app to **$($earth.Version)** before joining." }
    if ($trucking) { $msg += ' The trucking mod updates itself when you join.' }
    Send-Discord $S.DiscordWebhook $msg
  } else {
    $exitCode = 1
    $failed = Join-Path $BackupDir ('failed-' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '.log')
    if (Test-Path -LiteralPath $LogPath) { Copy-Item -LiteralPath $LogPath -Destination $failed -Force; Say "The failed start's log is in $failed" }
    foreach ($p in @(Get-ServerProcess $Exe)) { Stop-Process -Id $p.Id -Force; try { $p.WaitForExit(30000) | Out-Null } catch { } }
    Start-Sleep -Seconds 2
    Say 'The new version did not start properly. Putting the backup back.'
    Restore-Tree $backup $ServerDir $Skip
    if (Start-AndCheck) {
      Say 'The server is back up on the old version.'
      Send-Discord $S.DiscordWebhook "The update to $whatText didn't work, so **the server is back up on the version it had**. Join as usual."
    } else {
      $exitCode = 3
      Say 'The old version did not start either. Check the server window and the log.'
      Send-Discord $S.DiscordWebhook 'The server update went wrong and the server is down for now. It will be back as soon as it is fixed.'
    }
  }
} catch {
  Say "Update stopped: $($_.Exception.Message)"
  if (-not $touched) {
    $exitCode = 2
    Say 'The server was not changed.'
  } else {
    # Something broke after the server stopped: put the backup back, if there is one, and start it.
    $exitCode = 3
    try {
      foreach ($p in @(Get-ServerProcess $Exe)) { Stop-Process -Id $p.Id -Force; try { $p.WaitForExit(30000) | Out-Null } catch { } }
      # Only a whole backup: putting back half of one would delete files.
      if ($backedUp) {
        Say 'Putting the backup back.'
        Restore-Tree $backup $ServerDir $Skip
      }
      if (Start-AndCheck) {
        $exitCode = 1
        Say 'The server is back up on the old version.'
        Send-Discord $S.DiscordWebhook "The update to $whatText didn't work, so **the server is back up on the version it had**. Join as usual."
      } else {
        Say 'The server did not start. Check the server window and the log.'
        Send-Discord $S.DiscordWebhook 'The server update went wrong and the server is down for now. It will be back as soon as it is fixed.'
      }
    } catch { Say "Couldn't put the old version back: $($_.Exception.Message)" }
  }
} finally {
  # Called off (Ctrl+C or an error) before the server stopped: the plugin tells everyone it's off.
  if ($countdown -and (Test-Path -LiteralPath $RestartPath)) {
    Remove-Item -LiteralPath $RestartPath -Force -ErrorAction SilentlyContinue
    Send-Discord $S.DiscordWebhook 'The server update is called off. Carry on trucking!'
  }
  if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
}
exit $exitCode
