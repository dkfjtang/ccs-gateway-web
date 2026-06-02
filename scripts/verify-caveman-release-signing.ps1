param(
    [string] $RunDir = ".run\caveman-release-signing",
    [string] $BundleRoot,
    [string] $AppExePath,
    [string] $ValidateManifestPath,
    [switch] $SkipBuild,
    [switch] $ValidateManifestOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$runPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $RunDir))
$configPath = Join-Path $runPath "tauri-npm-build-config.json"
$logPath = Join-Path $runPath "tauri-build-signed.log"
$outputManifestPath = Join-Path $runPath "caveman-release-signing-manifest.json"
$buildStartedAt = Get-Date

New-Item -ItemType Directory -Force -Path $runPath | Out-Null

function Get-UpdaterPublicKey {
    $tauriConfigPath = Join-Path $repoRoot "src-tauri\tauri.conf.json"
    $tauriConfig = Get-Content -LiteralPath $tauriConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pubkey = [string] $tauriConfig.plugins.updater.pubkey
    if ([string]::IsNullOrWhiteSpace($pubkey)) {
        throw ("Updater public key is missing from {0}" -f $tauriConfigPath)
    }
    return $pubkey
}

function Assert-ReleaseSigningManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Release signing manifest is required: {0}" -f $Path)
    }

    $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifestProperties = @($manifest.PSObject.Properties.Name)
    foreach ($requiredProperty in @("skipBuild", "buildStartedAt", "msiPath", "msiSha256", "nsisPath", "nsisSha256", "appExePath", "appExeSha256", "signaturePath", "signatureSha256")) {
        if ($manifestProperties -notcontains $requiredProperty) {
            throw ("Release signing manifest is missing '{0}': {1}" -f $requiredProperty, $Path)
        }
    }
    if ([bool] $manifest.skipBuild) {
        throw ("Release signing manifest must come from a non-SkipBuild signing run: {0}" -f $Path)
    }

    foreach ($artifact in @(
        @{ Path = [string] $manifest.msiPath; Hash = [string] $manifest.msiSha256; Name = "msi" },
        @{ Path = [string] $manifest.nsisPath; Hash = [string] $manifest.nsisSha256; Name = "nsis" },
        @{ Path = [string] $manifest.appExePath; Hash = [string] $manifest.appExeSha256; Name = "appExe" },
        @{ Path = [string] $manifest.signaturePath; Hash = [string] $manifest.signatureSha256; Name = "signature" }
    )) {
        if ([string]::IsNullOrWhiteSpace($artifact.Path) -or -not (Test-Path -LiteralPath $artifact.Path -PathType Leaf)) {
            throw ("Release signing manifest {0} artifact is missing: {1}" -f $artifact.Name, $artifact.Path)
        }
        $actualHash = (Get-FileHash -LiteralPath $artifact.Path -Algorithm SHA256).Hash
        if (-not [string]::Equals($actualHash, $artifact.Hash, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Release signing manifest {0} artifact SHA256 does not match: {1}" -f $artifact.Name, $artifact.Path)
        }
    }

    $expectedSignaturePath = ("{0}.sig" -f ([System.IO.Path]::GetFullPath([string] $manifest.nsisPath)))
    $actualSignaturePath = [System.IO.Path]::GetFullPath([string] $manifest.signaturePath)
    if (-not [string]::Equals($actualSignaturePath, $expectedSignaturePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Release signing manifest signaturePath must match the selected NSIS setup signature: {0}" -f $Path)
    }

    Push-Location -LiteralPath (Join-Path $repoRoot "src-tauri")
    try {
        & cargo run --quiet --bin verify_updater_signature -- `
            ([string] $manifest.nsisPath) `
            ([string] $manifest.signaturePath) `
            (Get-UpdaterPublicKey)
        if ($LASTEXITCODE -ne 0) {
            throw ("Release signing manifest updater signature is not valid: {0}" -f $Path)
        }
    } finally {
        Pop-Location
    }

    return $manifest
}

if ($ValidateManifestOnly) {
    if ([string]::IsNullOrWhiteSpace($ValidateManifestPath)) {
        $ValidateManifestPath = $outputManifestPath
    }
    $resolvedManifestPath = Resolve-Path -LiteralPath $ValidateManifestPath
    Assert-ReleaseSigningManifest -Path $resolvedManifestPath.ProviderPath | Out-Null
    Write-Host ("release_signing_manifest={0}" -f $resolvedManifestPath.ProviderPath)
    Write-Host "release_signing=signed_manifest_verified"
    return
}

function Assert-EnvPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw ("Missing required release signing environment variable: {0}" -f $Name)
    }
}

Assert-EnvPresent -Name "TAURI_SIGNING_PRIVATE_KEY"

$passphrase = [Environment]::GetEnvironmentVariable("TAURI_SIGNING_PRIVATE_KEY_PASSWORD")
if ([string]::IsNullOrWhiteSpace($passphrase)) {
    Write-Warning "TAURI_SIGNING_PRIVATE_KEY_PASSWORD is not set. Continuing because unencrypted keys are valid, but release hosts should document this choice."
}

$tauriConfig = @{
    build = @{
        beforeBuildCommand = "npm run build:renderer"
    }
} | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $configPath -Value $tauriConfig -Encoding UTF8

if (-not $SkipBuild) {
    $buildStartedAt = Get-Date
    Push-Location -LiteralPath $repoRoot
    try {
        $output = & npm.cmd exec -- tauri build --config $configPath 2>&1
        $exitCode = $LASTEXITCODE
        $output | Set-Content -LiteralPath $logPath -Encoding UTF8
        if ($exitCode -ne 0) {
            throw ("Signed Tauri build failed with exit code {0}; see {1}" -f $exitCode, $logPath)
        }
    } finally {
        Pop-Location
    }
}

if ([string]::IsNullOrWhiteSpace($BundleRoot)) {
    $bundleRoot = Join-Path $repoRoot "src-tauri\target\release\bundle"
} elseif ([System.IO.Path]::IsPathRooted($BundleRoot)) {
    $bundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
} else {
    $bundleRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot.ProviderPath $BundleRoot))
}
$msi = Get-ChildItem -LiteralPath $bundleRoot -Recurse -File -Filter "*.msi" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$nsis = Get-ChildItem -LiteralPath $bundleRoot -Recurse -File -Filter "*setup.exe" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $msi) {
    throw "Signed release gate failed: MSI artifact not found"
}
if (-not $nsis) {
    throw "Signed release gate failed: NSIS setup artifact not found"
}

$resolvedAppExe = $null
if (-not [string]::IsNullOrWhiteSpace($AppExePath)) {
    $resolvedAppExe = Get-Item -LiteralPath $AppExePath -ErrorAction SilentlyContinue
} else {
    $releaseRoot = Split-Path -Parent $bundleRoot
    $appExeCandidates = @(
        (Join-Path $releaseRoot "cc-switch.exe"),
        (Join-Path $releaseRoot "CC Switch.exe")
    )
    foreach ($candidate in $appExeCandidates) {
        $resolvedAppExe = Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue
        if ($resolvedAppExe) {
            break
        }
    }
}
if (-not $resolvedAppExe) {
    throw "Signed release gate failed: desktop app executable artifact not found"
}

$expectedSigPath = ("{0}.sig" -f $nsis.FullName)
$sig = Get-Item -LiteralPath $expectedSigPath -ErrorAction SilentlyContinue
if (-not $sig) {
    throw ("Signed release gate failed: updater signature artifact not found for NSIS setup: {0}" -f $expectedSigPath)
}

if (-not $SkipBuild) {
    foreach ($artifact in @($msi, $nsis, $sig, $resolvedAppExe)) {
        if ($artifact.LastWriteTime -lt $buildStartedAt) {
            throw ("Signed release gate failed: stale artifact predates this build: {0}" -f $artifact.FullName)
        }
    }
} else {
    Write-Warning "-SkipBuild skips artifact freshness validation and is intended only for local gate-shape checks, not final release approval."
}

if ($SkipBuild) {
    Write-Host "Caveman release signing gate shape check passed."
    Write-Host "release_signing=local_shape_only"
} else {
    Write-Host "Caveman release signing gate passed."
    Write-Host "release_signing=signed_artifacts_verified"
}

$manifest = @{
    skipBuild = [bool] $SkipBuild
    buildStartedAt = $buildStartedAt.ToUniversalTime().ToString("o")
    msiPath = $msi.FullName
    msiSha256 = (Get-FileHash -LiteralPath $msi.FullName -Algorithm SHA256).Hash
    nsisPath = $nsis.FullName
    nsisSha256 = (Get-FileHash -LiteralPath $nsis.FullName -Algorithm SHA256).Hash
    appExePath = $resolvedAppExe.FullName
    appExeSha256 = (Get-FileHash -LiteralPath $resolvedAppExe.FullName -Algorithm SHA256).Hash
    signaturePath = $sig.FullName
    signatureSha256 = (Get-FileHash -LiteralPath $sig.FullName -Algorithm SHA256).Hash
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outputManifestPath -Encoding UTF8
if (-not $SkipBuild) {
    Assert-ReleaseSigningManifest -Path $outputManifestPath | Out-Null
}

Write-Host ("msi={0}" -f $msi.FullName)
Write-Host ("nsis={0}" -f $nsis.FullName)
Write-Host ("app_exe={0}" -f $resolvedAppExe.FullName)
Write-Host ("signature={0}" -f $sig.FullName)
Write-Host ("signing_manifest={0}" -f $outputManifestPath)
