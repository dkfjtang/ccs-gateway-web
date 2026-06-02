param(
    [string] $ReleaseSigningManifestPath = ".run\caveman-release-signing\caveman-release-signing-manifest.json",
    [string] $InstalledAppPath,
    [string] $InstalledSmokeEvidenceDir,
    [string] $DeployedSmokeEvidencePath = ".run\caveman-deployed-smoke\current.json",
    [string] $DeployedRestoreProbeEvidencePath = ".run\caveman-deployed-smoke-restore\current.json",
    [string] $LocalGateSummaryPath = ".run\caveman-release-gate\caveman-release-gate-summary.json",
    [string] $OutputPath = ".run\caveman-formal-release-readiness\after-local-evidence-audit.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string] $ParameterName
    )

    $repoRootFullName = $repoRoot.ProviderPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $repoPrefix = $repoRootFullName + [System.IO.Path]::DirectorySeparatorChar

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $candidate = [System.IO.Path]::GetFullPath($Path)
    } else {
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }

    if (-not $candidate.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("-{0} must stay inside the repository: {1}" -f $ParameterName, $Path)
    }

    return $candidate
}

function Invoke-CaptureNative {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock] $Action
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $Action 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return @{
        ExitCode = $exitCode
        Output = (($output | Out-String).Trim())
    }
}

function Resolve-OptionalRepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string] $ParameterName
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    return Resolve-RepoPath -Path $Path -ParameterName $ParameterName
}

function Read-JsonEvidence {
    param(
        [AllowNull()]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [ordered] @{
            status = "missing_path"
        }
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [ordered] @{
            status = "missing"
            path = $Path
        }
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        return [ordered] @{
            status = "read"
            path = $Path
            data = $data
        }
    } catch {
        return [ordered] @{
            status = "invalid_json"
            path = $Path
            error = $_.Exception.Message
            name = $Name
        }
    }
}

$resolvedOutputPath = Resolve-RepoPath -Path $OutputPath -ParameterName "OutputPath"
$outputDirectory = Split-Path -Parent $resolvedOutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$blockers = @()
$checks = [ordered] @{}

$localEvidenceBlockers = @()
$localEvidenceChecks = [ordered] @{}

$deployedSmokePath = Resolve-OptionalRepoPath -Path $DeployedSmokeEvidencePath -ParameterName "DeployedSmokeEvidencePath"
$deployedSmokeEvidence = Read-JsonEvidence -Path $deployedSmokePath -Name "deployedSmoke"
$localEvidenceChecks.deployedSmoke = $deployedSmokeEvidence
if ($deployedSmokeEvidence.status -ne "read") {
    $localEvidenceBlockers += "deployed_smoke_evidence_missing"
} else {
    $deployedSmokeData = $deployedSmokeEvidence.data
    foreach ($required in @(
        "fullEnabled",
        "fullLivePromptContainsCaveman",
        "liteEnabled",
        "liteDisabledFull",
        "liteLivePromptContainsModeLite",
        "ultraEnabled",
        "ultraDisabledLite",
        "ultraDisabledFull",
        "ultraLivePromptContainsModeUltra",
        "turnOffRetainedProfiles",
        "turnOffDisabledAllCavemanProfiles",
        "turnOffClearedLivePrompt",
        "stateRestored",
        "postRestorePromptIdsMatchInitial",
        "postRestoreEnabledPromptIdsMatchInitial",
        "postRestoreLivePromptMatchesInitial"
    )) {
        if (-not [bool] $deployedSmokeData.$required) {
            $localEvidenceBlockers += ("deployed_smoke_{0}_not_true" -f $required)
        }
    }
}

$restoreProbePath = Resolve-OptionalRepoPath -Path $DeployedRestoreProbeEvidencePath -ParameterName "DeployedRestoreProbeEvidencePath"
$restoreProbeEvidence = Read-JsonEvidence -Path $restoreProbePath -Name "deployedRestoreProbe"
$localEvidenceChecks.deployedRestoreProbe = $restoreProbeEvidence
if ($restoreProbeEvidence.status -ne "read") {
    $localEvidenceBlockers += "deployed_restore_probe_evidence_missing"
} else {
    $restoreProbeData = $restoreProbeEvidence.data
    foreach ($required in @(
        "baselineRestoredAfterSmoke",
        "originalRestoredAfterProbe"
    )) {
        if (-not [bool] $restoreProbeData.$required) {
            $localEvidenceBlockers += ("deployed_restore_probe_{0}_not_true" -f $required)
        }
    }
}

$localGateSummaryResolvedPath = Resolve-OptionalRepoPath -Path $LocalGateSummaryPath -ParameterName "LocalGateSummaryPath"
$localGateSummaryEvidence = Read-JsonEvidence -Path $localGateSummaryResolvedPath -Name "localGateSummary"
$localEvidenceChecks.localGateSummary = $localGateSummaryEvidence
if ($localGateSummaryEvidence.status -ne "read") {
    $localEvidenceBlockers += "local_gate_summary_missing"
} else {
    $localGateData = $localGateSummaryEvidence.data
    if ([string] $localGateData.releaseGate -ne "conditional_caveman_only") {
        $localEvidenceBlockers += "local_gate_summary_not_conditional_caveman_only"
    }
    if ([bool] $localGateData.requireSigning) {
        $localEvidenceBlockers += "local_gate_summary_unexpectedly_required_signing"
    }
    if ([bool] $localGateData.requireInstalledSmoke) {
        $localEvidenceBlockers += "local_gate_summary_unexpectedly_required_installed_smoke"
    }
}

if ($localEvidenceBlockers.Count -eq 0) {
    $localEvidenceStatus = "local_caveman_evidence_present"
} else {
    $localEvidenceStatus = "local_caveman_evidence_incomplete"
}

$signingManifestResolvedPath = $null
if ([string]::IsNullOrWhiteSpace($ReleaseSigningManifestPath)) {
    $blockers += "release_signing_manifest_path_missing"
    $checks.releaseSigningManifest = [ordered] @{
        status = "missing_path"
    }
} else {
    if ([System.IO.Path]::IsPathRooted($ReleaseSigningManifestPath)) {
        $candidateSigningManifestPath = [System.IO.Path]::GetFullPath($ReleaseSigningManifestPath)
    } else {
        $candidateSigningManifestPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ReleaseSigningManifestPath))
    }

    if (-not (Test-Path -LiteralPath $candidateSigningManifestPath -PathType Leaf)) {
        $blockers += "release_signing_manifest_missing"
        $checks.releaseSigningManifest = [ordered] @{
            status = "missing"
            path = $candidateSigningManifestPath
        }
    } else {
        $signingManifestResolvedPath = $candidateSigningManifestPath
        $signingValidation = Invoke-CaptureNative -Action {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\verify-caveman-release-signing.ps1") `
                -ValidateManifestOnly `
                -ValidateManifestPath $signingManifestResolvedPath
        }
        if ($signingValidation.ExitCode -ne 0) {
            $blockers += "release_signing_manifest_invalid"
            $checks.releaseSigningManifest = [ordered] @{
                status = "invalid"
                path = $signingManifestResolvedPath
                output = $signingValidation.Output
            }
        } else {
            $checks.releaseSigningManifest = [ordered] @{
                status = "valid"
                path = $signingManifestResolvedPath
                output = $signingValidation.Output
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($InstalledAppPath)) {
    $blockers += "installed_app_path_missing"
    $checks.installedSmoke = [ordered] @{
        status = "missing_installed_app_path"
    }
} elseif ([string]::IsNullOrWhiteSpace($InstalledSmokeEvidenceDir)) {
    $blockers += "installed_smoke_evidence_dir_missing"
    $checks.installedSmoke = [ordered] @{
        status = "missing_evidence_dir"
        installedAppPath = $InstalledAppPath
    }
} elseif ($null -eq $signingManifestResolvedPath) {
    $blockers += "installed_smoke_requires_valid_release_signing_manifest"
    $checks.installedSmoke = [ordered] @{
        status = "waiting_for_valid_release_signing_manifest"
        installedAppPath = $InstalledAppPath
        evidenceDir = $InstalledSmokeEvidenceDir
    }
} else {
    $installedSmokeValidation = Invoke-CaptureNative -Action {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\verify-caveman-installed-smoke.ps1") `
            -InstalledAppPath $InstalledAppPath `
            -EvidenceDir $InstalledSmokeEvidenceDir `
            -ReleaseSigningManifestPath $signingManifestResolvedPath `
            -ValidateEvidenceOnly
    }
    if ($installedSmokeValidation.ExitCode -ne 0) {
        $blockers += "installed_smoke_evidence_invalid"
        $checks.installedSmoke = [ordered] @{
            status = "invalid"
            installedAppPath = $InstalledAppPath
            evidenceDir = $InstalledSmokeEvidenceDir
            output = $installedSmokeValidation.Output
        }
    } else {
        $checks.installedSmoke = [ordered] @{
            status = "valid"
            installedAppPath = $InstalledAppPath
            evidenceDir = $InstalledSmokeEvidenceDir
            output = $installedSmokeValidation.Output
        }
    }
}

if ($blockers.Count -eq 0) {
    $status = "formal_release_prerequisites_present"
} else {
    $status = "formal_release_prerequisites_blocked"
}

$audit = [ordered] @{
    schemaVersion = 1
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    status = $status
    blockers = @($blockers)
    localCavemanEvidence = [ordered] @{
        status = $localEvidenceStatus
        blockers = @($localEvidenceBlockers)
        checks = $localEvidenceChecks
        note = "Local Caveman evidence supports conditional prompt-level readiness only. It does not replace release-host signing or installed-app smoke."
    }
    checks = $checks
    nextRequiredGate = "scripts\verify-caveman-release-gate.ps1 -RequireSigning -RequireInstalledSmoke"
    note = "This audit is a prerequisite check. It does not replace the final aggregate release gate."
}

$audit | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8

Write-Host ("formal_release_readiness_audit={0}" -f $resolvedOutputPath)
if ($blockers.Count -gt 0) {
    Write-Host ("formal_release_blocked_reason={0}" -f ($blockers -join ","))
}
Write-Host ("formal_release_readiness={0}" -f $status)
