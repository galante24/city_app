# Локальная release-сборка APK и копия в builds\app_v{version}.apk (Windows, PowerShell 5+).
# Запуск из корня репозитория: pwsh -File tool/local_apk_build_and_save.ps1
# Отключение: $env:SKIP_LOCAL_APK_BUILD=1

$ErrorActionPreference = "Stop"
if ($env:SKIP_LOCAL_APK_BUILD -and $env:SKIP_LOCAL_APK_BUILD -ne "0") {
  Write-Host "local_apk: SKIP_LOCAL_APK_BUILD, выход"
  exit 0
}

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = Split-Path -Parent $ScriptDir
Set-Location $Root

$Pub = Join-Path $Root "pubspec.yaml"
if (-not (Test-Path -LiteralPath $Pub)) { throw "local_apk: нет pubspec.yaml" }

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) { throw "local_apk: команда flutter не найдена в PATH" }

Write-Host "local_apk: flutter build apk --release"
& flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "local_apk: flutter build завершился с кодом $LASTEXITCODE" }

$Built = Join-Path $Root "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path -LiteralPath $Built)) { throw "local_apk: не найден $Built" }
if ((Get-Item -LiteralPath $Built).Length -le 0) { throw "local_apk: пустой артефакт" }

$line = (Get-Content -LiteralPath $Pub -Raw) -split "`n" | Where-Object { $_ -match '^\s*version:\s*' } | Select-Object -First 1
if (-not $line) { throw "local_apk: нет строки version" }
$ver = ($line -replace '^\s*version:\s*', '' -split '#')[0].Trim() -replace '\r', ''
if ($ver -notmatch '\+') { throw "local_apk: ожидается a.b.c+N, получено: $ver" }

$builds = Join-Path $Root "builds"
New-Item -ItemType Directory -Force -Path $builds | Out-Null
$out = Join-Path $builds "app_v$ver.apk"
Copy-Item -LiteralPath $Built -Destination $out -Force
if (-not (Test-Path -LiteralPath $out) -or (Get-Item -LiteralPath $out).Length -le 0) {
  throw "local_apk: копия невалидна"
}
Write-Host "local_apk: сохранено: $out"
Copy-Item -LiteralPath $Pub -Destination (Join-Path $builds ".last_built_from_pubspec.yaml") -Force -ErrorAction SilentlyContinue

# Ротация: оставить 10 новеиших app_v*.apk
$apks = Get-ChildItem -LiteralPath $builds -Filter "app_v*.apk" -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending
if ($apks.Count -gt 10) {
  $apks | Select-Object -Skip 10 | ForEach-Object {
    Write-Host "local_apk: удалён старый: $($_.Name)"
    Remove-Item -LiteralPath $_.FullName -Force
  }
}

exit 0
