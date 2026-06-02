param(
    [switch] $RequireSigning,
    [switch] $RequireInstalledSmoke,
    [string] $ReleaseSigningManifestPath,
    [string] $InstalledAppPath,
    [string] $InstalledSmokeEvidenceDir,
    [switch] $ConfirmInstalledAppLaunched,
    [switch] $ConfirmInstalledPromptEntryVisible,
    [switch] $ConfirmInstalledModesVisible,
    [switch] $ConfirmInstalledModeSequence,
    [switch] $ConfirmInstalledTurnOffRetainsPresetDisabled,
    [switch] $ConfirmInstalledLivePromptNonCaveman,
    [string] $GateSummaryPath = ".run\caveman-release-gate\caveman-release-gate-summary.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")

function Resolve-GateSummaryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string] $AllowedDirectory
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "-GateSummaryPath is required"
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    } else {
        $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }

    $summaryRootFullName = [System.IO.Path]::GetFullPath($AllowedDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $summaryPrefix = $summaryRootFullName + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedPath.StartsWith($summaryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("-GateSummaryPath must stay inside .run\caveman-release-gate: {0}" -f $Path)
    }

    return $resolvedPath
}

$gateSummaryRoot = Join-Path $repoRoot ".run\caveman-release-gate"
$gateSummaryPath = Resolve-GateSummaryPath -Path $GateSummaryPath -AllowedDirectory $gateSummaryRoot

if ([string]::IsNullOrWhiteSpace($ReleaseSigningManifestPath)) {
    $ReleaseSigningManifestPath = Join-Path $repoRoot ".run\caveman-release-signing\caveman-release-signing-manifest.json"
}
if ([System.IO.Path]::IsPathRooted($ReleaseSigningManifestPath)) {
    $releaseSigningManifestPath = [System.IO.Path]::GetFullPath($ReleaseSigningManifestPath)
} else {
    $releaseSigningManifestPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ReleaseSigningManifestPath))
    $repoRootFullName = $repoRoot.ProviderPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $repoPrefix = $repoRootFullName + [System.IO.Path]::DirectorySeparatorChar
    if (-not $releaseSigningManifestPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Relative -ReleaseSigningManifestPath must stay inside the repository: {0}" -f $ReleaseSigningManifestPath)
    }
}

if ($RequireSigning) {
    if (-not (Test-Path -LiteralPath $releaseSigningManifestPath -PathType Leaf)) {
        throw ("Release signing manifest is required when -RequireSigning is set: {0}" -f $releaseSigningManifestPath)
    }
}

if ($RequireInstalledSmoke) {
    if ([string]::IsNullOrWhiteSpace($InstalledAppPath)) {
        throw "-InstalledAppPath is required when -RequireInstalledSmoke is set"
    }
    if ([string]::IsNullOrWhiteSpace($InstalledSmokeEvidenceDir)) {
        throw "-InstalledSmokeEvidenceDir is required when -RequireInstalledSmoke is set"
    }
    $resolvedInstalledSmokeEvidenceDir = Resolve-Path -LiteralPath $InstalledSmokeEvidenceDir
    if (-not (Test-Path -LiteralPath $resolvedInstalledSmokeEvidenceDir -PathType Container)) {
        throw ("Installed-app smoke evidence directory is not a directory: {0}" -f $InstalledSmokeEvidenceDir)
    }
    $installedSmokeEvidenceFiles = @(Get-ChildItem -LiteralPath $resolvedInstalledSmokeEvidenceDir -File)
    if ($installedSmokeEvidenceFiles.Count -lt 1) {
        throw ("Installed-app smoke evidence directory must contain at least one file: {0}" -f $resolvedInstalledSmokeEvidenceDir)
    }

    $missingInstalledConfirmations = @()
    if (-not $ConfirmInstalledAppLaunched) {
        $missingInstalledConfirmations += "-ConfirmInstalledAppLaunched"
    }
    if (-not $ConfirmInstalledPromptEntryVisible) {
        $missingInstalledConfirmations += "-ConfirmInstalledPromptEntryVisible"
    }
    if (-not $ConfirmInstalledModesVisible) {
        $missingInstalledConfirmations += "-ConfirmInstalledModesVisible"
    }
    if (-not $ConfirmInstalledModeSequence) {
        $missingInstalledConfirmations += "-ConfirmInstalledModeSequence"
    }
    if (-not $ConfirmInstalledTurnOffRetainsPresetDisabled) {
        $missingInstalledConfirmations += "-ConfirmInstalledTurnOffRetainsPresetDisabled"
    }
    if (-not $ConfirmInstalledLivePromptNonCaveman) {
        $missingInstalledConfirmations += "-ConfirmInstalledLivePromptNonCaveman"
    }
    if ($missingInstalledConfirmations.Count -gt 0) {
        throw ("-RequireInstalledSmoke requires explicit installed-app confirmations: {0}" -f ($missingInstalledConfirmations -join " "))
    }
}

function Invoke-GateStep {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [scriptblock] $Action
    )

    Write-Host ("==> {0}" -f $Name)
    & $Action
}

function Invoke-NativeStep {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [scriptblock] $Action
    )

    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw ("{0} failed with exit code {1}" -f $Name, $LASTEXITCODE)
    }
}

$diffCheckPaths = @(
    "docs/ccs-caveman-release-readiness.md",
    "scripts/new-caveman-formal-release-checklist.ps1",
    "scripts/new-caveman-release-host-runbook.ps1",
    "scripts/new-caveman-release-approval-packet.ps1",
    "scripts/verify-caveman-release-approval-packet.ps1",
    "scripts/new-caveman-installed-smoke-confirmation.ps1",
    "scripts/new-caveman-installed-smoke-evidence.ps1",
    "scripts/verify-caveman-formal-release-readiness.ps1",
    "scripts/verify-caveman-api-smoke.ps1",
    "scripts/verify-caveman-deployed-smoke.ps1",
    "scripts/verify-caveman-deployed-smoke-restores-existing-prompt.ps1",
    "scripts/verify-caveman-desktop-preflight.ps1",
    "scripts/verify-caveman-installed-smoke.ps1",
    "scripts/verify-caveman-release-gate.ps1",
    "scripts/verify-caveman-release-hardening.ps1",
    "scripts/verify-caveman-release-signing.ps1",
    "scripts/verify-caveman-ui-smoke.ps1",
    "scripts/verify-token-cost-savers.ps1",
    "src-tauri/src/commands/prompt.rs",
    "src-tauri/src/prompt.rs",
    "src-tauri/src/services/prompt.rs",
    "src/components/prompts/PromptPanel.tsx",
    "tests/components/PromptPanel.integration.test.tsx",
    "tests/components/PromptPanel.test.tsx"
)

function Assert-TextFileClean {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Paths
    )

    foreach ($path in $Paths) {
        $fullPath = Join-Path $repoRoot $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw ("Diff text check path is missing: {0}" -f $path)
        }

        $lines = Get-Content -LiteralPath $fullPath -Encoding UTF8
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            if ($line -match "[`t ]$") {
                throw ("Trailing whitespace in {0}:{1}" -f $path, ($index + 1))
            }
            if ($line -match "^(<<<<<<<|=======|>>>>>>>)") {
                throw ("Conflict marker in {0}:{1}" -f $path, ($index + 1))
            }
        }
    }
}

if ($RequireSigning) {
    Invoke-NativeStep -Name "Release signing manifest preflight" -Action {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\verify-caveman-release-signing.ps1") `
            -ValidateManifestOnly `
            -ValidateManifestPath $releaseSigningManifestPath
    }
}

if ($RequireInstalledSmoke) {
    Invoke-NativeStep -Name "Installed-app evidence preflight" -Action {
            $installedSmokePreflightArgs = @(
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                (Join-Path $repoRoot "scripts\verify-caveman-installed-smoke.ps1"),
                "-InstalledAppPath",
                $InstalledAppPath,
                "-EvidenceDir",
                $InstalledSmokeEvidenceDir,
                "-ValidateEvidenceOnly"
            )
            if ($RequireSigning) {
                $installedSmokePreflightArgs += @("-ReleaseSigningManifestPath", $releaseSigningManifestPath)
            }
            & powershell @installedSmokePreflightArgs
    }
}

Push-Location -LiteralPath $repoRoot
try {
    Invoke-GateStep -Name "Caveman and shared token-cost verifier" -Action {
        Invoke-NativeStep -Name "Caveman and shared token-cost verifier" -Action {
            & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-token-cost-savers.ps1"
        }
    }

    Invoke-GateStep -Name "Caveman API smoke" -Action {
        Invoke-NativeStep -Name "Caveman API smoke" -Action {
            & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-api-smoke.ps1"
        }
    }

    Invoke-GateStep -Name "Caveman Web UI smoke" -Action {
        Invoke-NativeStep -Name "Caveman Web UI smoke" -Action {
            & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-ui-smoke.ps1"
        }
    }

    Invoke-GateStep -Name "Caveman desktop preflight" -Action {
        Invoke-NativeStep -Name "Caveman desktop preflight" -Action {
            & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-desktop-preflight.ps1"
        }
    }

    Invoke-GateStep -Name "Web production build" -Action {
        Invoke-NativeStep -Name "Web production build" -Action {
            & ".\node_modules\.bin\vite.cmd" build --mode web
        }
    }

    Invoke-GateStep -Name "Diff whitespace check" -Action {
        Invoke-NativeStep -Name "Diff whitespace check" -Action {
            & git diff --check -- $diffCheckPaths
        }
        Assert-TextFileClean -Paths $diffCheckPaths
    }

    Invoke-GateStep -Name "Caveman release hardening checks" -Action {
        Invoke-NativeStep -Name "Caveman release hardening checks" -Action {
            & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-hardening.ps1"
        }
    }

    $formalReleaseBlockedReasons = @()

    if ($RequireSigning) {
        Invoke-GateStep -Name "Release signing gate" -Action {
            Invoke-NativeStep -Name "Release signing gate" -Action {
                & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-signing.ps1" -ValidateManifestOnly -ValidateManifestPath $releaseSigningManifestPath
            }
        }
    } else {
        Write-Host "release_signing=skipped_local_condition"
        $formalReleaseBlockedReasons += "release_signing_not_required"
    }

    if ($RequireInstalledSmoke) {
        Invoke-GateStep -Name "Installed-app smoke confirmation" -Action {
            Invoke-NativeStep -Name "Installed-app smoke confirmation" -Action {
                $installedSmokeArgs = @(
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    ".\scripts\verify-caveman-installed-smoke.ps1",
                    "-InstalledAppPath",
                    $InstalledAppPath,
                    "-EvidenceDir",
                    $InstalledSmokeEvidenceDir,
                    "-ConfirmAppLaunched",
                    "-ConfirmPromptEntryVisible",
                    "-ConfirmModesVisible",
                    "-ConfirmModeSequence",
                    "-ConfirmTurnOffRetainsPresetDisabled",
                    "-ConfirmLivePromptNonCaveman"
                )
                if ($RequireSigning) {
                    $installedSmokeArgs += @("-ReleaseSigningManifestPath", $releaseSigningManifestPath)
                }
                & powershell @installedSmokeArgs
            }
        }
    } else {
        Write-Host "installed_smoke=skipped_local_condition"
        $formalReleaseBlockedReasons += "installed_smoke_not_required"
    }

    Write-Host "Caveman release gate passed."
    if ($RequireSigning -and $RequireInstalledSmoke) {
        $releaseGate = "ready_for_formal_release"
        Write-Host "release_gate=ready_for_formal_release"
    } else {
        $releaseGate = "conditional_caveman_only"
        Write-Host ("formal_release_blocked_reason={0}" -f ($formalReleaseBlockedReasons -join ","))
        Write-Host "release_gate=conditional_caveman_only"
    }

    $summary = [ordered] @{
        schemaVersion = 1
        createdAt = (Get-Date).ToUniversalTime().ToString("o")
        requireSigning = [bool] $RequireSigning
        requireInstalledSmoke = [bool] $RequireInstalledSmoke
        releaseSigningManifestPath = if ($RequireSigning) { $releaseSigningManifestPath } else { $null }
        installedAppPath = if ($RequireInstalledSmoke) { $InstalledAppPath } else { $null }
        installedSmokeEvidenceDir = if ($RequireInstalledSmoke) { $InstalledSmokeEvidenceDir } else { $null }
        formalReleaseBlockedReasons = @($formalReleaseBlockedReasons)
        releaseGate = $releaseGate
    }
    $summaryDir = Split-Path -Parent $gateSummaryPath
    New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $gateSummaryPath -Encoding UTF8
    Write-Host ("gate_summary={0}" -f $gateSummaryPath)
} finally {
    Pop-Location
}
