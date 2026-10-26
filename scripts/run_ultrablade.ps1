# Launch UltraBlade from the repo root.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot.exe'
if (-not (Test-Path $godot)) { $godot = 'godot' }
Push-Location $repo
try {
    & $godot --path (Join-Path $repo 'game') @args
} finally {
    Pop-Location
}
