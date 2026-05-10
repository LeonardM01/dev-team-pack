# Usage:
#   .\install.ps1 [TargetDir]
#
#   TargetDir   Directory to install dev-team-pack into (default: current directory)
#
#   Environment variables:
#     $env:DEV_TEAM_REPO   Git repo URL (default: https://github.com/LeonardM01/dev-team-pack.git)
#     $env:DEV_TEAM_REF    Branch/tag/ref to fetch (default: main)
#
#   Examples:
#     .\install.ps1
#     .\install.ps1 C:\projects\my-app
#     $env:DEV_TEAM_REF = 'v2.0'; .\install.ps1 C:\projects\my-app

param(
  [string]$TargetDir = $PWD.Path
)

$ErrorActionPreference = 'Stop'

$REPO_URL = if ($env:DEV_TEAM_REPO) { $env:DEV_TEAM_REPO } else { 'https://github.com/LeonardM01/dev-team-pack.git' }
$REF      = if ($env:DEV_TEAM_REF)  { $env:DEV_TEAM_REF  } else { 'main' }
$TARGET   = $TargetDir

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
    $cloneOutput = git clone --depth 1 --branch $REF $REPO_URL "$Work\pack" 2>&1
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

function Merge-ClaudeDir {
  param([string]$Work)

  $srcBase = Join-Path $Work 'pack\.claude'
  if (-not (Test-Path $srcBase)) { return }

  Get-ChildItem -Path $srcBase -Recurse -File | ForEach-Object {
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

    if (Test-Path $dest) {
      Write-Log "skip .claude/$relNorm (existing wins)"
    } else {
      $destDir = Split-Path $dest -Parent
      if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
      }
      Copy-Item -Path $srcFile -Destination $dest
      Write-Log "add  .claude/$relNorm"
    }
  }
}

function Merge-ClaudeMd {
  param([string]$Work)

  $packMd    = Join-Path $Work 'pack\CLAUDE.md'
  $targetMd  = Join-Path $TARGET 'CLAUDE.md'
  $beginMarker = '<!-- dev-team-pack:begin -->'
  $endMarker   = '<!-- dev-team-pack:end -->'

  if (-not (Test-Path $packMd)) { return }

  $packContent = [System.IO.File]::ReadAllText($packMd)
  $block = "$beginMarker`n# Dev Team Pack`n$packContent`n$endMarker"

  if (-not (Test-Path $targetMd)) {
    [System.IO.File]::WriteAllText($targetMd, $block + "`n")
    Write-Log "add  CLAUDE.md"
    return
  }

  $existing = [System.IO.File]::ReadAllText($targetMd)
  $lines = $existing -split "`n"

  if ($lines | Where-Object { $_ -ceq $beginMarker }) {
    Write-Log "skip CLAUDE.md (dev-team-pack already installed)"
    return
  }

  [System.IO.File]::WriteAllText($targetMd, $existing + "`n`n---`n`n" + $block + "`n")
  Write-Log "add  CLAUDE.md (appended dev-team block)"
}

function Copy-McpJson {
  param([string]$Work)

  $src  = Join-Path $Work 'pack\.mcp.json'
  $dest = Join-Path $TARGET '.mcp.json'

  if (-not (Test-Path $src)) { return }

  if (Test-Path $dest) {
    Write-Log "skip .mcp.json (existing wins)"
  } else {
    Copy-Item -Path $src -Destination $dest
    Write-Log "add  .mcp.json"
  }
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

  $helpText  = & claude --help 2>&1
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
  if (-not [Console]::IsOutputRedirected) {
    Write-Host ""
    Write-Host "[dev-team-pack] Installation complete."
    Write-Host "  Target : $TARGET"
    Write-Host "  Repo   : $REPO_URL"
    Write-Host "  Ref    : $REF"
  }
}

$WORK = $null
try {
  Require-TargetWritable
  $WORK = Get-WorkDir
  Fetch-Pack -Work $WORK
  Merge-ClaudeDir -Work $WORK
  Copy-McpJson -Work $WORK
  Merge-ClaudeMd -Work $WORK
  Run-EnvSetup -Work $WORK
  Run-Analysis -Work $WORK
  Print-Summary
  Write-Log "Done."
} finally {
  if ($WORK -and (Test-Path $WORK)) {
    Remove-Item -Recurse -Force $WORK -ErrorAction SilentlyContinue
  }
}
