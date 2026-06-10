Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [AllowNull()]
        [string] $Actual,
        [Parameter(Mandatory = $true)]
        [string] $Expected
    )

    if ($Actual -ne $Expected) {
        throw ("{0}: expected '{1}', got '{2}'" -f $Name, $Expected, $Actual)
    }
    Write-Host ("ok: {0}" -f $Name)
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Content,
        [Parameter(Mandatory = $true)]
        [string] $Needle
    )

    if (-not $Content.Contains($Needle)) {
        throw ("{0}: missing '{1}'" -f $Name, $Needle)
    }
    Write-Host ("ok: {0}" -f $Name)
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Content,
        [Parameter(Mandatory = $true)]
        [string] $Needle
    )

    if ($Content.Contains($Needle)) {
        throw ("{0}: must not contain '{1}'" -f $Name, $Needle)
    }
    Write-Host ("ok: {0}" -f $Name)
}

function Get-JsonVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return [string] $json.version
}

function Get-NodePackageLockVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $script = @'
const fs = require("node:fs");
const path = process.argv[2];
const data = JSON.parse(fs.readFileSync(path, "utf8"));
const root = data.packages && data.packages[""];
if (!data.version || !root || !root.version) {
  throw new Error("missing package-lock version");
}
process.stdout.write(`${data.version}\n${root.version}`);
'@
    $scriptPath = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".cjs")
    try {
        Set-Content -LiteralPath $scriptPath -Encoding UTF8 -Value $script
        $result = & node $scriptPath $Path
        if ($LASTEXITCODE -ne 0) {
            throw "failed to read package-lock.json version with node"
        }
    }
    finally {
        if (Test-Path -LiteralPath $scriptPath) {
            Remove-Item -LiteralPath $scriptPath -Force
        }
    }

    return @($result[0], $result[1])
}

function Get-RepoRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $pathFull = (Resolve-Path -LiteralPath $Path).Path
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if ($pathFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $pathFull.Substring($prefix.Length)
    }
    return $pathFull
}

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
Set-Location -LiteralPath $repoRoot

$expectedVersion = "3.16.2-ccs-gateway.1"
$expectedOfficialArchiveVersion = "3.16.2"
$expectedOfficialArchiveSha256 = "9589AD28CE3F9D44F1A6C57A45AB6212CE17FB5E6B0A61CEAE9DA00D6A897431"

Write-Host "==> remote policy"
$upstreamUrl = (git remote get-url upstream).Trim()
Assert-Equal "upstream fetch url" $upstreamUrl "https://github.com/farion1231/cc-switch.git"
$upstreamPushUrl = (git remote get-url --push upstream).Trim()
Assert-Equal "upstream push url disabled" $upstreamPushUrl "DISABLED"

$referenceUrl = (git remote get-url ccs-web-reference).Trim()
Assert-Equal "ccs-web reference fetch url" $referenceUrl "https://github.com/cp-yu/cc-switch-web.git"
$referencePushUrl = (git remote get-url --push ccs-web-reference).Trim()
Assert-Equal "ccs-web reference push url disabled" $referencePushUrl "DISABLED"

Write-Host "==> version policy"
Assert-Equal "package.json version" (Get-JsonVersion (Join-Path $repoRoot "package.json")) $expectedVersion
$packageLockVersions = Get-NodePackageLockVersion (Join-Path $repoRoot "package-lock.json")
Assert-Equal "package-lock.json root version" $packageLockVersions[0] $expectedVersion
Assert-Equal "package-lock.json package version" $packageLockVersions[1] $expectedVersion
Assert-Equal "tauri.conf.json version" (Get-JsonVersion (Join-Path $repoRoot "src-tauri\tauri.conf.json")) $expectedVersion
$tauriConfig = Get-Content -LiteralPath (Join-Path $repoRoot "src-tauri\tauri.conf.json") -Raw -Encoding UTF8
Assert-Contains "fork updater endpoint" $tauriConfig "https://github.com/dkfjtang/ccs-gateway-web/releases/latest/download/latest.json"
Assert-NotContains "official updater endpoint not used for fork builds" $tauriConfig "https://github.com/farion1231/cc-switch/releases/latest/download/latest.json"
$runtimeRoots = @("src", "src-tauri\src", "crates")
$runtimeExtensions = @(".rs", ".ts", ".tsx")
foreach ($runtimeRoot in $runtimeRoots) {
    $runtimeRootPath = Join-Path $repoRoot $runtimeRoot
    $runtimeFiles = Get-ChildItem -LiteralPath $runtimeRootPath -Recurse -File |
        Where-Object {
            $runtimeExtensions -contains $_.Extension -and
            $_.FullName -notmatch '\\(target|node_modules|dist)\\'
        }
    foreach ($runtimeFile in $runtimeFiles) {
        $runtimeContent = Get-Content -LiteralPath $runtimeFile.FullName -Raw -Encoding UTF8
        $relativePath = Get-RepoRelativePath -Root $repoRoot -Path $runtimeFile.FullName
        Assert-NotContains ("runtime release url avoids official channel: {0}" -f $relativePath) $runtimeContent "https://github.com/farion1231/cc-switch/releases"
    }
}
$forkUserEntryFiles = @(
    "SUPPORT.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "flatpak\com.ccswitch.desktop.metainfo.xml",
    "docs\user-manual\README.md",
    "docs\user-manual\en\README.md",
    "docs\user-manual\zh\README.md",
    "docs\user-manual\ja\README.md",
    "docs\user-manual\en\1-getting-started\1.2-installation.md",
    "docs\user-manual\zh\1-getting-started\1.2-installation.md",
    "docs\user-manual\ja\1-getting-started\1.2-installation.md",
    "docs\user-manual\en\5-faq\5.2-questions.md",
    "docs\user-manual\zh\5-faq\5.2-questions.md",
    "docs\user-manual\ja\5-faq\5.2-questions.md"
)
$officialUserEntryChannels = @(
    "https://github.com/farion1231/cc-switch/releases",
    "https://github.com/farion1231/cc-switch/issues",
    "https://github.com/farion1231/cc-switch/discussions",
    "https://github.com/farion1231/cc-switch/security"
)
foreach ($entryFile in $forkUserEntryFiles) {
    $entryPath = Join-Path $repoRoot $entryFile
    $entryContent = Get-Content -LiteralPath $entryPath -Raw -Encoding UTF8
    foreach ($officialChannel in $officialUserEntryChannels) {
        Assert-NotContains ("fork user entry avoids official channel: {0}" -f $entryFile) $entryContent $officialChannel
    }
}
$cargoToml = Get-Content -LiteralPath (Join-Path $repoRoot "src-tauri\Cargo.toml") -Raw -Encoding UTF8
Assert-Contains "Cargo.toml version" $cargoToml ('version = "{0}"' -f $expectedVersion)

Write-Host "==> official archive policy"
$gitignore = Get-Content -LiteralPath (Join-Path $repoRoot ".gitignore") -Raw -Encoding UTF8
Assert-Contains ".upstream ignored" $gitignore "/.upstream/"
$officialArchiveZip = Join-Path $repoRoot ".upstream\cc-switch-v3.16.2.zip"
$officialArchiveDir = Join-Path $repoRoot ".upstream\cc-switch-v3.16.2"
if (-not (Test-Path -LiteralPath $officialArchiveZip -PathType Leaf)) {
    throw "Missing official source archive zip: .upstream\cc-switch-v3.16.2.zip"
}
$archiveHash = (Get-FileHash -LiteralPath $officialArchiveZip -Algorithm SHA256).Hash
Assert-Equal "official v3.16.2 archive sha256" $archiveHash $expectedOfficialArchiveSha256
if (-not (Test-Path -LiteralPath $officialArchiveDir -PathType Container)) {
    throw "Missing extracted official source archive: .upstream\cc-switch-v3.16.2"
}
Write-Host "ok: official v3.16.2 archive extracted"
$archivePackageVersion = Get-JsonVersion (Join-Path $officialArchiveDir "package.json")
Assert-Equal "official archive package.json version" $archivePackageVersion $expectedOfficialArchiveVersion
$archiveTauriVersion = Get-JsonVersion (Join-Path $officialArchiveDir "src-tauri\tauri.conf.json")
Assert-Equal "official archive tauri.conf.json version" $archiveTauriVersion $expectedOfficialArchiveVersion
$trackedUpstreamFiles = @(git ls-files -- ".upstream")
if ($trackedUpstreamFiles.Count -ne 0) {
    throw ".upstream files must not be tracked by git"
}
Write-Host "ok: .upstream archive is not tracked"

Write-Host "==> test isolation policy"
$vitestConfig = Get-Content -LiteralPath (Join-Path $repoRoot "vitest.config.ts") -Raw -Encoding UTF8
Assert-Contains "Vitest excludes upstream archive" $vitestConfig "**/.upstream/**"

Write-Host "==> migration docs"
$migrationDoc = Get-Content -LiteralPath (Join-Path $repoRoot "docs\ccs-official-upstream-migration.md") -Raw -Encoding UTF8
Assert-Contains "official upstream decision" $migrationDoc 'Use official `farion1231/cc-switch` as the primary upstream from now on.'
Assert-Contains "ccs-web reference only" $migrationDoc '`ccs-web` is retained only as an auxiliary reference'
Assert-Contains "v3.16.2 target" $migrationDoc 'Official GitHub Releases currently show `v3.16.2`'
Assert-Contains "full rust sweep evidence" $migrationDoc "Full Rust library sweep now reports 1390 passed, 2 ignored."
Assert-Contains "fork updater channel" $migrationDoc 'Desktop updater endpoints must point at the fork release channel'

Write-Host "official_upstream_alignment=ready"
