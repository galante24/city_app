# Один Run: pub get, analyze, затем commit + push на GitHub
param(
  [string]$Message = "обновление"
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git add .
$staged = @(git diff --cached --name-only)
if ($staged.Count -gt 0) {
  git commit -m "Автоматическое обновление: $Message"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
  Write-Host "Нет изменений для коммита; выполняю git push (если нечего — сообщение на stderr)."
}
git push
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Готово: проверка и push."
