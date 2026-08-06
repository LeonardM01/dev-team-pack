# verify-install-ps1.ps1 — manual verification matrix for install.ps1's update
# detection (Task 10 of the installer-update-detection plan).
#
# The bash test harness (tests/install-update.test.sh, tests/decide.test.sh)
# cannot drive PowerShell, so this script exists to run the equivalent matrix
# by hand on a machine with pwsh (Windows, or `pwsh` on macOS/Linux). It
# builds a local git fixture, invokes install.ps1 against it repeatedly, and
# asserts each of the 12 cases from task-10-brief.md Step 8, plus two
# regression cases (13, 14) added after review found cross-installer hash
# divergence bugs: CRLF mangling on Windows clones, and a tree-hash format
# mismatch in the git-unavailable fallback.
#
# Cases 11 and 14 shell out to `bash install.sh`, so `bash` must be on PATH
# (Git Bash or WSL bash on Windows) in addition to `git` and `pwsh`.
#
# Usage:
#   pwsh -File tests/verify-install-ps1.ps1
#
# Exit code is 0 if every case passes, 1 otherwise.

$ErrorActionPreference = 'Stop'

$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$InstallPs1 = Join-Path $RepoRoot 'install.ps1'

$script:TestsRun    = 0
$script:TestsFailed = 0

function Ok {
  param([string]$Name)
  $script:TestsRun++
  Write-Host "  ok   $Name"
}

function Fail {
  param([string]$Name, [string]$Detail)
  $script:TestsRun++
  $script:TestsFailed++
  Write-Host "  FAIL $Name"
  Write-Host "       $Detail"
}

function Assert-Eq {
  param([string]$Name, $Got, $Expected)
  if ("$Got" -eq "$Expected") { Ok $Name } else { Fail $Name "expected [$Expected] got [$Got]" }
}

function Assert-True {
  param([string]$Name, [bool]$Condition, [string]$Detail = '')
  if ($Condition) { Ok $Name } else { Fail $Name $Detail }
}

function Assert-FileAbsent {
  param([string]$Name, [string]$Path)
  if (Test-Path $Path) { Fail $Name "expected absent: $Path" } else { Ok $Name }
}

function Assert-FilesIdentical {
  param([string]$Name, [string]$A, [string]$B)
  $bytesA = [System.IO.File]::ReadAllBytes($A)
  $bytesB = [System.IO.File]::ReadAllBytes($B)
  if ([System.Linq.Enumerable]::SequenceEqual($bytesA, $bytesB)) {
    Ok $Name
  } else {
    Fail $Name "files differ: $A vs $B"
  }
}

function New-Fixture {
  param([string]$Path)
  New-Item -ItemType Directory -Path (Join-Path $Path '.claude/agents') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $Path 'scripts') -Force | Out-Null
  Set-Content -Path (Join-Path $Path '.claude/agents/code-reviewer.md') -Value 'v1 reviewer' -NoNewline:$false
  Set-Content -Path (Join-Path $Path 'CLAUDE.md') -Value 'v1 pack docs' -NoNewline:$false
  Set-Content -Path (Join-Path $Path '.mcp.json') -Value '{ "mcpServers": { "context7": {"command":"c7"} } }' -NoNewline:$false
  Push-Location $Path
  try {
    git init -q -b main | Out-Null
    git -c user.email=t@example.com -c user.name=test add -A | Out-Null
    git -c user.email=t@example.com -c user.name=test commit -q -m v1 | Out-Null
  } finally {
    Pop-Location
  }
}

function Invoke-Install {
  param([string]$Fixture, [string]$Target, [switch]$Force)
  $env:DEV_TEAM_REPO = $Fixture
  $env:DEV_TEAM_REF  = 'main'
  $argsList = @($Target)
  if ($Force) { $argsList = @('-Force') + $argsList }
  $out = & pwsh -NoProfile -File $InstallPs1 @argsList 2>&1
  $exit = $LASTEXITCODE
  Remove-Item Env:DEV_TEAM_REPO -ErrorAction SilentlyContinue
  Remove-Item Env:DEV_TEAM_REF  -ErrorAction SilentlyContinue
  return @{ Out = ($out -join "`n"); Exit = $exit }
}

function Get-StateJson {
  param([string]$Target)
  $p = Join-Path $Target '.dev-team-pack.json'
  if (-not (Test-Path $p)) { return $null }
  Get-Content -Raw -Path $p | ConvertFrom-Json
}

$Sandbox = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())) -Force
$Fixture = Join-Path $Sandbox 'fixture'
$Target  = Join-Path $Sandbox 'target'
New-Item -ItemType Directory -Path $Fixture | Out-Null
New-Fixture -Path $Fixture

try {
  Write-Host "=== Case 1: fresh install writes populated state ==="
  $r1 = Invoke-Install -Fixture $Fixture -Target $Target
  Assert-Eq "case1 exit code" $r1.Exit 0
  $state1 = Get-StateJson -Target $Target
  Assert-True "case1 state file written" ($null -ne $state1)
  Assert-True "case1 files map populated" ($state1.files.PSObject.Properties.Count -gt 0)
  Assert-True "case1 no tools key"  (-not ($state1.PSObject.Properties.Name -contains 'tools'))
  Assert-True "case1 no mcps key"   (-not ($state1.PSObject.Properties.Name -contains 'mcps'))

  Write-Host "`n=== Case 2: immediate re-run reports up to date, no changes ==="
  $before = Get-ChildItem -Recurse -File $Target | Sort-Object FullName | ForEach-Object { "$($_.FullName):$((Get-FileHash $_.FullName).Hash)" }
  $r2 = Invoke-Install -Fixture $Fixture -Target $Target
  $after = Get-ChildItem -Recurse -File $Target | Sort-Object FullName | ForEach-Object { "$($_.FullName):$((Get-FileHash $_.FullName).Hash)" }
  Assert-True "case2 reports up to date" ($r2.Out -match 'Already up to date')
  Assert-True "case2 no files changed" (($before -join "`n") -eq ($after -join "`n"))

  Write-Host "`n=== Case 3: -Force on up-to-date target performs full install ==="
  $r3 = Invoke-Install -Fixture $Fixture -Target $Target -Force
  Assert-True "case3 does not report up to date" (-not ($r3.Out -match 'Already up to date'))
  Assert-True "case3 reports done" ($r3.Out -match 'Done\.')

  Write-Host "`n=== Case 4: pack file changed upstream, target untouched -> updated ==="
  Set-Content -Path (Join-Path $Fixture '.claude/agents/code-reviewer.md') -Value 'v2 reviewer'
  Push-Location $Fixture
  try { git -c user.email=t@example.com -c user.name=test commit -aqm v2 } finally { Pop-Location }
  $r4 = Invoke-Install -Fixture $Fixture -Target $Target
  $content4 = Get-Content -Raw (Join-Path $Target '.claude/agents/code-reviewer.md')
  Assert-True "case4 file updated" ($content4.Trim() -eq 'v2 reviewer')

  Write-Host "`n=== Case 5: target edited locally, upstream unchanged -> kept ==="
  Set-Content -Path (Join-Path $Target '.claude/agents/code-reviewer.md') -Value 'local edit' -NoNewline
  $r5 = Invoke-Install -Fixture $Fixture -Target $Target
  $content5 = Get-Content -Raw (Join-Path $Target '.claude/agents/code-reviewer.md')
  Assert-True "case5 local edit kept" ($content5.Trim() -eq 'local edit')

  Write-Host "`n=== Case 6: both changed -> conflict, file unchanged ==="
  Set-Content -Path (Join-Path $Fixture '.claude/agents/code-reviewer.md') -Value 'v3 reviewer'
  Push-Location $Fixture
  try { git -c user.email=t@example.com -c user.name=test commit -aqm v3 } finally { Pop-Location }
  $r6 = Invoke-Install -Fixture $Fixture -Target $Target
  $content6 = Get-Content -Raw (Join-Path $Target '.claude/agents/code-reviewer.md')
  Assert-True "case6 conflict reported" ($r6.Out -match 'conflict')
  Assert-True "case6 local edit still intact" ($content6.Trim() -eq 'local edit')

  Write-Host "`n=== Case 7: case 6 with -Force -> overwritten ==="
  $r7 = Invoke-Install -Fixture $Fixture -Target $Target -Force
  $content7 = Get-Content -Raw (Join-Path $Target '.claude/agents/code-reviewer.md')
  Assert-True "case7 forced overwrite" ($content7.Trim() -eq 'v3 reviewer')

  Write-Host "`n=== Case 8: target file deleted locally -> stays absent across two updates ==="
  Remove-Item (Join-Path $Target '.claude/agents/code-reviewer.md')
  Invoke-Install -Fixture $Fixture -Target $Target | Out-Null
  Assert-FileAbsent "case8 absent after run 1" (Join-Path $Target '.claude/agents/code-reviewer.md')
  Set-Content -Path (Join-Path $Fixture '.claude/agents/code-reviewer.md') -Value 'v4 reviewer'
  Push-Location $Fixture
  try { git -c user.email=t@example.com -c user.name=test commit -aqm v4 } finally { Pop-Location }
  Invoke-Install -Fixture $Fixture -Target $Target | Out-Null
  Assert-FileAbsent "case8 absent after run 2" (Join-Path $Target '.claude/agents/code-reviewer.md')

  Write-Host "`n=== Case 9: pre-existing untracked file adopted on install, updatable afterwards ==="
  $Sandbox9 = Join-Path $Sandbox 'case9'
  New-Item -ItemType Directory -Path $Sandbox9 | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $Sandbox9 '.claude') -Force | Out-Null
  Set-Content -Path (Join-Path $Sandbox9 '.claude/agents/code-reviewer.md') -Value 'pre-existing' -NoNewline
  Invoke-Install -Fixture $Fixture -Target $Sandbox9 | Out-Null
  $content9 = Get-Content -Raw (Join-Path $Sandbox9 '.claude/agents/code-reviewer.md')
  Assert-True "case9 untracked file left alone on install" ($content9.Trim() -eq 'pre-existing')
  Set-Content -Path (Join-Path $Fixture '.claude/agents/code-reviewer.md') -Value 'v5 reviewer'
  Push-Location $Fixture
  try { git -c user.email=t@example.com -c user.name=test commit -aqm v5 } finally { Pop-Location }
  Invoke-Install -Fixture $Fixture -Target $Sandbox9 | Out-Null
  $content9b = Get-Content -Raw (Join-Path $Sandbox9 '.claude/agents/code-reviewer.md')
  Assert-True "case9 adopted file now updates" ($content9b.Trim() -eq 'v5 reviewer')

  Write-Host "`n=== Case 10: CLAUDE.md with content outside markers -> block updated, outside content intact ==="
  $Sandbox10 = Join-Path $Sandbox 'case10'
  New-Item -ItemType Directory -Path $Sandbox10 | Out-Null
  Set-Content -Path (Join-Path $Sandbox10 'CLAUDE.md') -Value "# My project`n`nCustom notes." -NoNewline
  Invoke-Install -Fixture $Fixture -Target $Sandbox10 | Out-Null
  $md10a = Get-Content -Raw (Join-Path $Sandbox10 'CLAUDE.md')
  Assert-True "case10 outside content present after install" ($md10a -match 'Custom notes\.')
  Assert-True "case10 block present after install" ($md10a -match 'dev-team-pack:begin')
  Set-Content -Path (Join-Path $Fixture 'CLAUDE.md') -Value 'v2 pack docs'
  Push-Location $Fixture
  try { git -c user.email=t@example.com -c user.name=test commit -aqm v2docs } finally { Pop-Location }
  Invoke-Install -Fixture $Fixture -Target $Sandbox10 | Out-Null
  $md10b = Get-Content -Raw (Join-Path $Sandbox10 'CLAUDE.md')
  Assert-True "case10 outside content still intact" ($md10b -match 'Custom notes\.')
  Assert-True "case10 block content updated" ($md10b -match 'v2 pack docs')

  Write-Host "`n=== Case 11: install.ps1 state read by install.sh -> prompts for tools/MCPs ==="
  $Sandbox11 = Join-Path $Sandbox 'case11'
  New-Item -ItemType Directory -Path $Sandbox11 | Out-Null
  Invoke-Install -Fixture $Fixture -Target $Sandbox11 | Out-Null
  $env:DEV_TEAM_REPO = $Fixture
  $env:DEV_TEAM_REF  = 'main'
  $env:DEV_TEAM_NONINTERACTIVE = '1'
  $env:NO_COLOR = '1'
  & bash (Join-Path $RepoRoot 'install.sh') $Sandbox11 2>&1 | Out-Null
  Remove-Item Env:DEV_TEAM_REPO, Env:DEV_TEAM_REF, Env:DEV_TEAM_NONINTERACTIVE, Env:NO_COLOR -ErrorAction SilentlyContinue
  $state11 = Get-StateJson -Target $Sandbox11
  Assert-True "case11 install.sh wrote tools key" ($state11.PSObject.Properties.Name -contains 'tools')
  Assert-True "case11 tools defaulted (not reused from empty/absent)" (($state11.tools -join ',') -eq 'claude,cursor')

  Write-Host "`n=== Case 12: schema hand-edited to 99 -> aborts with upgrade message ==="
  $Sandbox12 = Join-Path $Sandbox 'case12'
  New-Item -ItemType Directory -Path $Sandbox12 | Out-Null
  Invoke-Install -Fixture $Fixture -Target $Sandbox12 | Out-Null
  $statePath12 = Join-Path $Sandbox12 '.dev-team-pack.json'
  $raw12 = Get-Content -Raw $statePath12 | ConvertFrom-Json
  $raw12.schema = 99
  $raw12 | ConvertTo-Json -Depth 5 | Set-Content -Path $statePath12
  $r12 = Invoke-Install -Fixture $Fixture -Target $Sandbox12
  Assert-True "case12 non-zero exit" ($r12.Exit -ne 0)
  Assert-True "case12 upgrade message shown" ($r12.Out -match 'newer than this installer supports')

  Write-Host "`n=== Case 13: git clone disables core.autocrlf (CRLF/LF hash parity) ==="
  Write-Host "  Regression check for install.ps1's clone (~line 74): without"
  Write-Host "  '-c core.autocrlf=false', Git for Windows' common core.autocrlf=true"
  Write-Host "  default would translate LF blobs to CRLF on checkout. Get-Sha256File"
  Write-Host "  hashes raw bytes and Copy-Item preserves them into the target, so every"
  Write-Host "  hash install.ps1 computes would permanently disagree with install.sh's"
  Write-Host "  LF-based hashes for byte-identical repo content -- every .claude/* file"
  Write-Host "  and .mcp.json would misclassify as conflict/update on every run."
  $Sandbox13Fixture = Join-Path $Sandbox 'case13-fixture'
  $Sandbox13Target  = Join-Path $Sandbox 'case13-target'
  New-Item -ItemType Directory -Path (Join-Path $Sandbox13Fixture '.claude/agents') -Force | Out-Null
  New-Item -ItemType Directory -Path $Sandbox13Target -Force | Out-Null
  $multiline = "line one`nline two`nline three`n"
  [System.IO.File]::WriteAllText((Join-Path $Sandbox13Fixture '.claude/agents/example.md'), $multiline)
  Push-Location $Sandbox13Fixture
  try {
    git init -q -b main | Out-Null
    git -c user.email=t@example.com -c user.name=test add -A | Out-Null
    git -c user.email=t@example.com -c user.name=test commit -q -m v1 | Out-Null
  } finally {
    Pop-Location
  }

  # Emulate a Windows machine's common global default. Saved and restored so
  # this test doesn't leave the running machine's git config mutated.
  $savedAutocrlf = (git config --global core.autocrlf 2>$null)
  git config --global core.autocrlf true
  try {
    Invoke-Install -Fixture $Sandbox13Fixture -Target $Sandbox13Target | Out-Null
  } finally {
    if ([string]::IsNullOrEmpty($savedAutocrlf)) {
      git config --global --unset core.autocrlf 2>$null
    } else {
      git config --global core.autocrlf $savedAutocrlf
    }
  }

  $installedFile = Join-Path $Sandbox13Target '.claude/agents/example.md'
  if (Test-Path $installedFile) {
    $installedBytes = [System.IO.File]::ReadAllBytes($installedFile)
    $hasCR = $installedBytes -contains [byte]13
    Assert-True "case13 installed file has no CR bytes despite global core.autocrlf=true" (-not $hasCR) `
      "installed .claude/agents/example.md contains CR bytes -- core.autocrlf=false is missing from the git clone in install.ps1"
    $expectedBytes = [System.Text.Encoding]::UTF8.GetBytes($multiline)
    $identical = [System.Linq.Enumerable]::SequenceEqual($installedBytes, $expectedBytes)
    Assert-True "case13 installed bytes match source LF content exactly" $identical
  } else {
    Fail "case13 installed file has no CR bytes despite global core.autocrlf=true" "file was not installed: $installedFile"
    Fail "case13 installed bytes match source LF content exactly" "file was not installed: $installedFile"
  }

  Write-Host "`n=== Case 14: tree-hash format agrees with install.sh's pack_tree_hash ==="
  Write-Host "  Regression check for Get-PackVersion's git-unavailable fallback: path"
  Write-Host "  prefix ('./'), sort order/locale (ordinal, like LC_ALL=C sort), entry"
  Write-Host "  separator, and the top-level-only .git/ exclusion must all match"
  Write-Host "  install.sh's pack_tree_hash byte-for-byte, or the two installers will"
  Write-Host "  never agree a pack fetched without git is 'up to date'."

  function Import-InstallPs1Functions {
    param([string[]]$Names)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($InstallPs1, [ref]$tokens, [ref]$parseErrors)
    foreach ($name in $Names) {
      $fnAst = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
      }, $true) | Select-Object -First 1
      if (-not $fnAst) { throw "Could not find function '$name' in install.ps1 -- has it been renamed?" }
      Invoke-Expression $fnAst.Extent.Text
    }
  }

  # Load the real Get-PackVersion (and its dependencies) straight out of
  # install.ps1 by extracting the function text via the PowerShell AST, so
  # this exercises the shipped code rather than a hand-copied duplicate.
  Import-InstallPs1Functions -Names @('Get-Sha256File', 'Get-Sha256String', 'Get-PackVersion')

  $TreeFixtureRoot = Join-Path $Sandbox 'case14-tree'
  $TreePackDir     = Join-Path $TreeFixtureRoot 'pack'
  New-Item -ItemType Directory -Path (Join-Path $TreePackDir '.claude/agents') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $TreePackDir 'nested') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $TreePackDir '.git/objects') -Force | Out-Null
  Set-Content -Path (Join-Path $TreePackDir '.claude/agents/code-reviewer.md') -Value 'content a' -NoNewline
  Set-Content -Path (Join-Path $TreePackDir '.mcp.json') -Value 'content b' -NoNewline
  Set-Content -Path (Join-Path $TreePackDir 'CLAUDE.md') -Value 'content c' -NoNewline
  Set-Content -Path (Join-Path $TreePackDir 'nested/file with space.txt') -Value 'content d' -NoNewline
  # A .git/ dir that isn't a usable repo: Get-PackVersion will see it exists,
  # attempt `git rev-parse HEAD`, have that fail, and fall through to the
  # tree hash -- same as install.sh's pack_tree_hash would if invoked on a
  # tarball-fetched (non-git) pack directory. Also exercises the "exclude
  # only the top-level .git/*" rule.
  Set-Content -Path (Join-Path $TreePackDir '.git/objects/abc') -Value 'should-be-excluded' -NoNewline

  $psVersion = Get-PackVersion -Work $TreeFixtureRoot
  Assert-Eq "case14 falls back to tree hash (no usable .git repo)" $psVersion.Source 'tree'

  $bashScript = @"
set -euo pipefail
export DEV_TEAM_SOURCE_ONLY=1
source '$RepoRoot/install.sh'
WORK='$TreeFixtureRoot'
detect_hash_runtime >/dev/null 2>&1
pack_tree_hash
"@
  $bashHash = (& bash -c $bashScript 2>$null | Select-Object -Last 1)
  if ($null -ne $bashHash) { $bashHash = $bashHash.ToString().Trim() }

  Assert-Eq "case14 tree hash matches install.sh's pack_tree_hash" $psVersion.Version $bashHash

} finally {
  Remove-Item -Recurse -Force $Sandbox -ErrorAction SilentlyContinue
}

Write-Host "`n$($script:TestsRun) run, $($script:TestsFailed) failed"
if ($script:TestsFailed -gt 0) { exit 1 } else { exit 0 }
