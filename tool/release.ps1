# Delegates to root release.ps1 (production build + git)
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'release.ps1') @args
