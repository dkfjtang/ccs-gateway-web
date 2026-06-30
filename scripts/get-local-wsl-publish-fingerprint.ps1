param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [ValidateSet("full", "slim")]
    [string]$Profile = "full"
)

$ErrorActionPreference = "Stop"

function Get-RelativeUnixPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $rootUri = [System.Uri](([System.IO.Path]::GetFullPath($Root).TrimEnd('\')) + '\')
    $pathUri = [System.Uri]([System.IO.Path]::GetFullPath($Path))
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString())
}

function Add-FileHashInput {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.HashAlgorithm]$Hasher,
        [Parameter(Mandatory = $true)]
        [byte[]]$Buffer,
        [switch]$Finalize
    )

    if ($Finalize) {
        [void]$Hasher.TransformFinalBlock($Buffer, 0, $Buffer.Length)
        return
    }

    [void]$Hasher.TransformBlock($Buffer, 0, $Buffer.Length, $null, 0)
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$targets = New-Object System.Collections.Generic.List[string]
$directFiles = @(
    ".dockerignore",
    ".env.web",
    "Dockerfile.web",
    "index.html",
    "package.json",
    "pnpm-lock.yaml",
    "pnpm-workspace.yaml",
    "vite.config.ts",
    "tailwind.config.cjs",
    "postcss.config.cjs",
    "tsconfig.json",
    "tsconfig.node.json"
)

foreach ($relativePath in $directFiles) {
    $candidate = Join-Path $resolvedProjectRoot $relativePath
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $targets.Add($candidate)
    }
}

$srcRoot = Join-Path $resolvedProjectRoot "src"
if (Test-Path -LiteralPath $srcRoot -PathType Container) {
    Get-ChildItem -LiteralPath $srcRoot -Recurse -File | ForEach-Object {
        $targets.Add($_.FullName)
    }
}

$orderedTargets = $targets | Sort-Object -Unique
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    if ($orderedTargets.Count -eq 0) {
        Add-FileHashInput -Hasher $sha256 -Buffer ([System.Text.Encoding]::UTF8.GetBytes("profile=$Profile")) -Finalize
    } else {
        Add-FileHashInput -Hasher $sha256 -Buffer ([System.Text.Encoding]::UTF8.GetBytes("profile=$Profile"))
        Add-FileHashInput -Hasher $sha256 -Buffer ([byte[]](0))

        for ($index = 0; $index -lt $orderedTargets.Count; $index++) {
            $filePath = $orderedTargets[$index]
            $relativePath = Get-RelativeUnixPath -Root $resolvedProjectRoot -Path $filePath
            $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($relativePath)
            $separator = [byte[]](0)
            $contentBytes = [System.IO.File]::ReadAllBytes($filePath)

            Add-FileHashInput -Hasher $sha256 -Buffer $pathBytes
            Add-FileHashInput -Hasher $sha256 -Buffer $separator

            $isLast = ($index -eq $orderedTargets.Count - 1)
            if ($isLast) {
                Add-FileHashInput -Hasher $sha256 -Buffer $contentBytes -Finalize
            } else {
                Add-FileHashInput -Hasher $sha256 -Buffer $contentBytes
                Add-FileHashInput -Hasher $sha256 -Buffer $separator
            }
        }
    }

    $fingerprint = ([System.BitConverter]::ToString($sha256.Hash)).Replace("-", "").ToLowerInvariant()
    Write-Output $fingerprint
} finally {
    $sha256.Dispose()
}
