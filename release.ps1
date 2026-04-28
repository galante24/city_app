#Requires -Version 5.1
<#
.SYNOPSIS
  Production Android release: validates api_keys.json, embeds secrets via --dart-define-from-file,
  copies release APK, then git commit + push origin main (push only if build succeeds).

.EXAMPLE
  .\release.ps1
  .\release.ps1 -Message "release: version 1.0.2"
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Message = '',

    [string] $GitRemote = 'origin',

    [string] $GitBranch = 'main',

    # Skip git push (e.g. dry run / CI simulation)
    [switch] $SkipGitPush,

    # git commit --no-verify (avoid long hooks)
    [switch] $NoVerify
)

#region Init
$ErrorActionPreference = 'Stop'
if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = (Resolve-Path $PSScriptRoot).Path
Set-Location $RepoRoot

$DefinesFile = Join-Path $RepoRoot 'api_keys.json'
$DateTag = Get-Date -Format 'yyyyMMdd'
$TsFile = Get-Date -Format 'yyyyMMdd-HHmmss'
$ReleasesDir = Join-Path $RepoRoot 'builds\releases'
$DailyLog = Join-Path $ReleasesDir "release-$DateTag.log"

function Write-LogLine {
    param([string] $Line, [string] $DailyLogPath)
    # Console
    Write-Host $Line
    if (-not (Test-Path (Split-Path $DailyLogPath))) {
        New-Item -ItemType Directory -Path (Split-Path $DailyLogPath) -Force | Out-Null
    }
    Add-Content -Path $DailyLogPath -Value $Line -Encoding UTF8 -ErrorAction Continue
}

function Assert-LastExit {
    param([string] $StepName, [int] $Code)
    if ($Code -ne 0) {
        $msg = "${StepName}: command failed (exit code $Code)."
        Write-LogLine -Line "[ERR] $msg" -DailyLogPath $script:DailyLog
        throw $msg
    }
}
#endregion

#region Preflight
try {
    Write-LogLine -Line "========== release.ps1 start $($TsFile) ==========" -DailyLogPath $DailyLog

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git is not in PATH. Install Git for Windows.'
    }

    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'flutter is not in PATH. Install Flutter SDK and add bin to PATH.'
    }

    $flutterV = & flutter --version 2>&1
    Assert-LastExit 'flutter --version' $LASTEXITCODE

    if (-not (Test-Path -LiteralPath $DefinesFile)) {
        throw "Required file missing: $DefinesFile`nCreate it from api_keys.example.json with SUPABASE_URL and SUPABASE_ANON_KEY."
    }

    try {
        $raw = Get-Content -LiteralPath $DefinesFile -Raw -Encoding UTF8
        $j = $raw | ConvertFrom-Json
        if (-not $j.SUPABASE_URL -or [string]::IsNullOrWhiteSpace([string]$j.SUPABASE_URL)) {
            throw 'api_keys.json must contain non-empty SUPABASE_URL'
        }
        if (-not $j.SUPABASE_ANON_KEY -or [string]::IsNullOrWhiteSpace([string]$j.SUPABASE_ANON_KEY)) {
            throw 'api_keys.json must contain non-empty SUPABASE_ANON_KEY'
        }
    }
    catch {
        if ($_.Exception.Message -match 'must contain') { throw }
        throw "api_keys.json parse error: $($_.Exception.Message)"
    }

    $relDefines = 'api_keys.json'
    $defineArg = @('--dart-define-from-file', $relDefines)

    # JAVA for Gradle (optional but recommended)
    foreach ($jh in @($env:JAVA_HOME, 'C:\Program Files\Android\Android Studio\jbr')) {
        if (-not [string]::IsNullOrWhiteSpace($jh)) {
            $javaExe = Join-Path $jh 'bin\java.exe'
            if (Test-Path -LiteralPath $javaExe) {
                $env:JAVA_HOME = $jh
                break
            }
        }
    }
    if (-not $env:JAVA_HOME) {
        Write-LogLine -Line "[WARN] JAVA_HOME not set; Flutter/Gradle may fail. Set to Android Studio JBR if build errors." -DailyLogPath $DailyLog
    }

    git -C $RepoRoot rev-parse --is-inside-work-tree 2>&1 | Out-Null
    Assert-LastExit 'git rev-parse' $LASTEXITCODE

    $branch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>&1).Trim()
    if ($branch -ne $GitBranch -and -not $SkipGitPush) {
        Write-LogLine -Line "[WARN] Current branch is '$branch' (expected '$GitBranch'). Push will target $GitRemote $GitBranch anyway." -DailyLogPath $DailyLog
    }
}
catch {
    Write-LogLine -Line "[FATAL] $($_.Exception.Message)" -DailyLogPath $DailyLog
    exit 1
}
#endregion

#region Build (no git push before success)
try {
    if (-not (Test-Path $ReleasesDir)) {
        New-Item -ItemType Directory -Path $ReleasesDir -Force | Out-Null
    }

    Write-LogLine -Line "--- flutter clean ---" -DailyLogPath $DailyLog
    $o = & flutter clean 2>&1
    $o | ForEach-Object { Write-LogLine -Line "  $_" -DailyLogPath $DailyLog }
    Assert-LastExit 'flutter clean' $LASTEXITCODE

    Write-LogLine -Line "--- flutter pub get ---" -DailyLogPath $DailyLog
    $o = & flutter pub get 2>&1
    $o | ForEach-Object { Write-LogLine -Line "  $_" -DailyLogPath $DailyLog }
    Assert-LastExit 'flutter pub get' $LASTEXITCODE

    Write-LogLine -Line "--- flutter build apk --release (--dart-define-from-file) ---" -DailyLogPath $DailyLog
    $buildArgs = @('build', 'apk', '--release') + $defineArg
    $o = & flutter @buildArgs 2>&1
    $o | ForEach-Object { Write-LogLine -Line "  $_" -DailyLogPath $DailyLog }
    Assert-LastExit 'flutter build apk' $LASTEXITCODE

    $apkSrc = Join-Path $RepoRoot 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path -LiteralPath $apkSrc)) {
        throw "APK not found at $apkSrc"
    }

    $destName = "app-release-$TsFile.apk"
    $apkDest = Join-Path $ReleasesDir $destName
    Copy-Item -LiteralPath $apkSrc -Destination $apkDest -Force
    Write-LogLine -Line "[OK] Copied APK -> $apkDest" -DailyLogPath $DailyLog
}
catch {
    Write-LogLine -Line "[BUILD FAILED] $($_.Exception.Message)" -DailyLogPath $DailyLog
    Write-LogLine -Line "Git commit/push skipped (build must succeed first)." -DailyLogPath $DailyLog
    exit 2
}
#endregion

#region Git (after successful build)
try {
    git -C $RepoRoot config core.hooksPath .githooks 2>&1 | Out-Null

    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "release: build $TsFile"
    }

    Write-LogLine -Line "--- git add -A ---" -DailyLogPath $DailyLog
    $o = & git -C $RepoRoot add -A 2>&1
    $o | ForEach-Object { Write-LogLine -Line "  $_" -DailyLogPath $DailyLog }
    Assert-LastExit 'git add' $LASTEXITCODE

    $gitCommitArgs = @('-C', $RepoRoot, 'commit', '-m', $Message)
    if ($NoVerify) { $gitCommitArgs += '--no-verify' }
    Write-LogLine -Line "--- git commit ---" -DailyLogPath $DailyLog
    $cout = & git @gitCommitArgs 2>&1
    $cout | ForEach-Object { Write-LogLine -Line "  $_" -DailyLogPath $DailyLog }

    if ($LASTEXITCODE -ne 0) {
        Write-LogLine -Line "--- git commit --allow-empty ---" -DailyLogPath $DailyLog
        $gitAe = @('-C', $RepoRoot, 'commit', '--allow-empty', '-m', $Message)
        if ($NoVerify) { $gitAe += '--no-verify' }
        $cout2 = & git @gitAe 2>&1
        $cout2 | ForEach-Object { Write-LogLine -Line "  $_" -DailyLogPath $DailyLog }
        Assert-LastExit 'git commit --allow-empty' $LASTEXITCODE
    }

    if (-not $SkipGitPush) {
        Write-LogLine -Line "--- git push $GitRemote $GitBranch ---" -DailyLogPath $DailyLog
        $pout = & git -C $RepoRoot push $GitRemote $GitBranch 2>&1
        $pout | ForEach-Object { Write-LogLine -Line "  $_" -DailyLogPath $DailyLog }
        Assert-LastExit "git push $GitRemote $GitBranch" $LASTEXITCODE
    }
    else {
        Write-LogLine -Line "[SKIP] git push (--SkipGitPush)" -DailyLogPath $DailyLog
    }

    Write-LogLine -Line "========== release.ps1 DONE ==========" -DailyLogPath $DailyLog
    Write-Host "Success. APK: $apkDest ; Log: $DailyLog"
    exit 0
}
catch {
    Write-LogLine -Line "[GIT ERROR] $($_.Exception.Message)" -DailyLogPath $DailyLog
    exit 3
}
#endregion
