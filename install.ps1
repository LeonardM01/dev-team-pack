# Usage:
#   .\install.ps1 [TargetDir] [-Force] [-Reconfigure]
#
#   TargetDir      Directory to install dev-team-pack into (default: current directory)
#   -Force         Reinstall even if up to date; overwrite conflicting files
#   -Reconfigure   Accepted for parity with install.sh; currently a no-op — this
#                  script has no tool/MCP selection prompts to re-open
#
#   Environment variables:
#     $env:DEV_TEAM_REPO   Git repo URL (default: https://github.com/LeonardM01/dev-team-pack.git)
#     $env:DEV_TEAM_REF    Branch/tag/ref to fetch (default: main)
#     $env:DEV_TEAM_FORCE  Set to 1 for -Force
#
#   Examples:
#     .\install.ps1
#     .\install.ps1 C:\projects\my-app
#     .\install.ps1 -Force C:\projects\my-app
#     $env:DEV_TEAM_REF = 'v2.0'; .\install.ps1 C:\projects\my-app

param(
  [string]$TargetDir = $PWD.Path,
  [switch]$Force,
  [switch]$Reconfigure
)

$ErrorActionPreference = 'Stop'

$REPO_URL = if ($env:DEV_TEAM_REPO) { $env:DEV_TEAM_REPO } else { 'https://github.com/LeonardM01/dev-team-pack.git' }
$REF      = if ($env:DEV_TEAM_REF)  { $env:DEV_TEAM_REF  } else { 'main' }
$TARGET   = $TargetDir

$FORCE = $Force.IsPresent -or ($env:DEV_TEAM_FORCE -eq '1')
$STATE_PATH = Join-Path $TARGET '.dev-team-pack.json'

$script:Mode      = 'install'
$script:StateOld  = @{}
$script:StateNew  = @{}
$script:Conflicts = New-Object System.Collections.Generic.List[string]
# Conflicts recorded by the previous run, and keys this run reclassified as
# something other than an open conflict. Write-PackState persists
# Conflicts + (PrevConflicts - ResolvedConflicts), so a conflict in a step this
# run did not reach survives, while one that genuinely resolved is dropped.
$script:PrevConflicts     = New-Object System.Collections.Generic.List[string]
$script:ResolvedConflicts = New-Object System.Collections.Generic.List[string]
$script:Counters  = @{ Added = 0; Updated = 0; Kept = 0; Conflict = 0 }
$script:StateMeta = $null

function Write-Log {
  param([string]$Message)
  Write-Host "[dev-team-pack] $Message"
}

function Invoke-Die {
  param([string]$Message)
  Write-Error "[dev-team-pack] ERROR: $Message"
  exit 1
}

function Require-TargetWritable {
  if (-not (Test-Path $TARGET)) {
    New-Item -ItemType Directory -Path $TARGET -Force | Out-Null
  }
  $testFile = Join-Path $TARGET '.dev-team-write-test'
  try {
    [System.IO.File]::WriteAllText($testFile, '')
    Remove-Item $testFile -Force
  } catch {
    Invoke-Die "Target directory is not writable: $TARGET"
  }
}

function Get-WorkDir {
  $work = [System.IO.Path]::GetTempPath()
  $work = Join-Path $work ([System.IO.Path]::GetRandomFileName())
  New-Item -ItemType Directory -Path $work -Force | Out-Null
  return $work
}

function Fetch-Pack {
  param([string]$Work)

  $hasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)

  if ($hasGit) {
    # git clone always writes progress to stderr, even on success. In Windows
    # PowerShell 5.1 a native command's stderr redirected into a pipeline
    # becomes an ErrorRecord, and with $ErrorActionPreference = 'Stop' that
    # raises a terminating NativeCommandError on a SUCCESSFUL clone. Relax the
    # preference for the duration of the call and rely on $LASTEXITCODE.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $cloneOutput = git clone -c core.autocrlf=false --depth 1 --branch $REF $REPO_URL "$Work\pack" 2>&1
    } finally {
      $ErrorActionPreference = $prevEap
    }
    if ($LASTEXITCODE -eq 0) {
      return
    }
    Write-Log "git clone failed, falling back to tarball:"
    $cloneOutput | ForEach-Object { [Console]::Error.WriteLine($_) }
  }

  if (-not ($REPO_URL -match '^https?://github\.com/')) {
    Invoke-Die "DEV_TEAM_REPO must be a github.com URL when git is unavailable: $REPO_URL"
  }
  $slug = $REPO_URL -replace '^https?://github\.com/', '' -replace '\.git$', ''
  if ($slug -notmatch '.+/.+') {
    Invoke-Die "DEV_TEAM_REPO must be a github.com URL when git is unavailable: $REPO_URL"
  }

  if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
    Invoke-Die "tar.exe not found. Windows 10 version 1803+ is required. Please update Windows or install tar manually."
  }

  $tarballBase = "https://codeload.github.com/$slug/tar.gz"
  $tarPath     = Join-Path $Work "pack.tar.gz"

  $downloaded = $false
  foreach ($refPath in @("refs/heads/$REF", "refs/tags/$REF")) {
    try {
      Invoke-WebRequest -Uri "$tarballBase/$refPath" -OutFile $tarPath -UseBasicParsing
      $downloaded = $true
      break
    } catch {
    }
  }
  if (-not $downloaded) {
    Invoke-Die "ref $REF not found on $REPO_URL (tried refs/heads and refs/tags)"
  }

  tar.exe -xz -C $Work -f $tarPath
  if ($LASTEXITCODE -ne 0) {
    Invoke-Die "tar extraction failed."
  }

  $extracted = Get-ChildItem -Path $Work -Directory | Where-Object { $_.Name -like 'dev-team-pack-*' } | Select-Object -First 1
  if (-not $extracted) {
    Invoke-Die "Could not find extracted pack directory in $Work"
  }
  Rename-Item -Path $extracted.FullName -NewName 'pack'
}

function Get-Sha256File {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

function Get-Sha256String {
  param([string]$Text)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $sha   = [System.Security.Cryptography.SHA256]::Create()
  try { ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '' }
  finally { $sha.Dispose() }
}

function Get-PackVersion {
  param([string]$Work)
  $packDir = Join-Path $Work 'pack'
  if ((Test-Path (Join-Path $packDir '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $sha = git -C $packDir rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $sha) {
      return @{ Version = $sha.Trim(); Source = 'git' }
    }
  }
  # Mirror install.sh's pack_tree_hash exactly: `find .`-style relative paths
  # (./-prefixed, forward slashes), excluding only the top-level .git/ tree
  # (not any nested .git/), sorted byte-ordinally (LC_ALL=C sort — not
  # PowerShell's culture-aware default), each entry "path:hash\n" with no
  # extra separator between entries (every line, including the last, ends in
  # \n because bash's printf emits one per line), then hashed as one stream.
  $relPaths = Get-ChildItem -Path $packDir -Recurse -File -Force |
    ForEach-Object {
      $_.FullName.Substring($packDir.Length).TrimStart('\', '/') -replace '\\', '/'
    } |
    Where-Object { $_ -cnotlike '.git/*' }

  $sortedRel = @($relPaths)
  [Array]::Sort($sortedRel, [StringComparer]::Ordinal)

  $sb = New-Object System.Text.StringBuilder
  foreach ($rel in $sortedRel) {
    $full = Join-Path $packDir ($rel -replace '/', '\')
    [void]$sb.Append("./${rel}:$(Get-Sha256File $full)`n")
  }

  @{ Version = (Get-Sha256String $sb.ToString()); Source = 'tree' }
}

function Read-PackState {
  if (-not (Test-Path $STATE_PATH)) { return }
  try {
    $json = Get-Content -Raw -Path $STATE_PATH | ConvertFrom-Json
  } catch {
    Invoke-Die "Corrupt state file: $STATE_PATH (delete it to reinstall from scratch)"
  }
  if ($json.schema -gt 1) {
    Invoke-Die "State file schema $($json.schema) is newer than this installer supports (1). Update the installer and re-run."
  }
  $script:StateMeta = $json
  $script:Mode = 'update'
  if ($json.conflicts) {
    # ConvertTo-Json collapses a one-element array to a scalar in some shapes,
    # so normalise to an array before enumerating.
    foreach ($c in @($json.conflicts)) {
      if (($c -is [string]) -and $c.Trim()) { [void]$script:PrevConflicts.Add($c) }
    }
  }
  if ($json.files) {
    # Seed StateNew from StateOld: this script has no .cursor merge and no
    # tool selection, so keys it does not own (every .cursor/* entry a bash
    # run recorded) would otherwise be dropped from the state file, silently
    # untracking those files for both installers. Steps that do run overwrite
    # their seeded entries via Set-StateEntry.
    $json.files.PSObject.Properties | ForEach-Object {
      $script:StateOld[$_.Name] = $_.Value
      $script:StateNew[$_.Name] = $_.Value
    }
  }
}

function Get-StateHash {
  param([string]$Key)
  if ($script:StateOld.ContainsKey($Key)) { return $script:StateOld[$Key] }
  return $null
}

function Set-StateEntry {
  param([string]$Key, [string]$Hash)
  if ($Hash) { $script:StateNew[$Key] = $Hash }
}

# Called for every key a step classified as anything other than an open
# conflict, including a forced overwrite. Without this a conflict carried
# forward by Read-PackState would stick forever once it had been resolved.
function Resolve-ConflictEntry {
  param([string]$Key)
  if ($Key -and (-not $script:ResolvedConflicts.Contains($Key))) {
    [void]$script:ResolvedConflicts.Add($Key)
  }
}

function Write-PackState {
  param([string]$Version, [string]$Source)
  $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $installedAt = if ($script:StateMeta -and $script:StateMeta.installedAt) { $script:StateMeta.installedAt } else { $now }

  $files = [ordered]@{}
  $script:StateNew.Keys | Sort-Object | ForEach-Object { $files[$_] = $script:StateNew[$_] }

  # Fresh conflicts always win; a previously recorded one survives only if no
  # step this run reclassified it.
  $conflicts = New-Object System.Collections.Generic.List[string]
  foreach ($c in $script:Conflicts) {
    if (-not $conflicts.Contains($c)) { [void]$conflicts.Add($c) }
  }
  foreach ($c in $script:PrevConflicts) {
    if ((-not $script:ResolvedConflicts.Contains($c)) -and (-not $conflicts.Contains($c))) {
      [void]$conflicts.Add($c)
    }
  }

  $state = [ordered]@{
    schema        = 1
    repo          = $REPO_URL
    ref           = $REF
    version       = $Version
    versionSource = $Source
    installedAt   = $installedAt
    updatedAt     = $now
    conflicts     = @($conflicts | Sort-Object)
    files         = $files
  }
  # Set-Content -Encoding UTF8 emits a UTF-8 BOM on Windows PowerShell 5.1, and
  # install.sh's python3 json.load rejects a leading BOM. Write BOM-less UTF-8.
  $json = $state | ConvertTo-Json -Depth 5
  [System.IO.File]::WriteAllText($STATE_PATH, $json, (New-Object System.Text.UTF8Encoding($false)))
  Write-Log "wrote .dev-team-pack.json"
}

function Get-FileAction {
  param([string]$Key, [string]$Dest, [string]$Pack)
  $rec = Get-StateHash -Key $Key

  if (-not (Test-Path $Dest)) {
    if ($rec) { return 'skip-deleted' } else { return 'add' }
  }
  if (-not $rec) { return 'keep-untracked' }

  $disk = Get-Sha256File $Dest
  $pk   = Get-Sha256File $Pack

  if ($disk -eq $rec) {
    if ($pk -eq $rec) { return 'current' } else { return 'update' }
  } else {
    if ($pk -eq $rec) { return 'keep-local' } else { return 'conflict' }
  }
}

function Invoke-FileAction {
  param([string]$Key, [string]$Dest, [string]$Pack)
  $action = Get-FileAction -Key $Key -Dest $Dest -Pack $Pack
  $rec = Get-StateHash -Key $Key

  switch ($action) {
    'add' {
      $destDir = Split-Path $Dest -Parent
      if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
      Copy-Item -Path $Pack -Destination $Dest
      Set-StateEntry -Key $Key -Hash (Get-Sha256File $Dest)
      $script:Counters.Added++
      Write-Log "add      $Key"
    }
    'update' {
      Copy-Item -Path $Pack -Destination $Dest -Force
      Set-StateEntry -Key $Key -Hash (Get-Sha256File $Dest)
      $script:Counters.Updated++
      Write-Log "updated  $Key"
    }
    'conflict' {
      if ($FORCE) {
        Copy-Item -Path $Pack -Destination $Dest -Force
        Set-StateEntry -Key $Key -Hash (Get-Sha256File $Dest)
        $script:Counters.Updated++
        Write-Log "updated  $Key (forced over conflict)"
      } else {
        Set-StateEntry -Key $Key -Hash $rec
        $script:Counters.Conflict++
        $script:Conflicts.Add($Key)
        Write-Log "conflict $Key (modified locally, changed upstream)"
      }
    }
    'keep-local'  { Set-StateEntry -Key $Key -Hash $rec; $script:Counters.Kept++ }
    'current'     { Set-StateEntry -Key $Key -Hash $rec }
    'skip-deleted'{ Set-StateEntry -Key $Key -Hash $rec }
    'keep-untracked' {
      if ($script:Mode -eq 'install') { Set-StateEntry -Key $Key -Hash (Get-Sha256File $Dest) }
      $script:Counters.Kept++
    }
  }
  if (($action -ne 'conflict') -or $FORCE) { Resolve-ConflictEntry -Key $Key }
  return $action
}

function Merge-ClaudeDir {
  param([string]$Work)

  $srcBase = Join-Path $Work 'pack\.claude'
  if (-not (Test-Path $srcBase)) { return }

  # -Force to match Get-PackVersion's enumeration: without it hidden pack files
  # are version-hashed but never merged, so the pack looks changed forever.
  Get-ChildItem -Path $srcBase -Recurse -File -Force | ForEach-Object {
    $srcFile = $_.FullName
    $rel     = $srcFile.Substring($srcBase.Length).TrimStart('\', '/')
    $relNorm = $rel -replace '\\', '/'

    if ($relNorm -like 'agent-memory/*') {
      return
    }

    if (($_.Name -eq 'settings.local.json') -and (Test-Path (Join-Path $TARGET '.claude\settings.local.json'))) {
      Write-Log "skip .claude/$relNorm (local settings preserved)"
      return
    }

    $dest = Join-Path $TARGET ".claude\$rel"

    Invoke-FileAction -Key ".claude/$relNorm" -Dest $dest -Pack $srcFile | Out-Null
  }
}

function Merge-ClaudeMd {
  param([string]$Work)
  $packMd      = Join-Path $Work 'pack\CLAUDE.md'
  $targetMd    = Join-Path $TARGET 'CLAUDE.md'
  $beginMarker = '<!-- dev-team-pack:begin -->'
  $endMarker   = '<!-- dev-team-pack:end -->'
  $key         = 'CLAUDE.md#dev-team-pack'

  if (-not (Test-Path $packMd)) { return }

  # install.sh builds body from `$(cat pack_md)`, which strips ALL trailing
  # newlines via command substitution, then re-adds exactly one when hashing.
  # Mirror that here so the two installers compute identical hashes/bytes for
  # the same pack content.
  $packRaw     = [System.IO.File]::ReadAllText($packMd)
  $packTrimmed = $packRaw -replace '(\r?\n)+$', ''
  $body        = "# Dev Team Pack`n$packTrimmed"
  $block       = "$beginMarker`n$body`n$endMarker"
  $packHash    = Get-Sha256String "$body`n"

  if (-not (Test-Path $targetMd)) {
    [System.IO.File]::WriteAllText($targetMd, "$block`n")
    Set-StateEntry -Key $key -Hash $packHash
    Resolve-ConflictEntry -Key $key
    Write-Log "add  CLAUDE.md"
    return
  }

  $existing = [System.IO.File]::ReadAllText($targetMd)
  # Split on bare `n only (not `r?`n) so any `r attached to a line, and any
  # trailing "" element that encodes a final newline, survive round-tripping
  # through -join later — this is what keeps the splice byte-for-byte.
  $lines = $existing -split "`n"

  if (-not ($lines | Where-Object { $_ -ceq $beginMarker })) {
    [System.IO.File]::WriteAllText($targetMd, $existing + "`n`n---`n`n" + $block + "`n")
    Set-StateEntry -Key $key -Hash $packHash
    Resolve-ConflictEntry -Key $key
    Write-Log "add  CLAUDE.md (appended dev-team block)"
    return
  }

  $beginIdx = -1
  $endIdx   = -1
  for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($beginIdx -lt 0 -and $lines[$i] -ceq $beginMarker) { $beginIdx = $i; continue }
    if ($beginIdx -ge 0 -and $endIdx -lt 0 -and $lines[$i] -ceq $endMarker) { $endIdx = $i; break }
  }
  if ($beginIdx -lt 0 -or $endIdx -lt 0) {
    Write-Log "skip CLAUDE.md (dev-team-pack begin marker but no matching end marker; leaving file untouched)"
    return
  }

  $innerLines  = if ($endIdx -gt $beginIdx + 1) { $lines[($beginIdx + 1)..($endIdx - 1)] } else { @() }
  $currentBody = if ($innerLines.Length -gt 0) { ($innerLines -join "`n") + "`n" } else { "" }
  $currentHash = Get-Sha256String $currentBody
  $rec = Get-StateHash -Key $key

  if (-not $rec) {
    if ($script:Mode -eq 'install') { Set-StateEntry -Key $key -Hash $currentHash }
    Resolve-ConflictEntry -Key $key
    Write-Log "skip CLAUDE.md (block not tracked)"
    return
  }

  if ($currentHash -eq $packHash) {
    Set-StateEntry -Key $key -Hash $rec
    Resolve-ConflictEntry -Key $key
    Write-Log "skip CLAUDE.md (block already current)"
    return
  }

  if (($currentHash -ne $rec) -and (-not $FORCE)) {
    Set-StateEntry -Key $key -Hash $rec
    $script:Counters.Conflict++
    $script:Conflicts.Add($key)
    Write-Log "conflict CLAUDE.md block (edited locally, changed upstream)"
    return
  }

  $before = if ($beginIdx -gt 0) { $lines[0..($beginIdx - 1)] } else { @() }
  $after  = if ($endIdx -lt ($lines.Length - 1)) { $lines[($endIdx + 1)..($lines.Length - 1)] } else { @() }

  $newLines = @($before) + @($block -split "`n") + @($after)
  $merged   = $newLines -join "`n"

  [System.IO.File]::WriteAllText($targetMd, $merged)
  Set-StateEntry -Key $key -Hash $packHash
  Resolve-ConflictEntry -Key $key
  $script:Counters.Updated++
  Write-Log "updated CLAUDE.md dev-team block"
}

function Copy-McpJson {
  param([string]$Work)

  $src  = Join-Path $Work 'pack\.mcp.json'
  $dest = Join-Path $TARGET '.mcp.json'

  if (-not (Test-Path $src)) { return }

  Invoke-FileAction -Key '.mcp.json' -Dest $dest -Pack $src | Out-Null
}

function Run-EnvSetup {
  param([string]$Work)

  $setupScript = Join-Path $Work 'pack\scripts\setup-env.sh'

  if (-not (Test-Path $setupScript)) {
    Write-Log "setup-env.sh not found in pack — skipping"
    return
  }

  $bash = Get-Command bash.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -notlike '*System32*' } |
    Select-Object -First 1

  if (-not $bash) {
    $wslBash = Get-Command bash.exe -ErrorAction SilentlyContinue |
      Where-Object { $_.Source -like '*System32*' } |
      Select-Object -First 1
    if ($wslBash) {
      Write-Log "Only WSL bash found — skipping setup-env.sh. Install Git Bash and re-run, or run manually: bash scripts/setup-env.sh"
    } else {
      Write-Log "bash not found — skipping setup-env.sh. Install Git Bash and re-run, or run manually: bash scripts/setup-env.sh"
    }
    return
  }

  Write-Log "Running setup-env.sh via $($bash.Source)..."
  try {
    Push-Location $TARGET
    try {
      & $bash.Source $setupScript
      if ($LASTEXITCODE -ne 0) {
        Write-Log "setup-env.sh failed (non-fatal)"
      }
    } finally {
      Pop-Location
    }
  } catch {
    Write-Log "setup-env.sh failed (non-fatal): $_"
  }
}

function Run-Analysis {
  param([string]$Work)

  $promptFile = Join-Path $Work 'pack\scripts\analyze-prompt.txt'
  if (-not (Test-Path $promptFile)) { return }

  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Log "Claude CLI not found — skipping stack analysis."
    Write-Log "To install: npm i -g @anthropic-ai/claude-code"
    return
  }

  $promptContent = [System.IO.File]::ReadAllText($promptFile)

  # Same PS 5.1 hazard as the git clone above: anything claude writes to stderr
  # would become a terminating NativeCommandError under $ErrorActionPreference
  # = 'Stop', aborting the install over a help probe.
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $helpText = & claude --help 2>&1
  } finally {
    $ErrorActionPreference = $prevEap
  }
  $extraArgs = if ($helpText -match 'permission-mode') { @('--permission-mode', 'acceptEdits') } else { @() }

  Write-Log "Running stack analysis with Claude CLI..."
  try {
    Push-Location $TARGET
    try {
      & claude -p $promptContent --add-dir $TARGET @extraArgs
      if ($LASTEXITCODE -ne 0) {
        Write-Log "Analysis finished with warnings (non-fatal)."
      }
    } finally {
      Pop-Location
    }
  } catch {
    Write-Log "Analysis finished with warnings (non-fatal): $_"
  }
}

function Print-Summary {
  Write-Host "[dev-team-pack] $(if ($script:Mode -eq 'update') { 'Update complete.' } else { 'Installation complete.' })"
  Write-Host "  Target : $TARGET"
  Write-Host "  Repo   : $REPO_URL"
  Write-Host "  Ref    : $REF"
  Write-Host ("  {0} added, {1} updated, {2} kept, {3} conflicts" -f `
    $script:Counters.Added, $script:Counters.Updated, $script:Counters.Kept, $script:Counters.Conflict)
  if ($script:Conflicts.Count -gt 0) {
    Write-Host "  Conflicts (kept your version):"
    $script:Conflicts | ForEach-Object { Write-Host "    ! $_" }
    Write-Host "  Re-run with -Force to overwrite conflicts."
  }
  if (($script:Mode -eq 'install') -and ($script:Counters.Kept -gt 0)) {
    Write-Host ("  Note: {0} existing files were recorded as the baseline." -f $script:Counters.Kept)
  }
  Write-Host "  Commit .dev-team-pack.json so teammates share the same baseline."
}

$WORK = $null
try {
  Require-TargetWritable
  $WORK = Get-WorkDir
  Fetch-Pack -Work $WORK

  $ver = Get-PackVersion -Work $WORK
  Write-Log "pack version $($ver.Version) ($($ver.Source))"
  Read-PackState

  $upToDate = ($script:Mode -eq 'update') -and (-not $FORCE) -and
              $script:StateMeta.version -and ($script:StateMeta.version -eq $ver.Version)

  if ($upToDate) {
    Write-Log "installed: $($script:StateMeta.version) ($($script:StateMeta.ref))"
    Write-Log "Already up to date. Run with -Force to reinstall."
    # The recorded version advances even on a run that left conflicts, so
    # "Already up to date" alone would hide files that are still stale.
    if ($script:PrevConflicts.Count -gt 0) {
      Write-Log "Unresolved conflicts from the last run:"
      $script:PrevConflicts | ForEach-Object { Write-Host "    ! $_" }
      Write-Log "Re-run with -Force to overwrite them with the pack version."
    }
  } else {
    Merge-ClaudeDir -Work $WORK
    Copy-McpJson    -Work $WORK
    Merge-ClaudeMd  -Work $WORK
    Run-EnvSetup    -Work $WORK
    Run-Analysis    -Work $WORK
    Write-PackState -Version $ver.Version -Source $ver.Source
    Print-Summary
    Write-Log "Done."
  }
} finally {
  if ($WORK -and (Test-Path $WORK)) {
    Remove-Item -Recurse -Force $WORK -ErrorAction SilentlyContinue
  }
}
