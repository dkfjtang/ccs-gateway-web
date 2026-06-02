param(
    [string] $OutputPath = ".run\caveman-release-host\caveman-release-host-runbook.json",
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

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")

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
    } else {
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }

    if (-not $candidate.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("-OutputPath must stay inside the repository: {0}" -f $Path)
    }

    return $candidate
}

function Assert-RelativeEvidenceFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path)) {
        throw ("Evidence files must be non-empty relative paths: {0}" -f $Path)
    }
}

if ($EvidenceFiles.Count -lt 1) {
    throw "At least one installed-smoke evidence file must be listed"
}
foreach ($evidenceFile in $EvidenceFiles) {
    Assert-RelativeEvidenceFile -Path $evidenceFile
}

$requiredScripts = @(
    "scripts\verify-caveman-release-signing.ps1",
    "scripts\new-caveman-installed-smoke-confirmation.ps1",
    "scripts\new-caveman-installed-smoke-evidence.ps1",
    "scripts\verify-caveman-installed-smoke.ps1",
    "scripts\verify-caveman-formal-release-readiness.ps1",
    "scripts\verify-caveman-release-gate.ps1"
)

foreach ($script in $requiredScripts) {
    $scriptPath = Join-Path $repoRoot $script
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw ("Required release-host script is missing: {0}" -f $script)
    }
}

$resolvedOutputPath = Resolve-RepoOutputPath -Path $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$evidenceFilesArgument = (($EvidenceFiles | ForEach-Object { '"' + $_ + '"' }) -join " ")

$runbook = [ordered] @{
    schemaVersion = 1
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    purpose = "release_host_formal_caveman_release_evidence"
    releaseGateTarget = "ready_for_formal_release"
    cavemanScope = "prompt_style_profile_only"
    requiredSecrets = @(
        "TAURI_SIGNING_PRIVATE_KEY",
        "TAURI_SIGNING_PRIVATE_KEY_PASSWORD optional when the key is unencrypted"
    )
    expectedInputs = [ordered] @{
        releaseSigningManifestPath = $ReleaseSigningManifestPath
        installedAppPath = $InstalledAppPath
        installedSmokeEvidenceDir = $InstalledSmokeEvidenceDir
        evidenceFiles = @($EvidenceFiles)
    }
    requiredManualObservations = @(
        "installed app executable launches",
        "OpenClaw Prompts is visible",
        "Lite, Full, Ultra, and Turn off Caveman are visible",
        "Full then Lite then Ultra activates only the selected Caveman mode",
        "Turn off keeps Caveman presets present but disabled",
        "live prompt returns to a non-Caveman state"
    )
    commands = @(
        [ordered] @{
            name = "signed_release_build"
            command = "rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-signing.ps1"
            expectedOutput = @(
                "release_signing=signed_artifacts_verified",
                "signing_manifest="
            )
            produces = @($ReleaseSigningManifestPath)
        },
        [ordered] @{
            name = "installed_smoke_confirmation_note"
            command = ("rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-installed-smoke-confirmation.ps1 -EvidenceDir ""{0}"" -InstalledAppPath ""{1}"" -ReleaseSigningManifestPath ""{2}"" -ConfirmAppLaunched -ConfirmPromptEntryVisible -ConfirmModesVisible -ConfirmModeSequence -ConfirmTurnOffRetainsPresetDisabled -ConfirmLivePromptNonCaveman" -f $InstalledSmokeEvidenceDir, $InstalledAppPath, $ReleaseSigningManifestPath)
            expectedOutput = @("installed_smoke_confirmation=created")
            produces = @((Join-Path $InstalledSmokeEvidenceDir "caveman-installed-smoke-confirmation.json"))
        },
        [ordered] @{
            name = "installed_smoke_evidence_manifest"
            command = ("rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-installed-smoke-evidence.ps1 -InstalledAppPath ""{0}"" -EvidenceDir ""{1}"" -EvidenceFiles {2} -ReleaseSigningManifestPath ""{3}""" -f $InstalledAppPath, $InstalledSmokeEvidenceDir, $evidenceFilesArgument, $ReleaseSigningManifestPath)
            expectedOutput = @("installed_smoke_evidence_manifest_created=")
            produces = @((Join-Path $InstalledSmokeEvidenceDir "caveman-installed-smoke-evidence.json"))
        },
        [ordered] @{
            name = "installed_smoke_verifier"
            command = ("rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-installed-smoke.ps1 -InstalledAppPath ""{0}"" -EvidenceDir ""{1}"" -ReleaseSigningManifestPath ""{2}"" -ConfirmAppLaunched -ConfirmPromptEntryVisible -ConfirmModesVisible -ConfirmModeSequence -ConfirmTurnOffRetainsPresetDisabled -ConfirmLivePromptNonCaveman" -f $InstalledAppPath, $InstalledSmokeEvidenceDir, $ReleaseSigningManifestPath)
            expectedOutput = @("installed_smoke=app_prompt_modes_off_live_prompt_confirmed")
        },
        [ordered] @{
            name = "formal_release_prerequisite_audit"
            command = ("rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-formal-release-readiness.ps1 -ReleaseSigningManifestPath ""{0}"" -InstalledAppPath ""{1}"" -InstalledSmokeEvidenceDir ""{2}""" -f $ReleaseSigningManifestPath, $InstalledAppPath, $InstalledSmokeEvidenceDir)
            expectedOutput = @("formal_release_readiness=formal_release_prerequisites_present")
        },
        [ordered] @{
            name = "formal_aggregate_gate"
            command = ("rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-gate.ps1 -RequireSigning -ReleaseSigningManifestPath ""{0}"" -RequireInstalledSmoke -InstalledAppPath ""{1}"" -InstalledSmokeEvidenceDir ""{2}"" -ConfirmInstalledAppLaunched -ConfirmInstalledPromptEntryVisible -ConfirmInstalledModesVisible -ConfirmInstalledModeSequence -ConfirmInstalledTurnOffRetainsPresetDisabled -ConfirmInstalledLivePromptNonCaveman -GateSummaryPath "".run\caveman-release-gate\caveman-release-gate-summary.json""" -f $ReleaseSigningManifestPath, $InstalledAppPath, $InstalledSmokeEvidenceDir)
            expectedOutput = @(
                "release_gate=ready_for_formal_release",
                "gate_summary="
            )
            produces = @(".run\caveman-release-gate\caveman-release-gate-summary.json")
        }
    )
    finalEvidence = @(
        $ReleaseSigningManifestPath,
        (Join-Path $InstalledSmokeEvidenceDir "caveman-installed-smoke-confirmation.json"),
        (Join-Path $InstalledSmokeEvidenceDir "caveman-installed-smoke-evidence.json"),
        ".run\caveman-formal-release-readiness\after-local-evidence-audit.json",
        ".run\caveman-release-gate\caveman-release-gate-summary.json"
    )
    notFormalUntil = @(
        "release signing manifest is from a non-SkipBuild signing run",
        "installed smoke evidence is bound to the signed app executable",
        "final aggregate gate reports release_gate=ready_for_formal_release"
    )
}

$runbook | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8

Write-Host ("caveman_release_host_runbook={0}" -f $resolvedOutputPath)
Write-Host "caveman_release_host_runbook=created"
