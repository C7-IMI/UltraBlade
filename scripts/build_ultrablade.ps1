# Build a standalone Windows UltraBlade executable.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot_console.exe'
if (-not (Test-Path $godot)) { $godot = 'godot_console.exe' }
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$out = Join-Path $build 'UltraBlade.exe'
Push-Location $repo
try {
    & $godot --headless --path (Join-Path $repo 'game') --export-release 'Windows Desktop' $out
    if ($LASTEXITCODE -ne 0) { throw "Godot export failed with exit code $LASTEXITCODE" }
    $item = Get-Item $out
    $hash = (Get-FileHash $out -Algorithm SHA256).Hash
    Write-Host ("BUILT {0} | {1:n0} bytes | SHA256 {2}" -f $item.FullName, $item.Length, $hash)
} finally {
    Pop-Location
}
