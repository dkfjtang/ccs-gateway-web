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

function Assert-RgNoHits {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,
        [Parameter(Mandatory = $true)]
        [string] $FailureMessage
    )

    Write-Host "==> static check: $Name"
    $hits = & rtk rg @Arguments
    if ($LASTEXITCODE -eq 0) {
        Write-Host $hits
        throw $FailureMessage
    }
    if ($LASTEXITCODE -ne 1) {
        throw "rg failed while checking $Name"
    }
}

function Assert-RgHitCount {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,
        [Parameter(Mandatory = $true)]
        [int] $ExpectedCount
    )

    Write-Host "==> static check: $Name"
    $hits = & rtk rg @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Missing expected hits for $Name"
    }
    $hitCount = ($hits | Measure-Object).Count
    Write-Host $hits
    if ($hitCount -ne $ExpectedCount) {
        throw "Expected $ExpectedCount hits for $Name, found $hitCount"
    }
}

function Assert-RgHasHits {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    Write-Host "==> static check: $Name"
    $hits = & rtk rg @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Missing expected hits for $Name"
    }
    Write-Host $hits
}

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
Set-Location -LiteralPath $repoRoot

try {
    Invoke-Step "token_saver tests" {
        rtk cargo test --manifest-path src-tauri/Cargo.toml token_saver --lib
    }

    Invoke-Step "token_filter_engine tests" {
        rtk cargo test --manifest-path src-tauri/Cargo.toml token_filter_engine --lib
    }

    Invoke-Step "responses stickiness tests" {
        rtk cargo test --manifest-path src-tauri/Cargo.toml responses_session --lib
    }

    Invoke-Step "service tier tests" {
        rtk cargo test --manifest-path src-tauri/Cargo.toml service_tier --lib
    }

    Invoke-Step "caveman prompt tests" {
        rtk cargo test --manifest-path src-tauri/Cargo.toml caveman --lib
    }

    Write-Host "==> static check: overlay ledger exists"
    $ledgerPath = Join-Path $repoRoot "docs\ccs-fork-overlay-ledger.md"
    if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) {
        throw "Missing overlay ledger: $ledgerPath"
    }

    Assert-RgHitCount `
        -Name "single Token Saver forwarder hook" `
        -Arguments @("token_saver::optimize", "src-tauri/src") `
        -ExpectedCount 1

    Assert-RgHitCount `
        -Name "Token Saver request summary log" `
        -Arguments @("request_summary candidate_fields", "src-tauri/src/proxy") `
        -ExpectedCount 1

    Assert-RgHasHits `
        -Name "Responses stickiness recorded session diagnostic" `
        -Arguments @("sticky_recorded_session", "src-tauri/src/proxy")

    Assert-RgHasHits `
        -Name "Responses stickiness recorded response diagnostic" `
        -Arguments @("sticky_recorded_response", "src-tauri/src/proxy")

    Assert-RgHasHits `
        -Name "Responses stickiness applied diagnostic" `
        -Arguments @("sticky_applied", "src-tauri/src/proxy")

    Assert-RgHasHits `
        -Name "Responses stickiness missed diagnostic" `
        -Arguments @("sticky_missed", "src-tauri/src/proxy")

    Assert-RgHasHits `
        -Name "Responses stickiness blocked diagnostic" `
        -Arguments @("sticky_blocked_unavailable", "src-tauri/src/proxy")

    Assert-RgHasHits `
        -Name "Responses stickiness eviction diagnostic" `
        -Arguments @("sticky_evicted", "src-tauri/src/proxy")

    Assert-RgNoHits `
        -Name "Caveman is not wired into proxy runtime" `
        -Arguments @("caveman|Caveman|caveman_output_compression", "src-tauri/src/proxy", "--glob", "!types.rs") `
        -FailureMessage "Caveman references found under src-tauri/src/proxy; keep Caveman as prompt preset, not proxy response mutation."

    Assert-RgNoHits `
        -Name "Caveman is not wired into provider runtime" `
        -Arguments @("caveman|Caveman|caveman_output_compression", "src-tauri/src/provider.rs", "src-tauri/src/session_manager/providers") `
        -FailureMessage "Caveman references found under provider runtime paths; keep Caveman as prompt preset, not provider response mutation."

    Write-Host "overlay_status=overlay_ready"
} catch {
    Write-Host "overlay_status=overlay_failed"
    throw
}
