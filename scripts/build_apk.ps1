# Release APK with OpenWeather key from api_keys.json (gitignored).
# Run from repo root: powershell -File "scripts\build_apk.ps1"
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

# Явно задаём FLUTTER_ROOT из android\local.properties (иначе Gradle иногда
# подхватывает неверный/старый путь к SDK, напр. C:\src\flutter).
$localProps = Join-Path $root "android\local.properties"
if (Test-Path -LiteralPath $localProps) {
  $p = @{}
  Get-Content -LiteralPath $localProps | ForEach-Object {
    if ($_ -match '^\s*([^#=]+)=(.*)$') { $p[$matches[1].Trim()] = $matches[2].Trim() }
  }
  if ($p['flutter.sdk']) {
    $env:FLUTTER_ROOT = $p['flutter.sdk']
  }
}

$keys = Join-Path $root "api_keys.json"
if (-not (Test-Path -LiteralPath $keys)) {
  Write-Warning "Missing api_keys.json - copy api_keys.example.json and set OPENWEATHER_API_KEY."
  exit 1
}

flutter build apk --release --dart-define-from-file=api_keys.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$apk = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
Write-Host "Done: $apk"
