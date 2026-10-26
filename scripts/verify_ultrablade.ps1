# Verify the UltraBlade playable slice.
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
$repo = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot_console.exe'
if (-not (Test-Path $godot)) { $godot = 'godot_console.exe' }
Push-Location $repo
$failed = $false
try {
    Write-Host '== headless selftest =='
    & $godot --headless --path (Join-Path $repo 'game') -- --selftest
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    Write-Host '== end-to-end integration =='
    & $godot --headless --path (Join-Path $repo 'game') -s res://tools/integration_test.gd
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    Write-Host '== AI demo =='
    & $godot --headless --path (Join-Path $repo 'game') -- --demo-seconds 8 --demo
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    Write-Host '== exported binary =='
    $exe = Join-Path $repo 'build\UltraBlade.exe'
    if (Test-Path $exe) {
        & $exe --headless -- --selftest
        if ($LASTEXITCODE -ne 0) { $failed = $true }
    } else {
        Write-Host "SKIP no exported binary at $exe (run scripts/build_ultrablade.ps1)"
    }
} finally {
    Pop-Location
}
if ($failed) { throw 'verification failed' }
Write-Host 'ULTRABLADE_VERIFY_OK'
