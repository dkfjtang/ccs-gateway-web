Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [scriptblock] $Command
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "==> $Name"
    try {
        & $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Step failed: $Name"
        }
        $timer.Stop()
        Write-Host ("<== {0} elapsedMs={1}" -f $Name, [int64]$timer.Elapsed.TotalMilliseconds)
    } catch {
        $timer.Stop()
        Write-Host ("<!! {0} elapsedMs={1}" -f $Name, [int64]$timer.Elapsed.TotalMilliseconds)
        throw
    }
}

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
Set-Location -LiteralPath $repoRoot

Invoke-Step "token_saver tests" {
    rtk cargo test --manifest-path src-tauri/Cargo.toml token_saver --lib
}

Invoke-Step "token_filter_engine tests" {
    rtk cargo test --manifest-path src-tauri/Cargo.toml token_filter_engine --lib
}

Invoke-Step "caveman prompt tests" {
    rtk cargo test --manifest-path src-tauri/Cargo.toml caveman --lib
}

Invoke-Step "caveman prompt panel tests" {
    rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/components/PromptPanel.test.tsx"
}

Invoke-Step "caveman prompt panel runtime flow tests" {
    rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/components/PromptPanel.integration.test.tsx"
}

Invoke-Step "frontend typecheck" {
    rtk powershell -NoProfile -Command "& .\node_modules\.bin\tsc.cmd --noEmit"
}

Write-Host "==> static check: token cost saver fixtures exist"
$fixtureDir = Join-Path $repoRoot "src-tauri\fixtures\token-cost-savers"
if (-not (Test-Path -Path $fixtureDir -PathType Container)) {
    throw "Missing token cost saver fixture directory: $fixtureDir"
}
$fixtureFiles = Get-ChildItem -Path $fixtureDir -Filter "*.json" -File
if (($fixtureFiles | Measure-Object).Count -lt 1) {
    throw "No token cost saver JSON fixtures found in $fixtureDir"
}
$fixtureFiles | ForEach-Object {
    $null = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
    Write-Host ("fixture ok: {0}" -f $_.Name)
}

Write-Host "==> static check: Caveman is not wired into proxy runtime"
$proxyHits = rtk rg -n "caveman|Caveman|caveman_output_compression" src-tauri/src/proxy --glob "!types.rs"
if ($LASTEXITCODE -eq 0) {
    Write-Host $proxyHits
    throw "Caveman references found under src-tauri/src/proxy; keep Caveman as prompt preset, not proxy response mutation."
}
if ($LASTEXITCODE -ne 1) {
    throw "rg failed while checking Caveman proxy references"
}

Write-Host "==> static check: Caveman is not wired into provider runtime"
$providerHits = rtk rg -n "caveman|Caveman|caveman_output_compression" src-tauri/src/provider.rs src-tauri/src/session_manager/providers
if ($LASTEXITCODE -eq 0) {
    Write-Host $providerHits
    throw "Caveman references found under provider runtime paths; keep Caveman as prompt preset, not provider response mutation."
}
if ($LASTEXITCODE -ne 1) {
    throw "rg failed while checking Caveman provider references"
}

Write-Host "==> static check: Token Saver has a single forwarder hook"
$hookHits = rtk rg -n "token_saver::optimize" src-tauri/src
if ($LASTEXITCODE -ne 0) {
    throw "Missing token_saver::optimize hook"
}
$hookCount = ($hookHits | Measure-Object).Count
Write-Host $hookHits
if ($hookCount -ne 1) {
    throw "Expected exactly one token_saver::optimize hook, found $hookCount"
}

Write-Host "Token cost saver gates passed."
