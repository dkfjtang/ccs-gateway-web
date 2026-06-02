param(
    [string] $ReadinessAuditPath = ".run\caveman-formal-release-readiness\after-local-evidence-audit.json",
    [string] $FormalChecklistPath = ".run\caveman-formal-release-checklist\after-restore-probe.json",
    [string] $ReleaseHostRunbookPath = ".run\caveman-release-host\caveman-release-host-runbook.json",
    [string] $UiSmokeEvidencePath = ".run\caveman-ui-smoke\caveman-ui-smoke-evidence.json",
    [string] $DeployedSmokeEvidencePath = ".run\caveman-deployed-smoke\current.json",
    [string] $DeployedRestoreProbeEvidencePath = ".run\caveman-deployed-smoke-restore\current.json",
    [string] $LocalGateSummaryPath = ".run\caveman-release-gate\caveman-release-gate-summary.json",
    [string] $OutputPath = ".run\caveman-release-approval\caveman-release-approval-packet.json"
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

function Read-RequiredJson {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Required {0} JSON is missing: {1}" -f $Name, $Path)
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw ("Required {0} JSON is invalid: {1}. {2}" -f $Name, $Path, $_.Exception.Message)
    }
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

function Get-ArtifactRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return [ordered] @{
        path = $Path
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
}

$readinessPath = Resolve-RepoPath -Path $ReadinessAuditPath -ParameterName "ReadinessAuditPath"
$checklistPath = Resolve-RepoPath -Path $FormalChecklistPath -ParameterName "FormalChecklistPath"
$releaseHostRunbookPath = Resolve-RepoPath -Path $ReleaseHostRunbookPath -ParameterName "ReleaseHostRunbookPath"
$uiSmokePath = Resolve-RepoPath -Path $UiSmokeEvidencePath -ParameterName "UiSmokeEvidencePath"
$deployedSmokePath = Resolve-RepoPath -Path $DeployedSmokeEvidencePath -ParameterName "DeployedSmokeEvidencePath"
$restoreProbePath = Resolve-RepoPath -Path $DeployedRestoreProbeEvidencePath -ParameterName "DeployedRestoreProbeEvidencePath"
$localGatePath = Resolve-RepoPath -Path $LocalGateSummaryPath -ParameterName "LocalGateSummaryPath"
$resolvedOutputPath = Resolve-RepoPath -Path $OutputPath -ParameterName "OutputPath"

$readiness = Read-RequiredJson -Path $readinessPath -Name "readiness audit"
$checklist = Read-RequiredJson -Path $checklistPath -Name "formal checklist"
$releaseHostRunbook = Read-RequiredJson -Path $releaseHostRunbookPath -Name "release-host runbook"
$uiSmoke = Read-RequiredJson -Path $uiSmokePath -Name "UI smoke evidence"
$deployedSmoke = Read-RequiredJson -Path $deployedSmokePath -Name "deployed smoke evidence"
$restoreProbe = Read-RequiredJson -Path $restoreProbePath -Name "deployed restore probe evidence"
$localGate = Read-RequiredJson -Path $localGatePath -Name "local gate summary"

Assert-True -Condition ($readiness.localCavemanEvidence.status -eq "local_caveman_evidence_present") -Message "Readiness audit does not report local Caveman evidence as present"
Assert-True -Condition ($readiness.status -eq "formal_release_prerequisites_blocked") -Message "Approval packet must not be generated from an unexpected readiness status"
Assert-True -Condition ($checklist.releaseGate -eq "blocked_until_release_host_evidence") -Message "Formal checklist must remain blocked until release-host evidence"
Assert-True -Condition ($checklist.cavemanScope -eq "prompt_style_profile_only") -Message "Formal checklist Caveman scope is not prompt_style_profile_only"
Assert-True -Condition ($releaseHostRunbook.releaseGateTarget -eq "ready_for_formal_release") -Message "Release-host runbook must target ready_for_formal_release"
Assert-True -Condition ($uiSmoke.uiControls -eq "openclaw_prompt_entry_lite_full_ultra_turn_off") -Message "UI smoke evidence does not report expected controls"
Assert-True -Condition ($uiSmoke.uiFlow -eq "full_to_lite_to_ultra_to_off") -Message "UI smoke evidence does not report expected mode flow"
Assert-True -Condition ($uiSmoke.turnOff -eq "preset_retained_live_prompt_cleared") -Message "UI smoke evidence does not report expected off semantics"
Assert-True -Condition ($localGate.releaseGate -eq "conditional_caveman_only") -Message "Local gate summary must be conditional_caveman_only"

foreach ($requiredScreenshot in @(
    "02-caveman-full.png",
    "03-caveman-lite.png",
    "04-caveman-ultra.png",
    "05-caveman-off.png"
)) {
    Assert-True -Condition ($null -ne $uiSmoke.screenshots.$requiredScreenshot) -Message ("UI smoke evidence is missing screenshot artifact: {0}" -f $requiredScreenshot)
}

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
    Assert-True -Condition ([bool] $deployedSmoke.$required) -Message ("Deployed smoke evidence field is not true: {0}" -f $required)
}

foreach ($required in @(
    "baselineRestoredAfterSmoke",
    "originalRestoredAfterProbe"
)) {
    Assert-True -Condition ([bool] $restoreProbe.$required) -Message ("Restore probe evidence field is not true: {0}" -f $required)
}

$approvalStatus = "conditional_caveman_only_ready_for_release_host_approval"
$formalBlockers = @($readiness.blockers)

$packet = [ordered] @{
    schemaVersion = 1
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    approvalStatus = $approvalStatus
    cavemanScope = "prompt_style_profile_only"
    localEvidenceStatus = $readiness.localCavemanEvidence.status
    formalReleaseReadiness = $readiness.status
    formalReleaseBlockers = $formalBlockers
    releaseGate = $localGate.releaseGate
    evidence = [ordered] @{
        readinessAudit = $readinessPath
        formalChecklist = $checklistPath
        releaseHostRunbook = $releaseHostRunbookPath
        uiSmoke = $uiSmokePath
        deployedSmoke = $deployedSmokePath
        deployedRestoreProbe = $restoreProbePath
        localGateSummary = $localGatePath
    }
    evidenceArtifacts = [ordered] @{
        readinessAudit = Get-ArtifactRecord -Path $readinessPath
        formalChecklist = Get-ArtifactRecord -Path $checklistPath
        releaseHostRunbook = Get-ArtifactRecord -Path $releaseHostRunbookPath
        uiSmoke = Get-ArtifactRecord -Path $uiSmokePath
        deployedSmoke = Get-ArtifactRecord -Path $deployedSmokePath
        deployedRestoreProbe = Get-ArtifactRecord -Path $restoreProbePath
        localGateSummary = Get-ArtifactRecord -Path $localGatePath
    }
    provenLocalCapabilities = @(
        "users_can_select_caveman_lite_full_ultra",
        "mode_switching_is_mutually_exclusive",
        "users_can_turn_caveman_off",
        "turn_off_retains_presets_and_clears_caveman_live_prompt",
        "ui_smoke_screenshots_are_hashed",
        "deployed_smoke_restores_initial_state",
        "deployed_smoke_restores_existing_non_caveman_prompt",
        "local_gate_remains_conditional_without_release_host_evidence"
    )
    requiredBeforeFormalRelease = @(
        "non_skipbuild_release_signing_manifest_from_release_host",
        "valid_updater_signature_for_generated_nsis_setup",
        "installed_app_smoke_bound_to_signed_manifest",
        "release_host_runbook_generated_for_copyable_formal_gate",
        "final_aggregate_gate_with_RequireSigning_and_RequireInstalledSmoke"
    )
    finalGateCommand = 'rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-gate.ps1 -RequireSigning -ReleaseSigningManifestPath ".run\caveman-release-signing\caveman-release-signing-manifest.json" -RequireInstalledSmoke -InstalledAppPath "INSTALLED_APP_EXE_PATH" -InstalledSmokeEvidenceDir "INSTALLED_SMOKE_EVIDENCE_DIR" -ConfirmInstalledAppLaunched -ConfirmInstalledPromptEntryVisible -ConfirmInstalledModesVisible -ConfirmInstalledModeSequence -ConfirmInstalledTurnOffRetainsPresetDisabled -ConfirmInstalledLivePromptNonCaveman -GateSummaryPath ".run\caveman-release-gate\caveman-release-gate-summary.json"'
    note = "This packet supports Caveman prompt-level release approval preparation only. It is not a formal release pass until release-host signing and installed-app smoke evidence are attached."
}

$outputDirectory = Split-Path -Parent $resolvedOutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$packet | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8

Write-Host ("caveman_release_approval_packet={0}" -f $resolvedOutputPath)
Write-Host ("caveman_release_approval_status={0}" -f $approvalStatus)
Write-Host ("formal_release_blocked_reason={0}" -f ($formalBlockers -join ","))
