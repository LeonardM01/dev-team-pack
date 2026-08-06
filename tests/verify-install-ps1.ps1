# verify-install-ps1.ps1 — manual verification matrix for install.ps1's update
# detection (Task 10 of the installer-update-detection plan).
#
# The bash test harness (tests/install-update.test.sh, tests/decide.test.sh)
# cannot drive PowerShell, so this script exists to run the equivalent matrix
# by hand on a machine with pwsh (Windows, or `pwsh` on macOS/Linux). It
# builds a local git fixture, invokes install.ps1 against it repeatedly, and
# asserts each of the 12 cases from task-10-brief.md Step 8.
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

} finally {
  Remove-Item -Recurse -Force $Sandbox -ErrorAction SilentlyContinue
}

Write-Host "`n$($script:TestsRun) run, $($script:TestsFailed) failed"
if ($script:TestsFailed -gt 0) { exit 1 } else { exit 0 }
