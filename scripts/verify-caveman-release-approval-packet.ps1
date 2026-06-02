param(
    [string] $ApprovalPacketPath = ".run\caveman-release-approval\caveman-release-approval-packet.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")

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

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool] $Condition,
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$packetPath = Resolve-RepoPath -Path $ApprovalPacketPath -ParameterName "ApprovalPacketPath"
if (-not (Test-Path -LiteralPath $packetPath -PathType Leaf)) {
    throw ("Approval packet is missing: {0}" -f $packetPath)
}

$packet = Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-True -Condition ($packet.approvalStatus -eq "conditional_caveman_only_ready_for_release_host_approval") -Message "Approval packet status is not conditional"
Assert-True -Condition ($packet.localEvidenceStatus -eq "local_caveman_evidence_present") -Message "Approval packet local evidence is not present"
Assert-True -Condition ($packet.formalReleaseReadiness -eq "formal_release_prerequisites_blocked") -Message "Approval packet formal release readiness must remain blocked before release-host evidence"
Assert-True -Condition ($packet.releaseGate -eq "conditional_caveman_only") -Message "Approval packet release gate is not conditional_caveman_only"

foreach ($requiredBlocker in @(
    "release_signing_manifest_invalid",
    "installed_app_path_missing"
)) {
    Assert-True -Condition (@($packet.formalReleaseBlockers) -contains $requiredBlocker) -Message ("Approval packet is missing formal blocker: {0}" -f $requiredBlocker)
}

foreach ($requiredItem in @(
    "non_skipbuild_release_signing_manifest_from_release_host",
    "valid_updater_signature_for_generated_nsis_setup",
    "installed_app_smoke_bound_to_signed_manifest",
    "release_host_runbook_generated_for_copyable_formal_gate",
    "final_aggregate_gate_with_RequireSigning_and_RequireInstalledSmoke"
)) {
    Assert-True -Condition (@($packet.requiredBeforeFormalRelease) -contains $requiredItem) -Message ("Approval packet is missing final release requirement: {0}" -f $requiredItem)
}

foreach ($requiredText in @(
    "-RequireSigning",
    "-ReleaseSigningManifestPath",
    "-RequireInstalledSmoke",
    "-InstalledAppPath",
    "-InstalledSmokeEvidenceDir",
    "-ConfirmInstalledAppLaunched",
    "-ConfirmInstalledPromptEntryVisible",
    "-ConfirmInstalledModesVisible",
    "-ConfirmInstalledModeSequence",
    "-ConfirmInstalledTurnOffRetainsPresetDisabled",
    "-ConfirmInstalledLivePromptNonCaveman"
)) {
    Assert-True -Condition ([string] $packet.finalGateCommand).Contains($requiredText) -Message ("Approval packet final gate command is missing: {0}" -f $requiredText)
}

foreach ($artifactName in @(
    "readinessAudit",
    "formalChecklist",
    "releaseHostRunbook",
    "uiSmoke",
    "deployedSmoke",
    "deployedRestoreProbe",
    "localGateSummary"
)) {
    $artifact = $packet.evidenceArtifacts.$artifactName
    Assert-True -Condition ($null -ne $artifact) -Message ("Approval packet is missing evidence artifact: {0}" -f $artifactName)
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string] $artifact.path)) -Message ("Evidence artifact path is missing: {0}" -f $artifactName)
    Assert-True -Condition ([string] $artifact.sha256 -match "^[A-Fa-f0-9]{64}$") -Message ("Evidence artifact SHA256 is invalid: {0}" -f $artifactName)

    $artifactPath = Resolve-RepoPath -Path ([string] $artifact.path) -ParameterName ("{0}.path" -f $artifactName)
    Assert-True -Condition (Test-Path -LiteralPath $artifactPath -PathType Leaf) -Message ("Evidence artifact file is missing: {0}" -f $artifactPath)
    $actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
    Assert-True -Condition ($actualHash -eq [string] $artifact.sha256) -Message ("Evidence artifact SHA256 mismatch for {0}" -f $artifactName)
}

Write-Host ("caveman_release_approval_packet_verified={0}" -f $packetPath)
Write-Host "approval_packet_status=conditional_caveman_only_ready_for_release_host_approval"
