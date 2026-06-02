param(
    [Parameter(Mandatory = $true)]
    [string] $InstalledAppPath,
    [switch] $ConfirmAppLaunched,
    [switch] $ConfirmPromptEntryVisible,
    [switch] $ConfirmModesVisible,
    [switch] $ConfirmModeSequence,
    [switch] $ConfirmTurnOffRetainsPresetDisabled,
    [switch] $ConfirmLivePromptNonCaveman,
    [string] $EvidenceDir,
    [string] $ReleaseSigningManifestPath,
    [switch] $ValidatePathOnly,
    [switch] $ValidateEvidenceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$resolvedAppPath = Resolve-Path -LiteralPath $InstalledAppPath
if (-not (Test-Path -LiteralPath $resolvedAppPath -PathType Leaf)) {
    throw ("Installed app path is not a file: {0}" -f $InstalledAppPath)
}

$leafName = Split-Path -Leaf $resolvedAppPath
$extension = [System.IO.Path]::GetExtension($leafName)
if ($extension -ne ".exe") {
    throw ("Installed app smoke expects the installed desktop executable, got {0}" -f $leafName)
}
if ($leafName -match "(?i)setup|installer") {
    throw ("Installed app smoke expects the installed app executable, not an installer: {0}" -f $leafName)
}
if ($leafName -notin @("cc-switch.exe", "CC Switch.exe")) {
    throw ("Installed app smoke expects the installed CC Switch executable, got {0}" -f $leafName)
}

$resolvedAppFullName = $resolvedAppPath.ProviderPath
$repoRootFullName = $repoRoot.ProviderPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

function Test-PathInsideDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($Path)
    $normalizedDirectory = [System.IO.Path]::GetFullPath($Directory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $directoryPrefix = $normalizedDirectory + [System.IO.Path]::DirectorySeparatorChar
    return $normalizedPath.StartsWith($directoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

if (Test-PathInsideDirectory -Path $resolvedAppFullName -Directory $repoRootFullName) {
    throw ("Installed app smoke expects an installed desktop executable outside the source repo, got build/workspace artifact: {0}" -f $resolvedAppFullName)
}

$installRoots = @()
foreach ($name in @("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA")) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        $root = [System.IO.Path]::GetFullPath($value).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if ($name -eq "LOCALAPPDATA") {
            $root = Join-Path $root "Programs"
        }
        $installRoots += $root
    }
}

$isUnderInstallRoot = $false
foreach ($root in $installRoots) {
    if (Test-PathInsideDirectory -Path $resolvedAppFullName -Directory $root) {
        $isUnderInstallRoot = $true
        break
    }
}

if (-not $isUnderInstallRoot) {
    throw ("Installed app smoke expects an executable under a standard installed-app directory ({0}), got: {1}" -f ($installRoots -join "; "), $resolvedAppFullName)
}

if ($ValidatePathOnly) {
    Write-Host ("installed_app_path_validated={0}" -f $resolvedAppFullName)
    return
}

function Assert-InstalledSmokeEvidence {
    param(
        [string] $EvidenceDirectory,
        [Parameter(Mandatory = $true)]
        [string] $ExpectedAppPath,
        [string] $ExpectedReleaseSigningManifestPath
    )

    if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
        throw "-EvidenceDir is required for installed-app smoke confirmations"
    }

    $resolvedEvidenceDirectory = Resolve-Path -LiteralPath $EvidenceDirectory
    if (-not (Test-Path -LiteralPath $resolvedEvidenceDirectory -PathType Container)) {
        throw ("Installed-app smoke evidence directory is not a directory: {0}" -f $EvidenceDirectory)
    }

    $directoryFiles = @(Get-ChildItem -LiteralPath $resolvedEvidenceDirectory -File)
    if ($directoryFiles.Count -lt 1) {
        throw ("Installed-app smoke evidence directory must contain at least one file: {0}" -f $resolvedEvidenceDirectory)
    }

    $manifestPath = Join-Path $resolvedEvidenceDirectory "caveman-installed-smoke-evidence.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw ("Installed-app smoke evidence manifest is required: {0}" -f $manifestPath)
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifestProperties = @($manifest.PSObject.Properties.Name)
    foreach ($requiredProperty in @("installedAppPath", "installedAppSha256", "evidenceFiles", "evidenceFileSha256")) {
        if ($manifestProperties -notcontains $requiredProperty) {
            throw ("Installed-app smoke evidence manifest is missing '{0}': {1}" -f $requiredProperty, $manifestPath)
        }
    }

    $expectedAppFullPath = [System.IO.Path]::GetFullPath($ExpectedAppPath)
    $manifestAppFullPath = [System.IO.Path]::GetFullPath([string] $manifest.installedAppPath)
    if (-not [string]::Equals($manifestAppFullPath, $expectedAppFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Installed-app smoke evidence manifest installedAppPath does not match: {0}" -f $manifestPath)
    }

    $expectedHash = (Get-FileHash -LiteralPath $expectedAppFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestHash = ([string] $manifest.installedAppSha256).ToLowerInvariant()
    if (-not [string]::Equals($manifestHash, $expectedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Installed-app smoke evidence manifest installedAppSha256 does not match: {0}" -f $manifestPath)
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedReleaseSigningManifestPath)) {
        $resolvedReleaseManifest = Resolve-Path -LiteralPath $ExpectedReleaseSigningManifestPath
        $releaseManifest = Get-Content -LiteralPath $resolvedReleaseManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        $releaseManifestProperties = @($releaseManifest.PSObject.Properties.Name)
        foreach ($requiredProperty in @("skipBuild", "nsisPath", "nsisSha256", "appExePath", "appExeSha256", "signaturePath", "signatureSha256")) {
            if ($releaseManifestProperties -notcontains $requiredProperty) {
                throw ("Release signing manifest is missing '{0}': {1}" -f $requiredProperty, $resolvedReleaseManifest)
            }
        }
        if ([bool] $releaseManifest.skipBuild) {
            throw ("Installed-app smoke requires a non-SkipBuild release signing manifest: {0}" -f $resolvedReleaseManifest)
        }

        foreach ($requiredProperty in @("releaseSigningManifestPath", "sourceInstallerPath", "sourceInstallerSha256", "releaseAppExePath", "releaseAppExeSha256", "sourceSignaturePath", "sourceSignatureSha256")) {
            if ($manifestProperties -notcontains $requiredProperty) {
                throw ("Installed-app smoke evidence manifest is missing '{0}': {1}" -f $requiredProperty, $manifestPath)
            }
        }

        $manifestReleasePath = [System.IO.Path]::GetFullPath([string] $manifest.releaseSigningManifestPath)
        $expectedReleasePath = [System.IO.Path]::GetFullPath($resolvedReleaseManifest.ProviderPath)
        if (-not [string]::Equals($manifestReleasePath, $expectedReleasePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed-app smoke evidence manifest releaseSigningManifestPath does not match: {0}" -f $manifestPath)
        }

        $releaseNsisPath = [System.IO.Path]::GetFullPath([string] $releaseManifest.nsisPath)
        $manifestNsisPath = [System.IO.Path]::GetFullPath([string] $manifest.sourceInstallerPath)
        if (-not [string]::Equals($manifestNsisPath, $releaseNsisPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed-app smoke evidence manifest sourceInstallerPath does not match signing manifest: {0}" -f $manifestPath)
        }
        if (-not [string]::Equals(([string] $manifest.sourceInstallerSha256), ([string] $releaseManifest.nsisSha256), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed-app smoke evidence manifest sourceInstallerSha256 does not match signing manifest: {0}" -f $manifestPath)
        }

        $releaseAppExePath = [System.IO.Path]::GetFullPath([string] $releaseManifest.appExePath)
        $manifestReleaseAppExePath = [System.IO.Path]::GetFullPath([string] $manifest.releaseAppExePath)
        if (-not [string]::Equals($manifestReleaseAppExePath, $releaseAppExePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed-app smoke evidence manifest releaseAppExePath does not match signing manifest: {0}" -f $manifestPath)
        }
        if (-not [string]::Equals(([string] $manifest.releaseAppExeSha256), ([string] $releaseManifest.appExeSha256), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed-app smoke evidence manifest releaseAppExeSha256 does not match signing manifest: {0}" -f $manifestPath)
        }
        if (-not [string]::Equals($manifestHash, ([string] $releaseManifest.appExeSha256), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed-app smoke evidence manifest installedAppSha256 does not match signing manifest appExeSha256: {0}" -f $manifestPath)
        }

        $releaseSignaturePath = [System.IO.Path]::GetFullPath([string] $releaseManifest.signaturePath)
        $manifestSignaturePath = [System.IO.Path]::GetFullPath([string] $manifest.sourceSignaturePath)
        if (-not [string]::Equals($manifestSignaturePath, $releaseSignaturePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed-app smoke evidence manifest sourceSignaturePath does not match signing manifest: {0}" -f $manifestPath)
        }
        if (-not [string]::Equals(([string] $manifest.sourceSignatureSha256), ([string] $releaseManifest.signatureSha256), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed-app smoke evidence manifest sourceSignatureSha256 does not match signing manifest: {0}" -f $manifestPath)
        }

        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\verify-caveman-release-signing.ps1") `
            -ValidateManifestOnly `
            -ValidateManifestPath $resolvedReleaseManifest.ProviderPath
        if ($LASTEXITCODE -ne 0) {
            throw ("Release signing manifest validation failed with exit code {0}: {1}" -f $LASTEXITCODE, $resolvedReleaseManifest.ProviderPath)
        }
    }

    $evidenceFiles = @($manifest.evidenceFiles)
    if ($evidenceFiles.Count -lt 1) {
        throw ("Installed-app smoke evidence manifest must list at least one evidence file: {0}" -f $manifestPath)
    }
    if ($evidenceFiles -notcontains "caveman-installed-smoke-confirmation.json") {
        throw ("Installed-app smoke evidence manifest must include caveman-installed-smoke-confirmation.json: {0}" -f $manifestPath)
    }

    foreach ($evidenceFile in $evidenceFiles) {
        $relativePath = [string] $evidenceFile
        if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath)) {
            throw ("Installed-app smoke evidence file paths must be non-empty relative paths: {0}" -f $manifestPath)
        }

        $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $resolvedEvidenceDirectory $relativePath))
        if (-not (Test-PathInsideDirectory -Path $candidatePath -Directory $resolvedEvidenceDirectory)) {
            throw ("Installed-app smoke evidence file escapes the evidence directory: {0}" -f $relativePath)
        }
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            throw ("Installed-app smoke evidence file is missing: {0}" -f $candidatePath)
        }
        if ((Get-Item -LiteralPath $candidatePath).Length -lt 1) {
            throw ("Installed-app smoke evidence file must be non-empty: {0}" -f $candidatePath)
        }

        $hashProperty = $manifest.evidenceFileSha256.PSObject.Properties[$relativePath]
        if ($null -eq $hashProperty -or [string]::IsNullOrWhiteSpace([string] $hashProperty.Value)) {
            throw ("Installed-app smoke evidence manifest is missing SHA256 for evidence file '{0}': {1}" -f $relativePath, $manifestPath)
        }
        $actualEvidenceHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
        if (-not [string]::Equals($actualEvidenceHash, ([string] $hashProperty.Value), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed-app smoke evidence file SHA256 does not match manifest for '{0}': {1}" -f $relativePath, $manifestPath)
        }
    }

    $confirmationPath = Join-Path $resolvedEvidenceDirectory "caveman-installed-smoke-confirmation.json"
    $confirmation = Get-Content -LiteralPath $confirmationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $confirmationProperties = @($confirmation.PSObject.Properties.Name)
    foreach ($requiredProperty in @("schemaVersion", "installedAppPath", "releaseSigningManifestPath", "confirmations")) {
        if ($confirmationProperties -notcontains $requiredProperty) {
            throw ("Installed smoke confirmation note is missing '{0}': {1}" -f $requiredProperty, $confirmationPath)
        }
    }
    $confirmationAppPath = [System.IO.Path]::GetFullPath([string] $confirmation.installedAppPath)
    if (-not [string]::Equals($confirmationAppPath, $expectedAppFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Installed smoke confirmation note installedAppPath does not match: {0}" -f $confirmationPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedReleaseSigningManifestPath)) {
        $confirmationReleasePath = [System.IO.Path]::GetFullPath([string] $confirmation.releaseSigningManifestPath)
        $expectedReleasePath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ExpectedReleaseSigningManifestPath).ProviderPath)
        if (-not [string]::Equals($confirmationReleasePath, $expectedReleasePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Installed smoke confirmation note releaseSigningManifestPath does not match: {0}" -f $confirmationPath)
        }
    }
    foreach ($requiredConfirmation in @("appLaunched", "promptEntryVisible", "modesVisible", "modeSequence", "turnOffRetainsPresetDisabled", "livePromptNonCaveman")) {
        $confirmationValue = $confirmation.confirmations.PSObject.Properties[$requiredConfirmation]
        if ($null -eq $confirmationValue -or -not [bool] $confirmationValue.Value) {
            throw ("Installed smoke confirmation note is missing confirmation '{0}': {1}" -f $requiredConfirmation, $confirmationPath)
        }
    }

    return $resolvedEvidenceDirectory
}

if ($ValidateEvidenceOnly) {
    $resolvedEvidenceDir = Assert-InstalledSmokeEvidence -EvidenceDirectory $EvidenceDir -ExpectedAppPath $resolvedAppFullName -ExpectedReleaseSigningManifestPath $ReleaseSigningManifestPath
    Write-Host ("installed_smoke_evidence_validated={0}" -f $resolvedEvidenceDir)
    return
}

$confirmationSwitches = @(
    @{ Name = "ConfirmAppLaunched"; Value = [bool] $ConfirmAppLaunched },
    @{ Name = "ConfirmPromptEntryVisible"; Value = [bool] $ConfirmPromptEntryVisible },
    @{ Name = "ConfirmModesVisible"; Value = [bool] $ConfirmModesVisible },
    @{ Name = "ConfirmModeSequence"; Value = [bool] $ConfirmModeSequence },
    @{ Name = "ConfirmTurnOffRetainsPresetDisabled"; Value = [bool] $ConfirmTurnOffRetainsPresetDisabled },
    @{ Name = "ConfirmLivePromptNonCaveman"; Value = [bool] $ConfirmLivePromptNonCaveman }
)

$missing = @()
foreach ($confirmation in $confirmationSwitches) {
    if (-not $confirmation.Value) {
        $missing += ("-{0}" -f $confirmation.Name)
    }
}

if ($missing.Count -gt 0) {
    throw @"
Installed Caveman smoke requires manual confirmation.

Run the installed desktop app from:
$resolvedAppPath

Confirm:
1. Launch the installed app executable.
2. Open OpenClaw -> Prompts.
3. Lite, Full, Ultra, and Turn off Caveman are visible.
4. Select Lite, Full, Ultra in sequence; each mode becomes active.
5. Turn off Caveman; the Caveman preset remains present and disabled.
6. The live prompt returns to non-Caveman state.

Rerun this script with these confirmation switches only after the above installed-app smoke is completed:
$($missing -join " ")
"@
}

$resolvedEvidenceDir = Assert-InstalledSmokeEvidence -EvidenceDirectory $EvidenceDir -ExpectedAppPath $resolvedAppFullName -ExpectedReleaseSigningManifestPath $ReleaseSigningManifestPath

Write-Host "Caveman installed-app smoke manually confirmed."
Write-Host ("installed_app={0}" -f $resolvedAppPath)
Write-Host ("installed_smoke_evidence_dir={0}" -f $resolvedEvidenceDir)
Write-Host "installed_smoke=app_prompt_modes_off_live_prompt_confirmed"
