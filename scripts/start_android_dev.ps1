$ErrorActionPreference = "Stop"

$adbPath = Join-Path `
    $env:LOCALAPPDATA `
    "Android\Sdk\platform-tools\adb.exe"

if (-not (Test-Path -LiteralPath $adbPath)) {
    Write-Error "ADB was not found: $adbPath"
    exit 1
}

Write-Host "Checking Android devices..." -ForegroundColor Cyan

& $adbPath start-server | Out-Null

$devices = & $adbPath devices

$connectedDevice = $devices |
    Where-Object { $_ -match "\sdevice$" } |
    Select-Object -First 1

if (-not $connectedDevice) {
    Write-Error "No Android emulator was found. Start the emulator first."
    exit 1
}

Write-Host "Device found: $connectedDevice" -ForegroundColor Green
Write-Host "Configuring port forwarding..." -ForegroundColor Cyan

& $adbPath reverse tcp:3000 tcp:3000

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to configure adb reverse."
    exit 1
}

Write-Host "Port forwarding configured successfully:" -ForegroundColor Green
Write-Host "Android 127.0.0.1:3000 -> Windows localhost:3000"

$projectRoot = Split-Path -Parent $PSScriptRoot
$backendPath = Join-Path $projectRoot "backend"
$serverPath = Join-Path $backendPath "src\server.js"
$healthUrl = "http://127.0.0.1:3000/health"

function Test-BackendHealth {
    try {
        $responseBody = & curl.exe `
            --noproxy "*" `
            --silent `
            --show-error `
            --max-time 2 `
            $healthUrl 2>$null

        if ($LASTEXITCODE -ne 0) {
            return $false
        }

        $response = $responseBody | ConvertFrom-Json

        return $response.status -eq "ok"
    }
    catch {
        return $false
    }
}

Write-Host "Checking the Express backend..." -ForegroundColor Cyan

if (Test-BackendHealth) {
    Write-Host "Express is already running." -ForegroundColor Green
    exit 0
}

if (-not (Test-Path -LiteralPath $serverPath)) {
    Write-Error "Express entry point was not found: $serverPath"
    exit 1
}

Write-Host "Express is not running. Opening a backend terminal..." `
    -ForegroundColor Yellow

$escapedBackendPath = $backendPath.Replace("'", "''")
$backendCommand = `
    "Set-Location -LiteralPath '$escapedBackendPath'; node src/server.js"

Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList "-NoExit", "-Command", $backendCommand

for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Seconds 1

    if (Test-BackendHealth) {
        Write-Host "Express started successfully." -ForegroundColor Green
        Write-Host "Development environment is ready." -ForegroundColor Green
        exit 0
    }
}

Write-Error "Express did not become healthy within 10 seconds. Check the backend terminal."
exit 1
