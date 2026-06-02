param(
    [string] $OutputPath = ".run\caveman-formal-release-checklist\caveman-formal-release-checklist.json",
    [string] $ReleaseSigningManifestPath = ".run\caveman-release-signing\caveman-release-signing-manifest.json",
    [string] $InstalledAppPath = "INSTALLED_APP_EXE_PATH",
    [string] $InstalledSmokeEvidenceDir = "INSTALLED_SMOKE_EVIDENCE_DIR",
    [string[]] $EvidenceFiles = @(
        "prompt-panel-full.png",
        "prompt-panel-lite.png",
        "prompt-panel-ultra.png",
        "prompt-panel-off.png"
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")

function Resolve-RepoOutputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $repoRootFullName = $repoRoot.ProviderPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $repoPrefix = $repoRootFullName + [System.IO.Path]::DirectorySeparatorChar

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $candidate = [System.IO.Path]::GetFullPath($Path)
        if (-not $candidate.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("-OutputPath must stay inside the repository: {0}" -f $Path)
        }
        return $candidate
    }

    $candidate = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    if (-not $candidate.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("-OutputPath must stay inside the repository: {0}" -f $Path)
    }

    return $candidate
}

$requiredScripts = @(
    "scripts\verify-caveman-deployed-smoke.ps1",
    "scripts\verify-caveman-deployed-smoke-restores-existing-prompt.ps1",
    "scripts\new-caveman-release-host-runbook.ps1",
    "scripts\new-caveman-release-approval-packet.ps1",
    "scripts\verify-caveman-release-approval-packet.ps1",
    "scripts\verify-caveman-release-signing.ps1",
    "scripts\new-caveman-installed-smoke-confirmation.ps1",
    "scripts\new-caveman-installed-smoke-evidence.ps1",
    "scripts\verify-caveman-formal-release-readiness.ps1",
    "scripts\verify-caveman-installed-smoke.ps1",
    "scripts\verify-caveman-release-gate.ps1"
)

foreach ($script in $requiredScripts) {
    $scriptPath = Join-Path $repoRoot $script
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw ("Required Caveman formal release script is missing: {0}" -f $script)
    }
}

if ($EvidenceFiles.Count -lt 1) {
    throw "At least one installed-smoke evidence file must be listed"
}
foreach ($evidenceFile in $EvidenceFiles) {
    if ([string]::IsNullOrWhiteSpace($evidenceFile) -or [System.IO.Path]::IsPathRooted($evidenceFile)) {
        throw ("Evidence files must be non-empty relative paths: {0}" -f $evidenceFile)
    }
}

$resolvedOutputPath = Resolve-RepoOutputPath -Path $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$manifest = [ordered] @{
    schemaVersion = 1
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    releaseGate = "blocked_until_release_host_evidence"
    blockedReasons = @(
        "requires_non_skipbuild_tauri_signing_with_TAURI_SIGNING_PRIVATE_KEY",
        "requires_installed_desktop_app_smoke_bound_to_signed_manifest",
        "requires_final_aggregate_gate_with_RequireSigning_and_RequireInstalledSmoke"
    )
    cavemanScope = "prompt_style_profile_only"
    nonNegotiableBoundaries = @(
        "no_proxy_response_rewriting",
        "no_provider_runtime_response_rewriting",
        "no_caveman_output_compression_runtime_switch",
        "token_saver_and_proxy_optimizer_changes_are_out_of_caveman_release_scope"
    )
    requiredEnvironment = @(
        "TAURI_SIGNING_PRIVATE_KEY",
        "TAURI_SIGNING_PRIVATE_KEY_PASSWORD optional when the key is unencrypted"
    )
    expectedReleaseSigningManifestPath = $ReleaseSigningManifestPath
    expectedInstalledAppPath = $InstalledAppPath
    expectedInstalledSmokeEvidenceDir = $InstalledSmokeEvidenceDir
    expectedEvidenceFiles = @($EvidenceFiles)
    localValidationCommands = @(
        [ordered] @{
            name = "deployed_local_docker_caveman_smoke"
            command = "rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-deployed-smoke.ps1"
            expectedOutput = @(
                "deployed_caveman_smoke=passed",
                "deployed_caveman_smoke_evidence="
            )
            expectedEvidenceFields = @(
                "restoreInitialState=true",
                "stateRestored=true",
                "postRestorePromptIdsMatchInitial=true",
                "postRestoreEnabledPromptIdsMatchInitial=true",
                "postRestoreLivePromptMatchesInitial=true"
            )
        },
        [ordered] @{
            name = "deployed_local_docker_existing_prompt_restore_probe"
            command = "rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-deployed-smoke-restores-existing-prompt.ps1"
            expectedOutput = @(
                "deployed_caveman_smoke_restore=passed",
                "deployed_caveman_smoke_restore_evidence="
            )
            expectedEvidenceFields = @(
                "baselineRestoredAfterSmoke=true",
                "originalRestoredAfterProbe=true"
            )
        },
        [ordered] @{
            name = "web_ui_caveman_smoke_evidence"
            command = "rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-ui-smoke.ps1"
            expectedOutput = @(
                "ui_full=ok",
                "ui_lite=ok",
                "ui_ultra=ok",
                "ui_off=ok",
                "ui_smoke_evidence="
            )
            expectedEvidenceFields = @(
                "uiControls=openclaw_prompt_entry_lite_full_ultra_turn_off",
                "uiFlow=full_to_lite_to_ultra_to_off",
                "turnOff=preset_retained_live_prompt_cleared",
                "02-caveman-full.png",
                "03-caveman-lite.png",
                "04-caveman-ultra.png",
                "05-caveman-off.png"
            )
        },
        [ordered] @{
            name = "release_host_runbook"
            command = "rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-release-host-runbook.ps1"
            expectedOutput = @(
                "caveman_release_host_runbook=",
                "caveman_release_host_runbook=created"
            )
            expectedEvidenceFields = @(
                "releaseGateTarget=ready_for_formal_release",
                "signed_release_build",
                "installed_smoke_confirmation_note",
                "formal_aggregate_gate"
            )
        },
        [ordered] @{
            name = "caveman_release_approval_packet"
            command = "rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-release-approval-packet.ps1"
            expectedOutput = @(
                "caveman_release_approval_packet=",
                "caveman_release_approval_status=conditional_caveman_only_ready_for_release_host_approval",
                "formal_release_blocked_reason="
            )
            expectedEvidenceFields = @(
                "localEvidenceStatus=local_caveman_evidence_present",
                "formalReleaseReadiness=formal_release_prerequisites_blocked",
                "releaseGate=conditional_caveman_only"
            )
        },
        [ordered] @{
            name = "caveman_release_approval_packet_verifier"
            command = "rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-approval-packet.ps1"
            expectedOutput = @(
                "caveman_release_approval_packet_verified=",
                "approval_packet_status=conditional_caveman_only_ready_for_release_host_approval"
            )
        }
    )
    releaseHostCommands = @(
        [ordered] @{
            name = "signed_release_build"
            command = "rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-signing.ps1"
            expectedOutput = @(
                "release_signing=signed_artifacts_verified",
                "signing_manifest="
            )
        },
        [ordered] @{
            name = "manual_installed_desktop_smoke"
            requiredObservations = @(
                "installed app executable launches",
                "OpenClaw Prompts is visible",
                "Lite, Full, Ultra, and Turn off Caveman are visible",
                "Full then Lite then Ultra sequence activates each selected mode",
                "Turn off keeps the Caveman preset record but disables it",
                "live prompt returns to a non-Caveman state"
            )
        },
        [ordered] @{
            name = "installed_smoke_confirmation_note"
            command = ("rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-installed-smoke-confirmation.ps1 -EvidenceDir ""{0}"" -InstalledAppPath ""{1}"" -ReleaseSigningManifestPath ""{2}"" -ConfirmAppLaunched -ConfirmPromptEntryVisible -ConfirmModesVisible -ConfirmModeSequence -ConfirmTurnOffRetainsPresetDisabled -ConfirmLivePromptNonCaveman" -f $InstalledSmokeEvidenceDir, $InstalledAppPath, $ReleaseSigningManifestPath)
            expectedOutput = @(
                "installed_smoke_confirmation=created"
            )
        },
        [ordered] @{
            name = "installed_smoke_evidence_manifest"
            command = ("rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-installed-smoke-evidence.ps1 -InstalledAppPath ""{0}"" -EvidenceDir ""{1}"" -EvidenceFiles {2} -ReleaseSigningManifestPath ""{3}""" -f $InstalledAppPath, $InstalledSmokeEvidenceDir, (($EvidenceFiles | ForEach-Object { '"' + $_ + '"' }) -join " "), $ReleaseSigningManifestPath)
            expectedOutput = @(
                "installed_smoke_evidence_manifest_created="
            )
        },
        [ordered] @{
            name = "formal_release_prerequisite_audit"
            command = ("rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-formal-release-readiness.ps1 -ReleaseSigningManifestPath ""{0}"" -InstalledAppPath ""{1}"" -InstalledSmokeEvidenceDir ""{2}""" -f $ReleaseSigningManifestPath, $InstalledAppPath, $InstalledSmokeEvidenceDir)
            expectedOutput = @(
                "formal_release_readiness=formal_release_prerequisites_present"
            )
        },
        [ordered] @{
            name = "formal_aggregate_gate"
            command = ("rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-gate.ps1 -RequireSigning -ReleaseSigningManifestPath ""{0}"" -RequireInstalledSmoke -InstalledAppPath ""{1}"" -InstalledSmokeEvidenceDir ""{2}"" -ConfirmInstalledAppLaunched -ConfirmInstalledPromptEntryVisible -ConfirmInstalledModesVisible -ConfirmInstalledModeSequence -ConfirmInstalledTurnOffRetainsPresetDisabled -ConfirmInstalledLivePromptNonCaveman -GateSummaryPath "".run\caveman-release-gate\caveman-release-gate-summary.json""" -f $ReleaseSigningManifestPath, $InstalledAppPath, $InstalledSmokeEvidenceDir)
            expectedOutput = @(
                "release_gate=ready_for_formal_release"
                "gate_summary="
            )
        }
    )
}

$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8

Write-Host ("formal_release_checklist={0}" -f $resolvedOutputPath)
Write-Host "formal_release_blocked_reason=release_host_signing_and_installed_smoke_required"
Write-Host "formal_release_checklist=created"
