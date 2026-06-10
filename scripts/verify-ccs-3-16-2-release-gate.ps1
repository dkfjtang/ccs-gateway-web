param(
    [switch]$SkipDocker,
    [switch]$SkipDesktopPreflight,
    [switch]$OfflineCargo
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
Set-Location -LiteralPath $repoRoot

$CargoOfflineArgs = @()
if ($OfflineCargo) {
    $CargoOfflineArgs = @("--offline")
}

function Invoke-Gate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Write-Host "==> $Name"
    & $Command
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "Gate failed: $Name (exit $LASTEXITCODE)"
    }
}

Invoke-Gate "official upstream alignment" {
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-official-upstream-alignment.ps1
}

Invoke-Gate "local overlay governance" {
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-local-overlays.ps1
}

Invoke-Gate "token cost saver overlays" {
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-token-cost-savers.ps1
}

Invoke-Gate "frontend typecheck" {
    & .\node_modules\.bin\tsc.cmd --noEmit
}

Invoke-Gate "frontend unit tests" {
    & .\node_modules\.bin\vitest.cmd run --testTimeout=15000
}

Invoke-Gate "frontend web build" {
    & .\node_modules\.bin\vite.cmd build --mode web
}

Invoke-Gate "src-tauri lib tests" {
    cargo test --manifest-path src-tauri/Cargo.toml @CargoOfflineArgs --lib -- --test-threads=1
}

Invoke-Gate "src-tauri headless check" {
    cargo check --manifest-path src-tauri/Cargo.toml @CargoOfflineArgs --no-default-features --features headless
}

Invoke-Gate "server tests" {
    cargo test --manifest-path crates/server/Cargo.toml @CargoOfflineArgs
}

Invoke-Gate "server check" {
    cargo check --manifest-path crates/server/Cargo.toml @CargoOfflineArgs
}

Invoke-Gate "core tests" {
    cargo test --manifest-path crates/core/Cargo.toml @CargoOfflineArgs
}

Invoke-Gate "git diff whitespace" {
    git diff --check
}

Invoke-Gate "secret preflight all scope" {
    wsl.exe -d Ubuntu-24.04 -- bash -lc "cd /mnt/f/development/ccs-gateway-web && CCS_PREFLIGHT_SCOPE=all ./scripts/ccs-secret-preflight.sh"
}

if (-not $SkipDocker) {
    Invoke-Gate "docker compose build" {
        wsl.exe -d Ubuntu-24.04 -- bash -lc "cd /mnt/f/development/ccs-gateway-web && docker compose -f docker-compose.ccs-web.yml build"
    }

    Invoke-Gate "docker compose runtime smoke with proxy" {
        wsl.exe -d Ubuntu-24.04 -- bash -lc "cd /mnt/f/development/ccs-gateway-web && docker compose -f docker-compose.ccs-web.yml up -d && trap 'docker compose -f docker-compose.ccs-web.yml down' EXIT && sleep 5 && CCS_TARGET_NAME=local CCS_CONTAINER_NAME=ccs-gateway-web ./scripts/ccs-prod-probe.sh"
    }
}

if (-not $SkipDesktopPreflight) {
    Invoke-Gate "desktop no-bundle preflight" {
        powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-desktop-preflight.ps1
    }
}

Write-Host "ccs_3_16_2_release_gate=ready"
