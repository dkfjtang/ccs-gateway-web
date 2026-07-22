param(
    [switch]$SkipDocker,
    [switch]$SkipDesktopPreflight,
    [switch]$OfflineCargo
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
Set-Location -LiteralPath $repoRoot
$wslDistro = if ($env:CCS_WSL_DISTRO) { $env:CCS_WSL_DISTRO } else { "Ubuntu" }

$CargoOfflineArgs = @()
if ($OfflineCargo) {
    $CargoOfflineArgs = @("--offline")
}

function ConvertTo-WslPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsPath
    )

    $resolved = Resolve-Path -LiteralPath $WindowsPath
    $path = $resolved.Path
    if ($path -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "Only drive-letter Windows paths are supported: $path"
    }

    $drive = $Matches[1].ToLowerInvariant()
    $tail = $Matches[2] -replace '\\', '/'
    return "/mnt/$drive/$tail"
}

$repoRootWsl = ConvertTo-WslPath -WindowsPath $repoRoot

function Invoke-Gate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "==> $Name"
    try {
        & $Command
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            throw "Gate failed: $Name (exit $LASTEXITCODE)"
        }
        $timer.Stop()
        Write-Host ("<== {0} elapsedMs={1}" -f $Name, [int64]$timer.Elapsed.TotalMilliseconds)
    } catch {
        $timer.Stop()
        Write-Host ("<!! {0} elapsedMs={1}" -f $Name, [int64]$timer.Elapsed.TotalMilliseconds)
        throw
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
    wsl.exe -d $wslDistro -- bash -lc "cd '$repoRootWsl' && CCS_PREFLIGHT_SCOPE=all ./scripts/ccs-secret-preflight.sh"
}

if (-not $SkipDocker) {
    Invoke-Gate "docker compose build" {
        wsl.exe -d $wslDistro -- bash -lc "cd '$repoRootWsl' && docker compose -f docker-compose.ccs-web.yml build"
    }

    Invoke-Gate "docker compose runtime smoke with proxy" {
        wsl.exe -d $wslDistro -- bash -lc "cd '$repoRootWsl' && docker compose -f docker-compose.ccs-web.yml up -d && trap 'docker compose -f docker-compose.ccs-web.yml down' EXIT && sleep 5 && CCS_TARGET_NAME=local CCS_CONTAINER_NAME=ccs-gateway-web ./scripts/ccs-prod-probe.sh"
    }
}

if (-not $SkipDesktopPreflight) {
    Invoke-Gate "desktop no-bundle preflight" {
        powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-desktop-preflight.ps1
    }
}

Write-Host "ccs_3_16_2_release_gate=ready"
