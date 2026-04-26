# Release APK with OpenWeather key from api_keys.json (gitignored).
# Run from repo root: powershell -File "scripts\build_apk.ps1"
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

$keys = Join-Path $root "api_keys.json"
if (-not (Test-Path -LiteralPath $keys)) {
  Write-Warning "Missing api_keys.json - copy api_keys.example.json and set OPENWEATHER_API_KEY."
  exit 1
}

flutter build apk --release --dart-define-from-file=api_keys.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$apk = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
Write-Host "Done: $apk"
