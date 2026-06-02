param(
    [string] $RunDir = ".run\caveman-release-hardening"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$runPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $RunDir))
$fakeLocalAppData = Join-Path "C:\tmp" "caveman-release-hardening-localappdata"
$fakePrograms = Join-Path $fakeLocalAppData "Programs"
$fakeProgramsPrefix = Join-Path $fakeLocalAppData "ProgramsFake"
$fakeBundleRoot = Join-Path $runPath "fake-bundle"
$fakeBuiltAppExe = Join-Path $runPath "fake-build\cc-switch.exe"
$originalSigningPrivateKey = [Environment]::GetEnvironmentVariable("TAURI_SIGNING_PRIVATE_KEY")
$originalLocalAppData = [Environment]::GetEnvironmentVariable("LOCALAPPDATA")

New-Item -ItemType Directory -Force -Path $runPath | Out-Null
if (Test-Path -LiteralPath $fakeBundleRoot) {
    Remove-Item -LiteralPath $fakeBundleRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $fakeBundleRoot "msi") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $fakeBundleRoot "nsis") | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fakeBuiltAppExe) | Out-Null
New-Item -ItemType File -Force -Path (Join-Path $fakeBundleRoot "msi\CC Switch_0.0.0_x64_en-US.msi") | Out-Null
New-Item -ItemType File -Force -Path (Join-Path $fakeBundleRoot "nsis\CC Switch_0.0.0_x64-setup.exe") | Out-Null
Set-Content -LiteralPath $fakeBuiltAppExe -Encoding UTF8 -Value "fake built app exe for release hardening."

function Invoke-ExpectFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [scriptblock] $Action,
        [Parameter(Mandatory = $true)]
        [string] $ExpectedOutput
    )

    Write-Host ("==> {0}" -f $Name)
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $Action 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $text = ($output | Out-String)

    if ($exitCode -eq 0) {
        throw ("{0} unexpectedly passed. Output: {1}" -f $Name, $text)
    }
    if ($text -notmatch [regex]::Escape($ExpectedOutput)) {
        throw ("{0} failed, but did not contain expected output '{1}'. Output: {2}" -f $Name, $ExpectedOutput, $text)
    }

    Write-Host ("{0}=blocked" -f $Name)
}

function Invoke-ExpectSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [scriptblock] $Action,
        [Parameter(Mandatory = $true)]
        [string] $ExpectedOutput
    )

    Write-Host ("==> {0}" -f $Name)
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $Action 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $text = ($output | Out-String)

    if ($exitCode -ne 0) {
        throw ("{0} failed with exit code {1}. Output: {2}" -f $Name, $exitCode, $text)
    }
    if ($text -notmatch [regex]::Escape($ExpectedOutput)) {
        throw ("{0} passed, but did not contain expected output '{1}'. Output: {2}" -f $Name, $ExpectedOutput, $text)
    }

    Write-Host ("{0}=ok" -f $Name)
}

Invoke-ExpectFailure -Name "signing_missing_private_key" -ExpectedOutput "Missing required release signing environment variable: TAURI_SIGNING_PRIVATE_KEY" -Action {
    try {
        $env:TAURI_SIGNING_PRIVATE_KEY = $null
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-signing.ps1" -SkipBuild
    } finally {
        $env:TAURI_SIGNING_PRIVATE_KEY = $originalSigningPrivateKey
    }
}

Invoke-ExpectFailure -Name "signing_requires_matching_sig" -ExpectedOutput ".exe.sig" -Action {
    try {
        $env:TAURI_SIGNING_PRIVATE_KEY = "fake-test-key"
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-signing.ps1" -BundleRoot $fakeBundleRoot -AppExePath $fakeBuiltAppExe -SkipBuild
    } finally {
        $env:TAURI_SIGNING_PRIVATE_KEY = $originalSigningPrivateKey
    }
}

$prefixDir = Join-Path $fakeProgramsPrefix "CC Switch"
$prefixExe = Join-Path $prefixDir "cc-switch.exe"
New-Item -ItemType Directory -Force -Path $prefixDir | Out-Null
New-Item -ItemType File -Force -Path $prefixExe | Out-Null

Invoke-ExpectFailure -Name "installed_path_prefix_rejected" -ExpectedOutput "ProgramsFake" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $prefixExe -ValidatePathOnly
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

$validDir = Join-Path $fakePrograms "CC Switch"
$validExe = Join-Path $validDir "cc-switch.exe"
New-Item -ItemType Directory -Force -Path $validDir | Out-Null
Copy-Item -LiteralPath $fakeBuiltAppExe -Destination $validExe -Force

Invoke-ExpectSuccess -Name "installed_path_standard_root_validated" -ExpectedOutput "installed_app_path_validated=" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $validExe -ValidatePathOnly
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

$wrongNameExe = Join-Path $validDir "not-cc-switch.exe"
New-Item -ItemType File -Force -Path $wrongNameExe | Out-Null

Invoke-ExpectFailure -Name "installed_non_cc_switch_exe_rejected" -ExpectedOutput "expects the installed CC Switch executable" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $wrongNameExe -ValidatePathOnly
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

$installedConfirmations = @(
    "-ConfirmAppLaunched",
    "-ConfirmPromptEntryVisible",
    "-ConfirmModesVisible",
    "-ConfirmModeSequence",
    "-ConfirmTurnOffRetainsPresetDisabled",
    "-ConfirmLivePromptNonCaveman"
)

Invoke-ExpectFailure -Name "installed_smoke_requires_evidence_dir" -ExpectedOutput "-EvidenceDir is required for installed-app smoke confirmations" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $validExe @installedConfirmations
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Invoke-ExpectFailure -Name "release_gate_requires_installed_smoke_evidence_dir" -ExpectedOutput "-InstalledSmokeEvidenceDir is required when -RequireInstalledSmoke is set" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -RequireInstalledSmoke -InstalledAppPath $validExe -ConfirmInstalledAppLaunched -ConfirmInstalledPromptEntryVisible -ConfirmInstalledModesVisible -ConfirmInstalledModeSequence -ConfirmInstalledTurnOffRetainsPresetDisabled -ConfirmInstalledLivePromptNonCaveman
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

$emptyEvidenceDir = Join-Path $runPath "empty-installed-smoke-evidence"
if (Test-Path -LiteralPath $emptyEvidenceDir) {
    Remove-Item -LiteralPath $emptyEvidenceDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $emptyEvidenceDir | Out-Null

Invoke-ExpectFailure -Name "installed_smoke_rejects_empty_evidence_dir" -ExpectedOutput "Installed-app smoke evidence directory must contain at least one file" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $validExe -EvidenceDir $emptyEvidenceDir @installedConfirmations
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Invoke-ExpectFailure -Name "release_gate_rejects_empty_installed_smoke_evidence_dir" -ExpectedOutput "Installed-app smoke evidence directory must contain at least one file" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -RequireInstalledSmoke -InstalledAppPath $validExe -InstalledSmokeEvidenceDir $emptyEvidenceDir -ConfirmInstalledAppLaunched -ConfirmInstalledPromptEntryVisible -ConfirmInstalledModesVisible -ConfirmInstalledModeSequence -ConfirmInstalledTurnOffRetainsPresetDisabled -ConfirmInstalledLivePromptNonCaveman
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

$validEvidenceDir = Join-Path $runPath "valid-installed-smoke-evidence"
if (Test-Path -LiteralPath $validEvidenceDir) {
    Remove-Item -LiteralPath $validEvidenceDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $validEvidenceDir | Out-Null
$validEvidenceFile = Join-Path $validEvidenceDir "installed-smoke-note.txt"
Set-Content -LiteralPath $validEvidenceFile -Encoding UTF8 -Value "Caveman installed-app smoke evidence placeholder for release hardening."
$validConfirmationFile = Join-Path $validEvidenceDir "caveman-installed-smoke-confirmation.json"

Invoke-ExpectFailure -Name "installed_smoke_rejects_missing_evidence_manifest" -ExpectedOutput "Installed-app smoke evidence manifest is required" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir @installedConfirmations
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Invoke-ExpectFailure -Name "release_gate_rejects_missing_installed_smoke_evidence_manifest" -ExpectedOutput "Installed-app smoke evidence manifest is required" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -RequireInstalledSmoke -InstalledAppPath $validExe -InstalledSmokeEvidenceDir $validEvidenceDir -ConfirmInstalledAppLaunched -ConfirmInstalledPromptEntryVisible -ConfirmInstalledModesVisible -ConfirmInstalledModeSequence -ConfirmInstalledTurnOffRetainsPresetDisabled -ConfirmInstalledLivePromptNonCaveman
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Invoke-ExpectFailure -Name "installed_smoke_confirmation_requires_all_confirmations" -ExpectedOutput "requires all confirmation switches" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-installed-smoke-confirmation.ps1" -EvidenceDir $validEvidenceDir -InstalledAppPath $validExe -ReleaseSigningManifestPath (Join-Path $runPath "missing-release-signing-manifest.json") -ConfirmAppLaunched
}

$missingSigningManifestPath = Join-Path $runPath "missing-release-signing-manifest.json"
Invoke-ExpectFailure -Name "release_gate_rejects_relative_signing_manifest_escape" -ExpectedOutput "Relative -ReleaseSigningManifestPath must stay inside the repository" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -RequireSigning -ReleaseSigningManifestPath "..\outside-release-signing-manifest.json"
}

Invoke-ExpectFailure -Name "release_gate_rejects_relative_summary_escape" -ExpectedOutput "-GateSummaryPath must stay inside .run\caveman-release-gate" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -GateSummaryPath "..\outside-caveman-release-gate-summary.json"
}

Invoke-ExpectFailure -Name "release_gate_rejects_repo_file_summary_overwrite" -ExpectedOutput "-GateSummaryPath must stay inside .run\caveman-release-gate" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -GateSummaryPath "docs\ccs-caveman-release-readiness.md"
}

Invoke-ExpectFailure -Name "release_gate_requires_signing_manifest" -ExpectedOutput "Release signing manifest is required when -RequireSigning is set" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -RequireSigning -ReleaseSigningManifestPath $missingSigningManifestPath
}

Invoke-ExpectSuccess -Name "formal_release_checklist_created" -ExpectedOutput "formal_release_checklist=created" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-formal-release-checklist.ps1" -OutputPath ".run\caveman-release-hardening\formal-release-checklist.json"
}

Invoke-ExpectSuccess -Name "formal_release_checklist_includes_deployed_smoke" -ExpectedOutput "formal_release_checklist_includes_deployed_smoke=ok" -Action {
    $checklistPath = ".run\caveman-release-hardening\formal-release-checklist.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-formal-release-checklist.ps1" -OutputPath $checklistPath | Out-Null
    $checklist = Get-Content -LiteralPath $checklistPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $localValidationCommands = @($checklist.localValidationCommands)
    if (-not ($localValidationCommands | Where-Object { $_.name -eq "deployed_local_docker_caveman_smoke" })) {
        throw "formal release checklist is missing deployed local Docker Caveman smoke"
    }
    Write-Output "formal_release_checklist_includes_deployed_smoke=ok"
}

Invoke-ExpectSuccess -Name "deployed_smoke_restores_initial_state_by_default" -ExpectedOutput "deployed_smoke_restores_initial_state_by_default=ok" -Action {
    $deployedSmokeScript = Get-Content -LiteralPath ".\scripts\verify-caveman-deployed-smoke.ps1" -Raw -Encoding UTF8
    foreach ($requiredText in @(
        '[bool] $RestoreInitialState = $true',
        'function Restore-PromptState',
        'if ($RestoreInitialState)',
        'stateRestored = [bool] $stateRestored',
        'postRestorePromptIdsMatchInitial',
        'postRestoreEnabledPromptIdsMatchInitial',
        'postRestoreLivePromptMatchesInitial',
        'Assert-True -Condition $postRestorePromptIdsMatchInitial',
        'Assert-True -Condition $postRestoreEnabledPromptIdsMatchInitial',
        'Assert-True -Condition $postRestoreLivePromptMatchesInitial'
    )) {
        if (-not $deployedSmokeScript.Contains($requiredText)) {
            throw ("deployed smoke script is missing state restoration guard: {0}" -f $requiredText)
        }
    }

    $checklistPath = ".run\caveman-release-hardening\formal-release-checklist.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-formal-release-checklist.ps1" -OutputPath $checklistPath | Out-Null
    $checklist = Get-Content -LiteralPath $checklistPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $deployedSmokeCommand = @($checklist.localValidationCommands) | Where-Object { $_.name -eq "deployed_local_docker_caveman_smoke" } | Select-Object -First 1
    $expectedFields = @($deployedSmokeCommand.expectedEvidenceFields)
    foreach ($field in @("restoreInitialState=true", "stateRestored=true", "postRestorePromptIdsMatchInitial=true", "postRestoreEnabledPromptIdsMatchInitial=true", "postRestoreLivePromptMatchesInitial=true")) {
        if ($expectedFields -notcontains $field) {
            throw ("formal release checklist is missing deployed smoke restoration evidence field: {0}" -f $field)
        }
    }

    Write-Output "deployed_smoke_restores_initial_state_by_default=ok"
}

Invoke-ExpectSuccess -Name "release_readiness_doc_mentions_ui_smoke_manifest" -ExpectedOutput "release_readiness_doc_mentions_ui_smoke_manifest=ok" -Action {
    $doc = Get-Content -LiteralPath ".\docs\ccs-caveman-release-readiness.md" -Raw -Encoding UTF8
    foreach ($requiredText in @(
        ".run\caveman-ui-smoke\caveman-ui-smoke-evidence.json",
        "ui_smoke_screenshots_are_hashed",
        "UI smoke evidence manifest",
        "SHA256 hashes for each screenshot"
    )) {
        if (-not $doc.Contains($requiredText)) {
            throw ("release readiness doc is missing UI smoke evidence text: {0}" -f $requiredText)
        }
    }
    Write-Output "release_readiness_doc_mentions_ui_smoke_manifest=ok"
}

Invoke-ExpectSuccess -Name "formal_release_checklist_includes_existing_prompt_restore_probe" -ExpectedOutput "formal_release_checklist_includes_existing_prompt_restore_probe=ok" -Action {
    $restoreProbeScript = Get-Content -LiteralPath ".\scripts\verify-caveman-deployed-smoke-restores-existing-prompt.ps1" -Raw -Encoding UTF8
    foreach ($requiredText in @(
        'probePromptId = $probeId',
        'baselineRestoredAfterSmoke = $baselineRestoredAfterSmoke',
        'originalRestoredAfterProbe = $originalRestoredAfterProbe',
        'Assert-True -Condition $baselineRestoredAfterSmoke',
        'Assert-True -Condition $originalRestoredAfterProbe'
    )) {
        if (-not $restoreProbeScript.Contains($requiredText)) {
            throw ("deployed smoke restore probe is missing required restoration assertion: {0}" -f $requiredText)
        }
    }

    $checklistPath = ".run\caveman-release-hardening\formal-release-checklist.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-formal-release-checklist.ps1" -OutputPath $checklistPath | Out-Null
    $checklist = Get-Content -LiteralPath $checklistPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $restoreProbeCommand = @($checklist.localValidationCommands) | Where-Object { $_.name -eq "deployed_local_docker_existing_prompt_restore_probe" } | Select-Object -First 1
    if ($null -eq $restoreProbeCommand) {
        throw "formal release checklist is missing deployed local Docker existing prompt restore probe"
    }
    $expectedFields = @($restoreProbeCommand.expectedEvidenceFields)
    foreach ($field in @("baselineRestoredAfterSmoke=true", "originalRestoredAfterProbe=true")) {
        if ($expectedFields -notcontains $field) {
            throw ("formal release checklist is missing restore probe evidence field: {0}" -f $field)
        }
    }

    Write-Output "formal_release_checklist_includes_existing_prompt_restore_probe=ok"
}

Invoke-ExpectSuccess -Name "formal_release_checklist_includes_ui_smoke_evidence" -ExpectedOutput "formal_release_checklist_includes_ui_smoke_evidence=ok" -Action {
    $checklistPath = ".run\caveman-release-hardening\formal-release-checklist.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-formal-release-checklist.ps1" -OutputPath $checklistPath | Out-Null
    $checklist = Get-Content -LiteralPath $checklistPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $uiSmokeCommand = @($checklist.localValidationCommands) | Where-Object { $_.name -eq "web_ui_caveman_smoke_evidence" } | Select-Object -First 1
    if ($null -eq $uiSmokeCommand) {
        throw "formal release checklist is missing Web UI Caveman smoke evidence command"
    }
    foreach ($expectedOutput in @("ui_full=ok", "ui_lite=ok", "ui_ultra=ok", "ui_off=ok", "ui_smoke_evidence=")) {
        if (@($uiSmokeCommand.expectedOutput) -notcontains $expectedOutput) {
            throw ("formal release checklist is missing UI smoke expected output: {0}" -f $expectedOutput)
        }
    }
    foreach ($field in @(
        "uiControls=openclaw_prompt_entry_lite_full_ultra_turn_off",
        "uiFlow=full_to_lite_to_ultra_to_off",
        "turnOff=preset_retained_live_prompt_cleared",
        "02-caveman-full.png",
        "03-caveman-lite.png",
        "04-caveman-ultra.png",
        "05-caveman-off.png"
    )) {
        if (@($uiSmokeCommand.expectedEvidenceFields) -notcontains $field) {
            throw ("formal release checklist is missing UI smoke evidence field: {0}" -f $field)
        }
    }
    Write-Output "formal_release_checklist_includes_ui_smoke_evidence=ok"
}

Invoke-ExpectSuccess -Name "formal_release_checklist_includes_approval_packet" -ExpectedOutput "formal_release_checklist_includes_approval_packet=ok" -Action {
    $checklistPath = ".run\caveman-release-hardening\formal-release-checklist.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-formal-release-checklist.ps1" -OutputPath $checklistPath | Out-Null
    $checklist = Get-Content -LiteralPath $checklistPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $approvalPacketCommand = @($checklist.localValidationCommands) | Where-Object { $_.name -eq "caveman_release_approval_packet" } | Select-Object -First 1
    if ($null -eq $approvalPacketCommand) {
        throw "formal release checklist is missing Caveman release approval packet command"
    }
    foreach ($field in @("localEvidenceStatus=local_caveman_evidence_present", "formalReleaseReadiness=formal_release_prerequisites_blocked", "releaseGate=conditional_caveman_only")) {
        if (@($approvalPacketCommand.expectedEvidenceFields) -notcontains $field) {
            throw ("formal release checklist is missing approval packet evidence field: {0}" -f $field)
        }
    }
    Write-Output "formal_release_checklist_includes_approval_packet=ok"
}

Invoke-ExpectSuccess -Name "release_host_runbook_created" -ExpectedOutput "caveman_release_host_runbook=created" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-release-host-runbook.ps1" -OutputPath ".run\caveman-release-hardening\release-host-runbook.json"
}

Invoke-ExpectSuccess -Name "release_host_runbook_includes_formal_gate" -ExpectedOutput "release_host_runbook_includes_formal_gate=ok" -Action {
    $runbookPath = ".run\caveman-release-hardening\release-host-runbook.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-release-host-runbook.ps1" -OutputPath $runbookPath | Out-Null
    $runbook = Get-Content -LiteralPath $runbookPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($runbook.releaseGateTarget -ne "ready_for_formal_release") {
        throw ("release-host runbook target is not formal release: {0}" -f $runbook.releaseGateTarget)
    }
    foreach ($evidenceFile in @(
        "prompt-panel-full.png",
        "prompt-panel-lite.png",
        "prompt-panel-ultra.png",
        "prompt-panel-off.png"
    )) {
        if (@($runbook.expectedInputs.evidenceFiles) -notcontains $evidenceFile) {
            throw ("release-host runbook is missing installed-app evidence file: {0}" -f $evidenceFile)
        }
    }
    foreach ($commandName in @(
        "signed_release_build",
        "installed_smoke_confirmation_note",
        "installed_smoke_evidence_manifest",
        "installed_smoke_verifier",
        "formal_release_prerequisite_audit",
        "formal_aggregate_gate"
    )) {
        if (-not (@($runbook.commands) | Where-Object { $_.name -eq $commandName })) {
            throw ("release-host runbook is missing command: {0}" -f $commandName)
        }
    }
    $formalGate = @($runbook.commands) | Where-Object { $_.name -eq "formal_aggregate_gate" } | Select-Object -First 1
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
        "-ConfirmInstalledLivePromptNonCaveman",
        "release_gate=ready_for_formal_release"
    )) {
        $commandText = ([string] $formalGate.command) + " " + (@($formalGate.expectedOutput) -join " ")
        if (-not $commandText.Contains($requiredText)) {
            throw ("release-host final gate is missing required text: {0}" -f $requiredText)
        }
    }
    Write-Output "release_host_runbook_includes_formal_gate=ok"
}

Invoke-ExpectFailure -Name "formal_release_checklist_rejects_relative_output_escape" -ExpectedOutput "-OutputPath must stay inside the repository" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-formal-release-checklist.ps1" -OutputPath "..\outside-caveman-formal-release-checklist.json"
}

Invoke-ExpectFailure -Name "formal_release_checklist_rejects_absolute_output_escape" -ExpectedOutput "-OutputPath must stay inside the repository" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-formal-release-checklist.ps1" -OutputPath (Join-Path "C:\tmp" "outside-caveman-formal-release-checklist.json")
}

Invoke-ExpectSuccess -Name "formal_release_readiness_reports_missing_evidence" -ExpectedOutput "formal_release_readiness=formal_release_prerequisites_blocked" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-formal-release-readiness.ps1" -OutputPath ".run\caveman-release-hardening\formal-release-readiness.json"
}

Invoke-ExpectSuccess -Name "formal_release_readiness_reports_local_caveman_evidence" -ExpectedOutput "formal_release_readiness_reports_local_caveman_evidence=ok" -Action {
    $readinessPath = ".run\caveman-release-hardening\formal-release-readiness-local-evidence.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-formal-release-readiness.ps1" -OutputPath $readinessPath | Out-Null
    $readiness = Get-Content -LiteralPath $readinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($readiness.localCavemanEvidence.status -ne "local_caveman_evidence_present") {
        throw ("formal readiness local Caveman evidence was not present: {0}" -f $readiness.localCavemanEvidence.status)
    }
    foreach ($checkName in @("deployedSmoke", "deployedRestoreProbe", "localGateSummary")) {
        if ($readiness.localCavemanEvidence.checks.$checkName.status -ne "read") {
            throw ("formal readiness local Caveman evidence check was not readable: {0}" -f $checkName)
        }
    }
    if ($readiness.status -ne "formal_release_prerequisites_blocked") {
        throw ("formal readiness should remain blocked without release-host evidence: {0}" -f $readiness.status)
    }
    Write-Output "formal_release_readiness_reports_local_caveman_evidence=ok"
}

Invoke-ExpectSuccess -Name "approval_packet_reports_conditional_status" -ExpectedOutput "approval_packet_reports_conditional_status=ok" -Action {
    $packetPath = ".run\caveman-release-hardening\approval-packet.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-release-approval-packet.ps1" -OutputPath $packetPath | Out-Null
    $packet = Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($packet.approvalStatus -ne "conditional_caveman_only_ready_for_release_host_approval") {
        throw ("unexpected approval packet status: {0}" -f $packet.approvalStatus)
    }
    if ($packet.formalReleaseReadiness -ne "formal_release_prerequisites_blocked") {
        throw ("approval packet must keep formal release readiness blocked without release-host evidence: {0}" -f $packet.formalReleaseReadiness)
    }
    if ($packet.localEvidenceStatus -ne "local_caveman_evidence_present") {
        throw ("approval packet local evidence is not present: {0}" -f $packet.localEvidenceStatus)
    }
    if (@($packet.provenLocalCapabilities) -notcontains "ui_smoke_screenshots_are_hashed") {
        throw "approval packet is missing hashed UI smoke screenshot capability"
    }
    if (@($packet.requiredBeforeFormalRelease).Count -lt 5) {
        throw "approval packet is missing required formal release follow-up items"
    }
    foreach ($artifactName in @("readinessAudit", "formalChecklist", "releaseHostRunbook", "uiSmoke", "deployedSmoke", "deployedRestoreProbe", "localGateSummary")) {
        $artifact = $packet.evidenceArtifacts.$artifactName
        if ($null -eq $artifact) {
            throw ("approval packet is missing evidence artifact record: {0}" -f $artifactName)
        }
        if ([string]::IsNullOrWhiteSpace([string] $artifact.path)) {
            throw ("approval packet evidence artifact path is missing: {0}" -f $artifactName)
        }
        if ([string] $artifact.sha256 -notmatch "^[A-Fa-f0-9]{64}$") {
            throw ("approval packet evidence artifact SHA256 is invalid for {0}: {1}" -f $artifactName, $artifact.sha256)
        }
    }
    $uiSmokePath = $packet.evidenceArtifacts.uiSmoke.path
    $uiSmoke = Get-Content -LiteralPath $uiSmokePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($uiSmoke.uiControls -ne "openclaw_prompt_entry_lite_full_ultra_turn_off") {
        throw ("approval packet UI smoke evidence has unexpected controls: {0}" -f $uiSmoke.uiControls)
    }
    if ($uiSmoke.uiFlow -ne "full_to_lite_to_ultra_to_off") {
        throw ("approval packet UI smoke evidence has unexpected flow: {0}" -f $uiSmoke.uiFlow)
    }
    if ($uiSmoke.turnOff -ne "preset_retained_live_prompt_cleared") {
        throw ("approval packet UI smoke evidence has unexpected off semantics: {0}" -f $uiSmoke.turnOff)
    }
    foreach ($screenshot in @("02-caveman-full.png", "03-caveman-lite.png", "04-caveman-ultra.png", "05-caveman-off.png")) {
        if ($null -eq $uiSmoke.screenshots.$screenshot) {
            throw ("approval packet UI smoke evidence is missing screenshot: {0}" -f $screenshot)
        }
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
        if (-not ([string] $packet.finalGateCommand).Contains($requiredText)) {
            throw ("approval packet final gate command is missing required argument: {0}" -f $requiredText)
        }
    }
    Write-Output "approval_packet_reports_conditional_status=ok"
}

Invoke-ExpectSuccess -Name "approval_packet_verifier_accepts_current_packet" -ExpectedOutput "approval_packet_status=conditional_caveman_only_ready_for_release_host_approval" -Action {
    $packetPath = ".run\caveman-release-hardening\approval-packet.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-release-approval-packet.ps1" -OutputPath $packetPath | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-approval-packet.ps1" -ApprovalPacketPath $packetPath
}

Invoke-ExpectFailure -Name "approval_packet_verifier_rejects_tampered_evidence_hash" -ExpectedOutput "Evidence artifact SHA256 mismatch" -Action {
    $packetPath = ".run\caveman-release-hardening\tampered-approval-packet.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-release-approval-packet.ps1" -OutputPath $packetPath | Out-Null
    $packet = Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $packet.evidenceArtifacts.deployedSmoke.sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
    $packet | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $packetPath -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-approval-packet.ps1" -ApprovalPacketPath $packetPath
}

Invoke-ExpectFailure -Name "formal_release_readiness_rejects_absolute_output_escape" -ExpectedOutput "-OutputPath must stay inside the repository" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-formal-release-readiness.ps1" -OutputPath (Join-Path "C:\tmp" "outside-caveman-formal-release-readiness.json")
}

$fakeSignedNsis = Join-Path $fakeBundleRoot "nsis\CC Switch_0.0.0_x64-setup.exe"
$fakeSignedSig = ("{0}.sig" -f $fakeSignedNsis)
Set-Content -LiteralPath $fakeSignedSig -Encoding UTF8 -Value "fake updater signature for release hardening."

Invoke-ExpectSuccess -Name "signing_manifest_includes_app_exe" -ExpectedOutput "app_exe=" -Action {
    try {
        $env:TAURI_SIGNING_PRIVATE_KEY = "fake-test-key"
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-signing.ps1" -BundleRoot $fakeBundleRoot -AppExePath $fakeBuiltAppExe -SkipBuild
    } finally {
        $env:TAURI_SIGNING_PRIVATE_KEY = $originalSigningPrivateKey
    }
}

$fakeSigningManifestPath = Join-Path $runPath "fake-release-signing-manifest.json"
$fakeSigningManifest = @{
    skipBuild = $false
    buildStartedAt = (Get-Date).ToUniversalTime().ToString("o")
    msiPath = ([System.IO.Path]::GetFullPath((Join-Path $fakeBundleRoot "msi\CC Switch_0.0.0_x64_en-US.msi")))
    msiSha256 = (Get-FileHash -LiteralPath (Join-Path $fakeBundleRoot "msi\CC Switch_0.0.0_x64_en-US.msi") -Algorithm SHA256).Hash
    nsisPath = ([System.IO.Path]::GetFullPath($fakeSignedNsis))
    nsisSha256 = (Get-FileHash -LiteralPath $fakeSignedNsis -Algorithm SHA256).Hash
    appExePath = ([System.IO.Path]::GetFullPath($fakeBuiltAppExe))
    appExeSha256 = (Get-FileHash -LiteralPath $fakeBuiltAppExe -Algorithm SHA256).Hash
    signaturePath = ([System.IO.Path]::GetFullPath($fakeSignedSig))
    signatureSha256 = (Get-FileHash -LiteralPath $fakeSignedSig -Algorithm SHA256).Hash
}

function Restore-FakeSigningManifest {
    Set-Content -LiteralPath $fakeSignedSig -Encoding UTF8 -Value "fake updater signature for release hardening."
    $fakeSigningManifest.signatureSha256 = (Get-FileHash -LiteralPath $fakeSignedSig -Algorithm SHA256).Hash
    $fakeSigningManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $fakeSigningManifestPath -Encoding UTF8
}

Restore-FakeSigningManifest

$tamperedSigningManifestPath = Join-Path $runPath "tampered-release-signing-manifest.json"
$tamperedSigningManifest = @{
    skipBuild = $false
    buildStartedAt = (Get-Date).ToUniversalTime().ToString("o")
    msiPath = (Join-Path $fakeBundleRoot "msi\CC Switch_0.0.0_x64_en-US.msi")
    msiSha256 = (Get-FileHash -LiteralPath (Join-Path $fakeBundleRoot "msi\CC Switch_0.0.0_x64_en-US.msi") -Algorithm SHA256).Hash
    nsisPath = $fakeSigningManifest.nsisPath
    nsisSha256 = $fakeSigningManifest.nsisSha256
    appExePath = $fakeSigningManifest.appExePath
    appExeSha256 = "0000000000000000000000000000000000000000000000000000000000000000"
    signaturePath = $fakeSigningManifest.signaturePath
    signatureSha256 = $fakeSigningManifest.signatureSha256
}
$tamperedSigningManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tamperedSigningManifestPath -Encoding UTF8

Invoke-ExpectFailure -Name "release_gate_rejects_tampered_signing_manifest" -ExpectedOutput "appExe artifact SHA256 does not match" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -RequireSigning -ReleaseSigningManifestPath $tamperedSigningManifestPath
}

Invoke-ExpectFailure -Name "release_gate_rejects_untrusted_signing_manifest" -ExpectedOutput "updater signature is not valid" -Action {
    Restore-FakeSigningManifest
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -RequireSigning -ReleaseSigningManifestPath $fakeSigningManifestPath
}

Invoke-ExpectFailure -Name "installed_smoke_manifest_helper_requires_confirmation_note" -ExpectedOutput "Installed smoke confirmation note is required" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-installed-smoke-evidence.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir -EvidenceFiles "installed-smoke-note.txt"
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Invoke-ExpectSuccess -Name "installed_smoke_confirmation_note_created" -ExpectedOutput "installed_smoke_confirmation=created" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-installed-smoke-confirmation.ps1" -EvidenceDir $validEvidenceDir -InstalledAppPath $validExe -ReleaseSigningManifestPath $fakeSigningManifestPath -ConfirmAppLaunched -ConfirmPromptEntryVisible -ConfirmModesVisible -ConfirmModeSequence -ConfirmTurnOffRetainsPresetDisabled -ConfirmLivePromptNonCaveman
}

Invoke-ExpectSuccess -Name "installed_smoke_manifest_helper_creates_valid_manifest" -ExpectedOutput "installed_smoke_evidence_manifest_created=" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-installed-smoke-evidence.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir -EvidenceFiles "installed-smoke-note.txt"
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Set-Content -LiteralPath $validEvidenceFile -Encoding UTF8 -Value "Caveman installed-app smoke evidence tampered after manifest generation."
Invoke-ExpectFailure -Name "installed_smoke_rejects_tampered_evidence_file" -ExpectedOutput "evidence file SHA256 does not match manifest" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir -ValidateEvidenceOnly
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}
Set-Content -LiteralPath $validEvidenceFile -Encoding UTF8 -Value "Caveman installed-app smoke evidence placeholder for release hardening."
Invoke-ExpectSuccess -Name "installed_smoke_manifest_helper_refreshes_evidence_hash" -ExpectedOutput "installed_smoke_evidence_manifest_created=" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-installed-smoke-evidence.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir -EvidenceFiles "installed-smoke-note.txt"
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Set-Content -LiteralPath $validConfirmationFile -Encoding UTF8 -Value "{}"
Invoke-ExpectFailure -Name "installed_smoke_rejects_tampered_confirmation_note" -ExpectedOutput "evidence file SHA256 does not match manifest" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir -ValidateEvidenceOnly
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}
Invoke-ExpectSuccess -Name "installed_smoke_confirmation_note_restored" -ExpectedOutput "installed_smoke_confirmation=created" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-installed-smoke-confirmation.ps1" -EvidenceDir $validEvidenceDir -InstalledAppPath $validExe -ReleaseSigningManifestPath $fakeSigningManifestPath -ConfirmAppLaunched -ConfirmPromptEntryVisible -ConfirmModesVisible -ConfirmModeSequence -ConfirmTurnOffRetainsPresetDisabled -ConfirmLivePromptNonCaveman
}
Invoke-ExpectSuccess -Name "installed_smoke_manifest_helper_restores_confirmation_hash" -ExpectedOutput "installed_smoke_evidence_manifest_created=" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-installed-smoke-evidence.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir -EvidenceFiles "installed-smoke-note.txt"
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Invoke-ExpectFailure -Name "installed_smoke_manifest_helper_rejects_untrusted_signing_manifest" -ExpectedOutput "updater signature is not valid" -Action {
    Restore-FakeSigningManifest
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-caveman-installed-smoke-evidence.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir -EvidenceFiles "installed-smoke-note.txt" -ReleaseSigningManifestPath $fakeSigningManifestPath
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Invoke-ExpectSuccess -Name "installed_smoke_accepts_evidence_dir" -ExpectedOutput "installed_smoke_evidence_dir=" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir @installedConfirmations
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

$fakeReleaseBoundEvidenceManifest = @{
    installedAppPath = ([System.IO.Path]::GetFullPath($validExe))
    installedAppSha256 = (Get-FileHash -LiteralPath $validExe -Algorithm SHA256).Hash
    releaseSigningManifestPath = ([System.IO.Path]::GetFullPath($fakeSigningManifestPath))
    sourceInstallerPath = $fakeSigningManifest.nsisPath
    sourceInstallerSha256 = $fakeSigningManifest.nsisSha256
    releaseAppExePath = $fakeSigningManifest.appExePath
    releaseAppExeSha256 = $fakeSigningManifest.appExeSha256
    sourceSignaturePath = $fakeSigningManifest.signaturePath
    sourceSignatureSha256 = $fakeSigningManifest.signatureSha256
    evidenceFiles = @("installed-smoke-note.txt", "caveman-installed-smoke-confirmation.json")
    evidenceFileSha256 = @{
        "installed-smoke-note.txt" = (Get-FileHash -LiteralPath $validEvidenceFile -Algorithm SHA256).Hash
        "caveman-installed-smoke-confirmation.json" = (Get-FileHash -LiteralPath $validConfirmationFile -Algorithm SHA256).Hash
    }
}
$fakeReleaseBoundEvidenceManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $validEvidenceDir "caveman-installed-smoke-evidence.json") -Encoding UTF8

Invoke-ExpectFailure -Name "installed_smoke_rejects_untrusted_signing_manifest" -ExpectedOutput "updater signature is not valid" -Action {
    Restore-FakeSigningManifest
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir -ReleaseSigningManifestPath $fakeSigningManifestPath -ValidateEvidenceOnly
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

$mismatchedExe = Join-Path $validDir "CC Switch.exe"
Set-Content -LiteralPath $mismatchedExe -Encoding UTF8 -Value "fake installed exe that does not match release manifest."
$mismatchedEvidenceDir = Join-Path $runPath "mismatched-installed-smoke-evidence"
if (Test-Path -LiteralPath $mismatchedEvidenceDir) {
    Remove-Item -LiteralPath $mismatchedEvidenceDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $mismatchedEvidenceDir | Out-Null
Set-Content -LiteralPath (Join-Path $mismatchedEvidenceDir "installed-smoke-note.txt") -Encoding UTF8 -Value "Caveman mismatched installed-app smoke evidence placeholder."
$mismatchedConfirmation = @{
    schemaVersion = 1
    installedAppPath = ([System.IO.Path]::GetFullPath($mismatchedExe))
    releaseSigningManifestPath = ([System.IO.Path]::GetFullPath($fakeSigningManifestPath))
    confirmations = @{
        appLaunched = $true
        promptEntryVisible = $true
        modesVisible = $true
        modeSequence = $true
        turnOffRetainsPresetDisabled = $true
        livePromptNonCaveman = $true
    }
}
$mismatchedConfirmationPath = Join-Path $mismatchedEvidenceDir "caveman-installed-smoke-confirmation.json"
$mismatchedConfirmation | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $mismatchedConfirmationPath -Encoding UTF8
$mismatchedEvidenceManifest = @{
    installedAppPath = ([System.IO.Path]::GetFullPath($mismatchedExe))
    installedAppSha256 = (Get-FileHash -LiteralPath $mismatchedExe -Algorithm SHA256).Hash
    releaseSigningManifestPath = ([System.IO.Path]::GetFullPath($fakeSigningManifestPath))
    sourceInstallerPath = $fakeSigningManifest.nsisPath
    sourceInstallerSha256 = $fakeSigningManifest.nsisSha256
    releaseAppExePath = $fakeSigningManifest.appExePath
    releaseAppExeSha256 = $fakeSigningManifest.appExeSha256
    sourceSignaturePath = $fakeSigningManifest.signaturePath
    sourceSignatureSha256 = $fakeSigningManifest.signatureSha256
    evidenceFiles = @("installed-smoke-note.txt", "caveman-installed-smoke-confirmation.json")
    evidenceFileSha256 = @{
        "installed-smoke-note.txt" = (Get-FileHash -LiteralPath (Join-Path $mismatchedEvidenceDir "installed-smoke-note.txt") -Algorithm SHA256).Hash
        "caveman-installed-smoke-confirmation.json" = (Get-FileHash -LiteralPath $mismatchedConfirmationPath -Algorithm SHA256).Hash
    }
}
$mismatchedEvidenceManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $mismatchedEvidenceDir "caveman-installed-smoke-evidence.json") -Encoding UTF8

Invoke-ExpectFailure -Name "installed_smoke_rejects_mismatched_app_exe" -ExpectedOutput "installedAppSha256 does not match signing manifest appExeSha256" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $mismatchedExe -EvidenceDir $mismatchedEvidenceDir -ReleaseSigningManifestPath $fakeSigningManifestPath -ValidateEvidenceOnly
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

$skipBuildSigningManifestPath = Join-Path $runPath "skip-build-release-signing-manifest.json"
$skipBuildSigningManifest = @{
    skipBuild = $true
    buildStartedAt = (Get-Date).ToUniversalTime().ToString("o")
    msiPath = (Join-Path $fakeBundleRoot "msi\CC Switch_0.0.0_x64_en-US.msi")
    msiSha256 = (Get-FileHash -LiteralPath (Join-Path $fakeBundleRoot "msi\CC Switch_0.0.0_x64_en-US.msi") -Algorithm SHA256).Hash
    nsisPath = $fakeSigningManifest.nsisPath
    nsisSha256 = $fakeSigningManifest.nsisSha256
    appExePath = $fakeSigningManifest.appExePath
    appExeSha256 = $fakeSigningManifest.appExeSha256
    signaturePath = $fakeSigningManifest.signaturePath
    signatureSha256 = $fakeSigningManifest.signatureSha256
}
$skipBuildSigningManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $skipBuildSigningManifestPath -Encoding UTF8

Invoke-ExpectFailure -Name "installed_smoke_rejects_skipbuild_signing_manifest" -ExpectedOutput "requires a non-SkipBuild release signing manifest" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $validExe -EvidenceDir $validEvidenceDir -ReleaseSigningManifestPath $skipBuildSigningManifestPath -ValidateEvidenceOnly
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Invoke-ExpectFailure -Name "release_gate_rejects_skipbuild_signing_manifest" -ExpectedOutput "must come from a non-SkipBuild signing run" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-release-gate.ps1" -RequireSigning -ReleaseSigningManifestPath $skipBuildSigningManifestPath
}

$repoArtifactDir = Join-Path $runPath "repo-artifact"
$repoArtifactExe = Join-Path $repoArtifactDir "cc-switch.exe"
New-Item -ItemType Directory -Force -Path $repoArtifactDir | Out-Null
New-Item -ItemType File -Force -Path $repoArtifactExe | Out-Null

Invoke-ExpectFailure -Name "installed_repo_artifact_rejected" -ExpectedOutput "outside the source repo" -Action {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $repoArtifactExe -ValidatePathOnly
}

$fakeInstallerDir = Join-Path $fakePrograms "CC Switch Installer"
$fakeInstallerPath = Join-Path $fakeInstallerDir "CC Switch_0.0.0_x64-setup.exe"
New-Item -ItemType Directory -Force -Path $fakeInstallerDir | Out-Null
New-Item -ItemType File -Force -Path $fakeInstallerPath | Out-Null

Invoke-ExpectFailure -Name "installed_installer_rejected" -ExpectedOutput "not an installer" -Action {
    try {
        $env:LOCALAPPDATA = $fakeLocalAppData
        & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\verify-caveman-installed-smoke.ps1" -InstalledAppPath $fakeInstallerPath -ValidatePathOnly
    } finally {
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

Write-Host "Caveman release hardening checks passed."
Write-Host "release_hardening=passed"
exit 0
