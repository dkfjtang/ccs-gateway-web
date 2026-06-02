param(
    [Parameter(Mandatory = $true)]
    [string] $EvidenceDir,
    [Parameter(Mandatory = $true)]
    [string] $InstalledAppPath,
    [Parameter(Mandatory = $true)]
    [string] $ReleaseSigningManifestPath,
    [switch] $ConfirmAppLaunched,
    [switch] $ConfirmPromptEntryVisible,
    [switch] $ConfirmModesVisible,
    [switch] $ConfirmModeSequence,
    [switch] $ConfirmTurnOffRetainsPresetDisabled,
    [switch] $ConfirmLivePromptNonCaveman,
    [string] $OutputFileName = "caveman-installed-smoke-confirmation.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedEvidenceDir = Resolve-Path -LiteralPath $EvidenceDir
if (-not (Test-Path -LiteralPath $resolvedEvidenceDir -PathType Container)) {
    throw ("Evidence directory is not a directory: {0}" -f $EvidenceDir)
}

if ([string]::IsNullOrWhiteSpace($OutputFileName) -or [System.IO.Path]::IsPathRooted($OutputFileName) -or $OutputFileName -match "[\\/]") {
    throw ("-OutputFileName must be a file name under the evidence directory: {0}" -f $OutputFileName)
}

$confirmationSwitches = @(
    @{ Name = "appLaunched"; Switch = "-ConfirmAppLaunched"; Value = [bool] $ConfirmAppLaunched },
    @{ Name = "promptEntryVisible"; Switch = "-ConfirmPromptEntryVisible"; Value = [bool] $ConfirmPromptEntryVisible },
    @{ Name = "modesVisible"; Switch = "-ConfirmModesVisible"; Value = [bool] $ConfirmModesVisible },
    @{ Name = "modeSequence"; Switch = "-ConfirmModeSequence"; Value = [bool] $ConfirmModeSequence },
    @{ Name = "turnOffRetainsPresetDisabled"; Switch = "-ConfirmTurnOffRetainsPresetDisabled"; Value = [bool] $ConfirmTurnOffRetainsPresetDisabled },
    @{ Name = "livePromptNonCaveman"; Switch = "-ConfirmLivePromptNonCaveman"; Value = [bool] $ConfirmLivePromptNonCaveman }
)

$missing = @()
foreach ($confirmation in $confirmationSwitches) {
    if (-not $confirmation.Value) {
        $missing += $confirmation.Switch
    }
}
if ($missing.Count -gt 0) {
    throw ("Installed smoke confirmation note requires all confirmation switches: {0}" -f ($missing -join " "))
}

$confirmationMap = [ordered] @{}
foreach ($confirmation in $confirmationSwitches) {
    $confirmationMap[$confirmation.Name] = $confirmation.Value
}

$manifest = [ordered] @{
    schemaVersion = 1
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    installedAppPath = $InstalledAppPath
    releaseSigningManifestPath = $ReleaseSigningManifestPath
    confirmations = $confirmationMap
}

$outputPath = Join-Path $resolvedEvidenceDir $OutputFileName
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outputPath -Encoding UTF8

Write-Host ("installed_smoke_confirmation={0}" -f $outputPath)
Write-Host "installed_smoke_confirmation=created"
