param(
    [Parameter(Mandatory = $true)]
    [string] $InstalledAppPath,
    [Parameter(Mandatory = $true)]
    [string] $EvidenceDir,
    [Parameter(Mandatory = $true)]
    [string[]] $EvidenceFiles,
    [string] $ReleaseSigningManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$resolvedAppPath = Resolve-Path -LiteralPath $InstalledAppPath
$resolvedEvidenceDir = Resolve-Path -LiteralPath $EvidenceDir

if (-not (Test-Path -LiteralPath $resolvedEvidenceDir -PathType Container)) {
    throw ("Evidence directory is not a directory: {0}" -f $EvidenceDir)
}

$manifest = @{
    installedAppPath = $resolvedAppPath.ProviderPath
    installedAppSha256 = (Get-FileHash -LiteralPath $resolvedAppPath.ProviderPath -Algorithm SHA256).Hash
    evidenceFiles = @()
    evidenceFileSha256 = [ordered] @{}
}

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

foreach ($evidenceFile in $EvidenceFiles) {
    if ([string]::IsNullOrWhiteSpace($evidenceFile) -or [System.IO.Path]::IsPathRooted($evidenceFile)) {
        throw ("Evidence file must be a non-empty relative path under the evidence directory: {0}" -f $evidenceFile)
    }

    $evidencePath = [System.IO.Path]::GetFullPath((Join-Path $resolvedEvidenceDir $evidenceFile))
    if (-not (Test-PathInsideDirectory -Path $evidencePath -Directory $resolvedEvidenceDir.ProviderPath)) {
        throw ("Evidence file escapes the evidence directory: {0}" -f $evidenceFile)
    }
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        throw ("Evidence file is missing: {0}" -f $evidencePath)
    }
    if ((Get-Item -LiteralPath $evidencePath).Length -lt 1) {
        throw ("Evidence file must be non-empty: {0}" -f $evidencePath)
    }

    $manifest.evidenceFiles += $evidenceFile
    $manifest.evidenceFileSha256[$evidenceFile] = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash
}

$confirmationFileName = "caveman-installed-smoke-confirmation.json"
if ($manifest.evidenceFiles -notcontains $confirmationFileName) {
    $confirmationPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedEvidenceDir $confirmationFileName))
    if (-not (Test-Path -LiteralPath $confirmationPath -PathType Leaf)) {
        throw ("Installed smoke confirmation note is required before generating evidence manifest: {0}" -f $confirmationPath)
    }
    if ((Get-Item -LiteralPath $confirmationPath).Length -lt 1) {
        throw ("Installed smoke confirmation note must be non-empty: {0}" -f $confirmationPath)
    }
    $manifest.evidenceFiles += $confirmationFileName
    $manifest.evidenceFileSha256[$confirmationFileName] = (Get-FileHash -LiteralPath $confirmationPath -Algorithm SHA256).Hash
}

if ($manifest.evidenceFiles.Count -lt 1) {
    throw "At least one evidence file is required"
}

if (-not [string]::IsNullOrWhiteSpace($ReleaseSigningManifestPath)) {
    $resolvedReleaseSigningManifestPath = Resolve-Path -LiteralPath $ReleaseSigningManifestPath
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\verify-caveman-release-signing.ps1") `
        -ValidateManifestOnly `
        -ValidateManifestPath $resolvedReleaseSigningManifestPath.ProviderPath
    if ($LASTEXITCODE -ne 0) {
        throw ("Release signing manifest validation failed with exit code {0}: {1}" -f $LASTEXITCODE, $resolvedReleaseSigningManifestPath.ProviderPath)
    }

    $releaseManifest = Get-Content -LiteralPath $resolvedReleaseSigningManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $releaseManifestProperties = @($releaseManifest.PSObject.Properties.Name)
    foreach ($requiredProperty in @("skipBuild", "nsisPath", "nsisSha256", "appExePath", "appExeSha256", "signaturePath", "signatureSha256")) {
        if ($releaseManifestProperties -notcontains $requiredProperty) {
            throw ("Release signing manifest is missing '{0}': {1}" -f $requiredProperty, $resolvedReleaseSigningManifestPath)
        }
    }
    if ([bool] $releaseManifest.skipBuild) {
        throw ("Installed-smoke evidence requires a non-SkipBuild release signing manifest: {0}" -f $resolvedReleaseSigningManifestPath)
    }

    $manifest.releaseSigningManifestPath = $resolvedReleaseSigningManifestPath.ProviderPath
    $manifest.sourceInstallerPath = [string] $releaseManifest.nsisPath
    $manifest.sourceInstallerSha256 = [string] $releaseManifest.nsisSha256
    $manifest.releaseAppExePath = [string] $releaseManifest.appExePath
    $manifest.releaseAppExeSha256 = [string] $releaseManifest.appExeSha256
    $manifest.sourceSignaturePath = [string] $releaseManifest.signaturePath
    $manifest.sourceSignatureSha256 = [string] $releaseManifest.signatureSha256
}

$manifestPath = Join-Path $resolvedEvidenceDir "caveman-installed-smoke-evidence.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$validateArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $repoRoot "scripts\verify-caveman-installed-smoke.ps1"),
    "-InstalledAppPath",
    $resolvedAppPath.ProviderPath,
    "-EvidenceDir",
    $resolvedEvidenceDir.ProviderPath,
    "-ValidateEvidenceOnly"
)
if (-not [string]::IsNullOrWhiteSpace($ReleaseSigningManifestPath)) {
    $validateArgs += @("-ReleaseSigningManifestPath", (Resolve-Path -LiteralPath $ReleaseSigningManifestPath).ProviderPath)
}

& powershell @validateArgs
if ($LASTEXITCODE -ne 0) {
    throw ("Generated installed-smoke evidence manifest failed validation with exit code {0}" -f $LASTEXITCODE)
}

Write-Host ("installed_smoke_evidence_manifest_created={0}" -f $manifestPath)
