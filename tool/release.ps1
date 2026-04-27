#Requires -Version 5.1
<#
  One-shot production release: commit + push -> GitHub Actions (analyze, test, release APK, OTA, supabase if MIGRATION_APPROVED=1).
  Windows PowerShell; optional Git Bash not required. Empty tree: allow-empty commit.
  .git/release-in-progress skips heavy pre_commit_run.sh; CI is source of truth for release. Portable backend not touched.
#>
[CmdletBinding()]
param(
  [string] $Message = '',
  [string] $Remote = 'origin',
  [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $RepoRoot

function Write-ReleaseLog {
  param([string] $Text, [string] $LogFile)
  $line = "[$((Get-Date).ToString('o'))] $Text"
  if ($LogFile) { Add-Content -Path $LogFile -Value $line -Encoding UTF8 }
  Write-Host $line
}

function Get-GitHubActionsUrl {
  param([string] $OriginUrl)
  if ([string]::IsNullOrWhiteSpace($OriginUrl)) { return $null }
  if ($OriginUrl -match 'github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$') {
    $owner = $Matches[1]
    $repo = $Matches[2]
    return "https://github.com/$owner/$repo/actions"
  }
  return $null
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path $RepoRoot 'builds\releases'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "release-$ts.log"

$gitDir = (git -C $RepoRoot rev-parse --git-dir)
if ([string]::IsNullOrWhiteSpace($gitDir)) { throw "Not a git repository: $RepoRoot" }
$gitDirFull = (Resolve-Path $gitDir).Path
$rip = Join-Path $gitDirFull 'release-in-progress'

$branch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
if ($branch -eq 'HEAD') { throw 'Refusing release: detached HEAD' }

$originUrl = $null
$ru = & git -C $RepoRoot remote get-url $Remote 2>&1
if ($LASTEXITCODE -eq 0) { $originUrl = if ($ru -is [string]) { $ru } else { $ru -join ' ' } }
$actionsUrl = Get-GitHubActionsUrl -OriginUrl $originUrl

if ([string]::IsNullOrWhiteSpace($Message)) {
  $Message = "auto: release $ts"
}

if ($DryRun) {
  Write-ReleaseLog -Text "DRY-RUN: Message=$Message Remote=$Remote Branch=$branch" -LogFile $logFile
  if ($actionsUrl) { Write-ReleaseLog -Text "DRY-RUN: CI: $actionsUrl" -LogFile $logFile }
  return
}

try {
  Write-ReleaseLog -Text "Release start: $RepoRoot branch=$branch" -LogFile $logFile
  if ($actionsUrl) { Write-ReleaseLog -Text "CI (after push): $actionsUrl" -LogFile $logFile }

  git -C $RepoRoot config core.hooksPath .githooks
  git -C $RepoRoot config githook.autoPush 1
  $env:AUTO_PUSH = '1'

  '1' | Set-Content -LiteralPath $rip -Encoding utf8 -NoNewline
  Write-ReleaseLog -Text "Set release-in-progress + githook.autoPush=1 + AUTO_PUSH=1" -LogFile $logFile

  git -C $RepoRoot add -A
  $st = @(git -C $RepoRoot status --short 2>&1)
  if ($st.Count -gt 0) {
    $stLine = $st -join '; '
    Write-ReleaseLog -Text "git status: $stLine" -LogFile $logFile
  } else {
    Write-ReleaseLog -Text "git status: (clean or only ignored)" -LogFile $logFile
  }

  $commitOut = & git -C $RepoRoot commit -m $Message 2>&1
  $ce = $LASTEXITCODE
  $commitOut | ForEach-Object { Write-ReleaseLog -Text "git commit: $_" -LogFile $logFile }
  if ($ce -ne 0) {
    Write-ReleaseLog -Text "Commit exit $ce; trying allow-empty" -LogFile $logFile
    $emptyMsg = "auto: release (empty) $ts"
    $emptyOut = & git -C $RepoRoot commit --allow-empty -m $emptyMsg 2>&1
    $e2 = $LASTEXITCODE
    $emptyOut | ForEach-Object { Write-ReleaseLog -Text "git commit: $_" -LogFile $logFile }
    if ($e2 -ne 0) { throw "git commit --allow-empty failed: $e2" }
  } else {
    Write-ReleaseLog -Text "commit OK: $Message" -LogFile $logFile
  }

  $hash = (git -C $RepoRoot rev-parse HEAD).Trim()
  Write-ReleaseLog -Text "HEAD=$hash" -LogFile $logFile
  Write-ReleaseLog -Text "post-commit: also see builds/.githook_postcommit.log" -LogFile $logFile

  $pushOut = & git -C $RepoRoot push -u $Remote $branch 2>&1
  $pe = $LASTEXITCODE
  $pushOut | ForEach-Object { Write-ReleaseLog -Text "git push: $_" -LogFile $logFile }
  if ($pe -ne 0) { throw "git push failed: $pe" }
  Write-ReleaseLog -Text "push OK: $Remote $branch" -LogFile $logFile
  if ($actionsUrl) { Write-ReleaseLog -Text "GitHub Actions: $actionsUrl" -LogFile $logFile }
}
finally {
  if (Test-Path -LiteralPath $rip) { Remove-Item -LiteralPath $rip -Force -ErrorAction SilentlyContinue }
  git -C $RepoRoot config --unset githook.autoPush 2>$null
  if (Test-Path Env:AUTO_PUSH) { Remove-Item Env:\AUTO_PUSH -ErrorAction SilentlyContinue }
  $tail = "[$((Get-Date).ToString('o'))] Cleanup: githook.autoPush unset, release-in-progress removed. Log: $logFile"
  if ($logFile) { Add-Content -Path $logFile -Value $tail -Encoding UTF8 }
  Write-Host $tail
}
