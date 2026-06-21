<#
.SYNOPSIS
Publishes the local CCS Web build to the WSL Docker container, or inspects/repairs local WSL relay ports.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro '<wsl-distro>'

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro '<wsl-distro>' -SkipBuild

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -RepairRelay -DryRun

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -RepairRelay -Force
#>

param(
    [string]$Distro = $env:CCS_WSL_DISTRO,
    [string]$ComposeFile = "docker-compose.ccs-web.yml",
    [string]$LocalComposeFile = "docker-compose.ccs-web.local.yml",
    [string]$Service = "ccs-gateway-web",
    [string]$ContainerName = "ccs-gateway-web",
    [string]$Image = "ccs-gateway-web:local",
    [string]$WebHealthUrl = "http://127.0.0.1:17666/",
    [string]$ApiHealthUrl = "http://127.0.0.1:17666/api/invoke",
    [string]$ProxyHost = "127.0.0.1",
    [int]$ProxyPort = 15721,
    [int]$HealthRetries = 12,
    [int]$HealthDelaySeconds = 5,
    [int]$StopTimeoutSeconds = 20,
    [string]$LogDir = ".run/local-wsl-publish",
    [switch]$SkipBuild,
    [switch]$SkipFrontendBuild,
    [switch]$NoStart,
    [switch]$SkipHealthCheck,
    [switch]$ForceWslShutdownOnStaleRelay,
    [switch]$ConfirmWslShutdown,
    [switch]$NoCache,
    [switch]$RepairRelay,
    [switch]$DryRun,
    [switch]$Force,
    [int[]]$RelayPorts
)

$ErrorActionPreference = "Stop"
$transcriptStarted = $false

if (($DryRun -or $Force) -and -not $RepairRelay) {
    throw "-DryRun and -Force are only valid with -RepairRelay. For publishing, use -ForceWslShutdownOnStaleRelay -ConfirmWslShutdown when WSL relay cleanup is required."
}
if ((-not $RepairRelay) -and $null -ne $RelayPorts -and $RelayPorts.Count -gt 0) {
    throw "-RelayPorts is only valid with -RepairRelay. Publishing uses the configured ProxyPort plus 17666."
}
if ($RepairRelay -and $DryRun -and $Force) {
    throw "-DryRun and -Force are mutually exclusive with -RepairRelay."
}
if ($RepairRelay -and -not $DryRun -and -not $Force) {
    throw "-RepairRelay requires either -DryRun or -Force."
}
if (-not $RepairRelay -and [string]::IsNullOrWhiteSpace($Distro)) {
    throw "WSL distro is required. Pass -Distro '<wsl-distro>' or set CCS_WSL_DISTRO for this command."
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Quote-BashArg {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return "''"
    }

    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Format-ConfiguredValue {
    param(
        [AllowNull()][string]$Value,
        [string]$ConfiguredLabel = "<configured>",
        [string]$EmptyLabel = "<none>"
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $EmptyLabel
    }

    return $ConfiguredLabel
}

function Invoke-Wsl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    wsl -d $Distro -- bash -lc $Command
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed with exit code ${LASTEXITCODE}: $Command"
    }
}

function Test-Http {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
        return @{
            ok = $true
            status = [int]$response.StatusCode
            body = ($response.Content | Out-String).Trim()
        }
    } catch {
        return @{
            ok = $false
            status = 0
            body = $_.Exception.Message
        }
    }
}

function Wait-Http {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    for ($attempt = 1; $attempt -le $HealthRetries; $attempt++) {
        $result = Test-Http $Url
        Write-Host ("{0}: attempt {1}/{2}: {3} {4}" -f $Name, $attempt, $HealthRetries, $result.status, $result.body)
        if ($result.ok) {
            return $result
        }

        if ($attempt -lt $HealthRetries) {
            Start-Sleep -Seconds $HealthDelaySeconds
        }
    }

    throw "$Name check failed after $HealthRetries attempts: $Url"
}

function Test-ApiHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $body = '{"command":"auth.status","payload":{}}'
    try {
        $response = Invoke-WebRequest `
            -Uri $Url `
            -UseBasicParsing `
            -Method Post `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 10
        $content = ($response.Content | Out-String).Trim()
        $parsed = $content | ConvertFrom-Json
        $hasResult = $null -ne $parsed.result
        $hasError = $null -ne $parsed.error
        return @{
            ok = ([int]$response.StatusCode -eq 200 -and $hasResult -and -not $hasError)
            status = [int]$response.StatusCode
            body = $content
        }
    } catch {
        return @{
            ok = $false
            status = 0
            body = $_.Exception.Message
        }
    }
}

function Wait-ApiHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    for ($attempt = 1; $attempt -le $HealthRetries; $attempt++) {
        $result = Test-ApiHealth $Url
        Write-Host ("{0}: attempt {1}/{2}: {3} {4}" -f $Name, $attempt, $HealthRetries, $result.status, $result.body)
        if ($result.ok) {
            return $result
        }

        if ($attempt -lt $HealthRetries) {
            Start-Sleep -Seconds $HealthDelaySeconds
        }
    }

    throw "$Name check failed after $HealthRetries attempts: $Url"
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TcpHost,
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connect = $client.BeginConnect($TcpHost, $Port, $null, $null)
        $ok = $connect.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(5))
        if ($ok) {
            $client.EndConnect($connect)
        }
        $client.Close()
        return $ok
    } catch {
        return $false
    }
}

function Wait-TcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TcpHost,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    for ($attempt = 1; $attempt -le $HealthRetries; $attempt++) {
        $ok = Test-TcpPort -TcpHost $TcpHost -Port $Port
        Write-Host ("{0}: attempt {1}/{2}: tcp {3}:{4} reachable={5}" -f $Name, $attempt, $HealthRetries, $TcpHost, $Port, $ok)
        if ($ok) {
            return
        }

        if ($attempt -lt $HealthRetries) {
            Start-Sleep -Seconds $HealthDelaySeconds
        }
    }

    throw "$Name check failed after $HealthRetries attempts: ${TcpHost}:${Port}"
}

function Get-IndexScriptAssets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $assets = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($Html, '/assets/index-[^"]+\.js')) {
        $assets.Add($match.Value.TrimStart('/'))
    }
    return @($assets | Sort-Object -Unique)
}

function Get-IndexStyleAssets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $assets = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($Html, '/assets/index-[^"]+\.css')) {
        $assets.Add($match.Value.TrimStart('/'))
    }
    return @($assets | Sort-Object -Unique)
}

function Assert-ServedBuildMatchesDockerFrontendSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SnapshotIndexPath,
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    if (-not (Test-Path -LiteralPath $SnapshotIndexPath)) {
        throw "Docker frontend snapshot index not found: $SnapshotIndexPath"
    }

    $localHtml = Get-Content -LiteralPath $SnapshotIndexPath -Encoding UTF8 -Raw
    $localScripts = Get-IndexScriptAssets -Html $localHtml
    $localStyles = Get-IndexStyleAssets -Html $localHtml
    if ($localScripts.Count -eq 0) {
        throw "No Docker frontend snapshot Vite index script asset found in: $SnapshotIndexPath"
    }

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
    $servedScripts = Get-IndexScriptAssets -Html $response.Content
    $servedStyles = Get-IndexStyleAssets -Html $response.Content
    if ($servedScripts.Count -eq 0) {
        throw "No served Vite index script asset found from: $Url"
    }

    $localScriptJoined = $localScripts -join ","
    $servedScriptJoined = $servedScripts -join ","
    $localStyleJoined = $localStyles -join ","
    $servedStyleJoined = $servedStyles -join ","
    Write-Host ("Served build scripts: snapshot={0} served={1}" -f $localScriptJoined, $servedScriptJoined)
    Write-Host ("Served build styles:  snapshot={0} served={1}" -f $localStyleJoined, $servedStyleJoined)
    if ($localScriptJoined -ne $servedScriptJoined -or $localStyleJoined -ne $servedStyleJoined) {
        throw "Served build does not match Docker frontend snapshot. snapshot_scripts=${localScriptJoined}; served_scripts=${servedScriptJoined}; snapshot_styles=${localStyleJoined}; served_styles=${servedStyleJoined}"
    }
}

function ConvertTo-WslPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsPath
    )

    $resolved = Resolve-Path -LiteralPath $WindowsPath
    $path = $resolved.Path
    if ($path -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "Only drive-letter Windows paths are supported: $path"
    }

    $drive = $Matches[1].ToLowerInvariant()
    $tail = $Matches[2] -replace '\\', '/'
    return "/mnt/$drive/$tail"
}

function Resolve-LocalLogDir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)]
        [string]$RelativeLogDir
    )

    $combined = Join-Path $ProjectRoot $RelativeLogDir
    $full = [System.IO.Path]::GetFullPath($combined)
    $allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot ".run"))

    $allowedPrefix = $allowedRoot.TrimEnd('\') + '\'
    $normalizedFull = $full.TrimEnd('\')
    if ($normalizedFull -ne $allowedRoot -and -not $normalizedFull.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "LogDir must stay under the ignored local .run directory: $RelativeLogDir"
    }

    return $full
}

function Resolve-LocalRunPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $combined = Join-Path $ProjectRoot $RelativePath
    $full = [System.IO.Path]::GetFullPath($combined)
    $allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot ".run"))

    $allowedPrefix = $allowedRoot.TrimEnd('\') + '\'
    $normalizedFull = $full.TrimEnd('\')
    if ($normalizedFull -ne $allowedRoot -and -not $normalizedFull.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must stay under the ignored local .run directory: $RelativePath"
    }

    return $full
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Get-LocalPublishCacheLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $buildCacheRoot = Resolve-LocalRunPath -ProjectRoot $ProjectRoot -RelativePath ".run/build-cache"
    $metaRoot = Join-Path $buildCacheRoot "meta"

    $layout = [ordered]@{
        BuildCacheRoot = $buildCacheRoot
        FrontendDist = Join-Path $buildCacheRoot "frontend-dist"
        DockerCache = Join-Path $buildCacheRoot "docker"
        MetaRoot = $metaRoot
        FrontendFingerprint = Join-Path $metaRoot "frontend-dist.fingerprint"
    }

    foreach ($path in $layout.Values) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        if ($path -like "*.fingerprint") {
            continue
        }

        Ensure-Directory -Path $path
    }

    return $layout
}

function Get-FrontendFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )

    $fingerprintScript = Join-Path $ScriptRoot "get-local-wsl-publish-fingerprint.ps1"
    if (-not (Test-Path -LiteralPath $fingerprintScript)) {
        throw "Fingerprint script not found: $fingerprintScript"
    }

    $fingerprint = powershell -NoProfile -ExecutionPolicy Bypass -File $fingerprintScript -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Frontend fingerprint script failed with exit code ${LASTEXITCODE}."
    }

    $joined = (($fingerprint | ForEach-Object { "$_".Trim() }) -join "").Trim()
    if ([string]::IsNullOrWhiteSpace($joined)) {
        throw "Frontend fingerprint script returned an empty fingerprint."
    }

    return $joined
}

function Get-StoredFrontendFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FingerprintPath
    )

    if (-not (Test-Path -LiteralPath $FingerprintPath -PathType Leaf)) {
        return $null
    }

    return (Get-Content -LiteralPath $FingerprintPath -Encoding UTF8 -Raw).Trim()
}

function Set-StoredFrontendFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FingerprintPath,
        [Parameter(Mandatory = $true)]
        [string]$Fingerprint
    )

    [System.IO.File]::WriteAllText($FingerprintPath, $Fingerprint + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
}

function Ensure-DockerFrontendSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot,
        [Parameter(Mandatory = $true)]
        [hashtable]$CacheLayout,
        [switch]$SkipFrontendBuild,
        [switch]$NoCache
    )

    $snapshotIndexPath = Join-Path $CacheLayout.FrontendDist "index.html"
    $currentFingerprint = Get-FrontendFingerprint -ProjectRoot $ProjectRoot -ScriptRoot $ScriptRoot
    $storedFingerprint = Get-StoredFrontendFingerprint -FingerprintPath $CacheLayout.FrontendFingerprint
    $snapshotExists = Test-Path -LiteralPath $snapshotIndexPath -PathType Leaf
    $needsRefresh = $NoCache -or (-not $snapshotExists) -or ([string]::IsNullOrWhiteSpace($storedFingerprint)) -or ($storedFingerprint -ne $currentFingerprint)

    Write-Host "Frontend fingerprint: current=$currentFingerprint stored=$storedFingerprint"
    Write-Host "Docker frontend snapshot index: $snapshotIndexPath exists=$snapshotExists"

    if ($needsRefresh -and $SkipFrontendBuild) {
        throw "Docker frontend dist snapshot is stale or missing, but -SkipFrontendBuild was specified."
    }

    if ($needsRefresh) {
        Write-Step "Docker frontend dist snapshot needs refresh"
    } else {
        Write-Step "Skipping Docker frontend dist snapshot refresh"
        Write-Host "Frontend inputs unchanged; reusing exported Docker dist snapshot."
    }

    return @{
        IndexPath = $snapshotIndexPath
        Fingerprint = $currentFingerprint
        NeedsRefresh = $needsRefresh
    }
}

function Get-DockerBuildxBuilderName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $rootName = Split-Path -Leaf $ProjectRoot
    $sanitized = ($rootName -replace '[^A-Za-z0-9_.-]', '-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        $sanitized = "ccs-gateway-web"
    }

    return "$sanitized-local"
}

function Ensure-DockerBuildxBuilder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BuilderName,
        [string]$ProxyUrl
    )

    $builderArg = Quote-BashArg $BuilderName
    if ([string]::IsNullOrWhiteSpace($ProxyUrl)) {
        $inspectCommand = "docker buildx inspect $builderArg >/dev/null 2>&1 || docker buildx create --name $builderArg --driver docker-container --use >/dev/null"
        Invoke-Wsl $inspectCommand
    } else {
        $inspectOutput = wsl -d $Distro -- bash -lc "docker buildx inspect $builderArg 2>/dev/null"
        $inspectSucceeded = ($LASTEXITCODE -eq 0)
        $inspectText = ($inspectOutput | ForEach-Object { "$_" }) -join "`n"
        $hasProxy = $inspectSucceeded `
            -and $inspectText.Contains("env.HTTP_PROXY=""$ProxyUrl""") `
            -and $inspectText.Contains("env.HTTPS_PROXY=""$ProxyUrl""")
        if (-not $hasProxy) {
            $proxyArg = Quote-BashArg $ProxyUrl
            Invoke-Wsl "docker buildx rm $builderArg >/dev/null 2>&1 || true"
            Invoke-Wsl "docker buildx create --name $builderArg --driver docker-container --driver-opt env.http_proxy=$proxyArg --driver-opt env.https_proxy=$proxyArg --driver-opt env.HTTP_PROXY=$proxyArg --driver-opt env.HTTPS_PROXY=$proxyArg --use >/dev/null"
        }
    }

    Invoke-Wsl "docker buildx inspect $builderArg --bootstrap >/dev/null"
}

function Get-WslDefaultGateway {
    $gatewayScript = "ip route | grep '^default ' | head -n 1 | cut -d ' ' -f 3"
    $gateway = wsl -d $Distro -- bash -lc $gatewayScript
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $joined = (($gateway | ForEach-Object { "$_".Trim() }) -join "").Trim()
    if ([string]::IsNullOrWhiteSpace($joined)) {
        return $null
    }

    return $joined
}

function Test-WslTcpEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TcpHost,
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $hostArg = Quote-BashArg $TcpHost
    $python = "import socket; host=$hostArg; port=$Port; sock=socket.create_connection((host, port), timeout=3); sock.close()"
    $probe = "python3 -c " + (Quote-BashArg $python)

    wsl -d $Distro -- bash -lc $probe | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Get-AutoBuildProxyUrl {
    $gateway = Get-WslDefaultGateway
    if ([string]::IsNullOrWhiteSpace($gateway)) {
        return $null
    }

    if (Test-WslTcpEndpoint -TcpHost $gateway -Port 7890) {
        return "http://${gateway}:7890"
    }

    return $null
}

function Get-HostProxyUrl {
    if ($env:HTTP_PROXY) { return $env:HTTP_PROXY }
    if ($env:http_proxy) { return $env:http_proxy }
    if ($env:HTTPS_PROXY) { return $env:HTTPS_PROXY }
    if ($env:https_proxy) { return $env:https_proxy }
    return $null
}

function ConvertTo-WslReachableProxyUrl {
    param(
        [string]$ProxyUrl
    )

    if ([string]::IsNullOrWhiteSpace($ProxyUrl)) {
        return $null
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($ProxyUrl, [System.UriKind]::Absolute, [ref]$uri)) {
        return $ProxyUrl
    }

    if ($uri.Host -ne "127.0.0.1" -and $uri.Host -ne "localhost") {
        return $ProxyUrl
    }

    $gateway = Get-WslDefaultGateway
    if ([string]::IsNullOrWhiteSpace($gateway)) {
        return $ProxyUrl
    }

    $builder = [System.UriBuilder]::new($uri)
    $builder.Host = $gateway
    return $builder.Uri.AbsoluteUri.TrimEnd("/")
}

function Invoke-DockerComposeBuildWithCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRootWsl,
        [Parameter(Mandatory = $true)]
        [string]$ComposeFile,
        [Parameter(Mandatory = $true)]
        [string]$Service,
        [Parameter(Mandatory = $true)]
        [string]$DockerCacheWsl,
        [Parameter(Mandatory = $true)]
        [string]$BuilderName,
        [string]$ProxyUrl,
        [switch]$NoCache
    )

    $proxyPrefix = ""
    $proxyArgs = ""
    if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
        $proxyArg = Quote-BashArg $ProxyUrl
        $proxyPrefix = "HTTP_PROXY=$proxyArg HTTPS_PROXY=$proxyArg http_proxy=$proxyArg https_proxy=$proxyArg "
        $proxyArgs = " --set " + (Quote-BashArg "$Service.args.HTTP_PROXY=$ProxyUrl") + " --set " + (Quote-BashArg "$Service.args.HTTPS_PROXY=$ProxyUrl") + " --set " + (Quote-BashArg "$Service.args.http_proxy=$ProxyUrl") + " --set " + (Quote-BashArg "$Service.args.https_proxy=$ProxyUrl")
    }

    if ($env:CCS_WEB_NODE_IMAGE) {
        $proxyArgs += " --set " + (Quote-BashArg "$Service.args.NODE_IMAGE=$($env:CCS_WEB_NODE_IMAGE)")
    }
    if ($env:CCS_WEB_RUST_IMAGE) {
        $proxyArgs += " --set " + (Quote-BashArg "$Service.args.RUST_IMAGE=$($env:CCS_WEB_RUST_IMAGE)")
    }
    if ($env:CCS_WEB_DEBIAN_IMAGE) {
        $proxyArgs += " --set " + (Quote-BashArg "$Service.args.DEBIAN_IMAGE=$($env:CCS_WEB_DEBIAN_IMAGE)")
    }

    $command = "cd " + (Quote-BashArg $ProjectRootWsl) + " && ${proxyPrefix}DOCKER_BUILDKIT=1 docker buildx bake --pull=false --builder " + (Quote-BashArg $BuilderName) + " --file " + (Quote-BashArg $ComposeFile) + " " + (Quote-BashArg $Service) + " --load --set " + (Quote-BashArg "$Service.cache-from=type=local,src=$DockerCacheWsl") + " --set " + (Quote-BashArg "$Service.cache-to=type=local,dest=$DockerCacheWsl,mode=max") + $proxyArgs
    if ($NoCache) {
        $command += " --no-cache"
    }

    Invoke-Wsl $command
}

function Export-DockerFrontendDistWithCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)]
        [string]$ProjectRootWsl,
        [Parameter(Mandatory = $true)]
        [string]$DockerCacheWsl,
        [Parameter(Mandatory = $true)]
        [string]$BuilderName,
        [Parameter(Mandatory = $true)]
        [string]$FrontendDistPath,
        [string]$ProxyUrl,
        [switch]$NoCache
    )

    $frontendDistWsl = ConvertTo-WslPath -WindowsPath $FrontendDistPath
    if (Test-Path -LiteralPath $FrontendDistPath) {
        Remove-Item -LiteralPath $FrontendDistPath -Recurse -Force
    }
    Ensure-Directory -Path $FrontendDistPath

    $proxyPrefix = ""
    $proxyArgs = ""
    if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
        $proxyArg = Quote-BashArg $ProxyUrl
        $proxyPrefix = "HTTP_PROXY=$proxyArg HTTPS_PROXY=$proxyArg http_proxy=$proxyArg https_proxy=$proxyArg "
        $proxyArgs = " --build-arg HTTP_PROXY=$proxyArg --build-arg HTTPS_PROXY=$proxyArg --build-arg http_proxy=$proxyArg --build-arg https_proxy=$proxyArg"
    }

    if ($env:CCS_WEB_NODE_IMAGE) {
        $proxyArgs += " --build-arg NODE_IMAGE=" + (Quote-BashArg $env:CCS_WEB_NODE_IMAGE)
    }
    if ($env:CCS_WEB_RUST_IMAGE) {
        $proxyArgs += " --build-arg RUST_IMAGE=" + (Quote-BashArg $env:CCS_WEB_RUST_IMAGE)
    }
    if ($env:CCS_WEB_DEBIAN_IMAGE) {
        $proxyArgs += " --build-arg DEBIAN_IMAGE=" + (Quote-BashArg $env:CCS_WEB_DEBIAN_IMAGE)
    }

    $command = "cd " + (Quote-BashArg $ProjectRootWsl) + " && ${proxyPrefix}DOCKER_BUILDKIT=1 docker buildx build --pull=false --builder " + (Quote-BashArg $BuilderName) + " --file Dockerfile.web --target frontend-dist --output " + (Quote-BashArg "type=local,dest=$frontendDistWsl") + " --cache-from " + (Quote-BashArg "type=local,src=$DockerCacheWsl") + " --cache-to " + (Quote-BashArg "type=local,dest=$DockerCacheWsl,mode=max") + $proxyArgs
    if ($NoCache) {
        $command += " --no-cache"
    }
    $command += " ."

    Invoke-Wsl $command

    $indexPath = Join-Path $FrontendDistPath "index.html"
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        throw "Exported Docker frontend dist index not found: $indexPath"
    }

    return $indexPath
}

function Write-FailureDiagnostics {
    param(
        [string]$ProjectRootWsl,
        [string]$ComposeFile,
        [string]$LocalComposeFile,
        [string]$ContainerName,
        [string]$Service
    )

    Write-Warning "Collecting failure diagnostics..."
    try {
        $composeArgs = " -f " + (Quote-BashArg $ComposeFile)
        if (-not [string]::IsNullOrWhiteSpace($LocalComposeFile)) {
            $localComposePath = Join-Path $ProjectRoot $LocalComposeFile
            if (Test-Path -LiteralPath $localComposePath -PathType Leaf) {
                $localComposeWsl = ConvertTo-WslPath -WindowsPath $localComposePath
                $composeArgs += " -f " + (Quote-BashArg $localComposeWsl)
            }
        }
        $command = "cd " + (Quote-BashArg $ProjectRootWsl) + " && docker compose$composeArgs ps || true"
        Invoke-Wsl $command
    } catch {
        Write-Warning ("Failed to collect docker compose ps: {0}" -f $_.Exception.Message)
    }

    try {
        $command = "docker ps -a --filter " + (Quote-BashArg "name=^/${ContainerName}$") + " --format " + (Quote-BashArg "name={{.Names}} image={{.Image}} status={{.Status}} ports={{.Ports}}") + " || true"
        Invoke-Wsl $command
    } catch {
        Write-Warning ("Failed to collect docker ps: {0}" -f $_.Exception.Message)
    }

    try {
        $command = "docker logs --tail 200 " + (Quote-BashArg $ContainerName) + " 2>/dev/null || true"
        Invoke-Wsl $command
    } catch {
        Write-Warning ("Failed to collect container logs: {0}" -f $_.Exception.Message)
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptRoot "..")
$composePath = Join-Path $projectRoot $ComposeFile
$localComposePath = if ([string]::IsNullOrWhiteSpace($LocalComposeFile)) { $null } else { Join-Path $projectRoot $LocalComposeFile }
$composeFiles = New-Object System.Collections.Generic.List[string]
$composeFiles.Add($ComposeFile)
if ($localComposePath -and (Test-Path -LiteralPath $localComposePath -PathType Leaf)) {
    $composeFiles.Add($LocalComposeFile)
}

function Test-WslTcpPortsReleased {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports
    )

    $pattern = ($Ports | ForEach-Object { "$_" }) -join "|"
    $command = "if ss -H -ltn | awk '{print `$4}' | grep -Eq ':($pattern)$'; then exit 1; else exit 0; fi"
    wsl -d $Distro -- bash -lc $command | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Wait-WslTcpPortsReleased {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $joinedPorts = $Ports -join ","
    for ($attempt = 1; $attempt -le $HealthRetries; $attempt++) {
        $released = Test-WslTcpPortsReleased -Ports $Ports
        Write-Host ("{0}: attempt {1}/{2}: ports {3} released={4}" -f $Name, $attempt, $HealthRetries, $joinedPorts, $released)
        if ($released) {
            return
        }

        if ($attempt -lt $HealthRetries) {
            Start-Sleep -Seconds $HealthDelaySeconds
        }
    }

    throw "$Name check failed after $HealthRetries attempts: ports $joinedPorts are still listening in WSL."
}

function Get-WindowsTcpConnectionsForPorts {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports
    )

    try {
        return @(Get-NetTCPConnection -LocalPort $Ports -ErrorAction SilentlyContinue)
    } catch {
        return @()
    }
}

function Write-WindowsTcpConnectionsForPorts {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $connections = Get-WindowsTcpConnectionsForPorts -Ports $Ports
    if ($connections.Count -eq 0) {
        Write-Host ("{0}: no Windows TCP connections for ports {1}" -f $Name, ($Ports -join ","))
        return
    }

    Write-Host ("{0}: Windows TCP connections for ports {1}" -f $Name, ($Ports -join ","))
    $connections |
        Sort-Object LocalPort, State, RemotePort |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess, @{Name = "ProcessName"; Expression = { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName } } |
        Format-Table -AutoSize
}

function Test-WindowsStaleWslRelayConnectionsForPorts {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports
    )

    $connections = Get-WindowsTcpConnectionsForPorts -Ports $Ports
    $staleRelayConnections = @(
        $connections |
            Where-Object {
                $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                $process -and $process.ProcessName -eq "wslrelay" -and $_.State -ne "Listen"
            }
    )

    return ($staleRelayConnections.Count -gt 0)
}

function Normalize-RelayPorts {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports
    )

    $normalized = @(
        $Ports |
            Sort-Object -Unique |
            ForEach-Object {
                if ($_ -lt 1 -or $_ -gt 65535) {
                    throw "Relay port must be in range 1..65535: $_"
                }
                $_
            }
    )
    if ($normalized.Count -eq 0) {
        throw "At least one relay port is required."
    }

    return $normalized
}

function Get-WindowsWslRelayConnectionsForPorts {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports
    )

    return @(
        Get-WindowsTcpConnectionsForPorts -Ports $Ports |
            Where-Object {
                $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                $process -and $process.ProcessName -eq "wslrelay"
            } |
            Sort-Object LocalPort, State, RemotePort
    )
}

function Write-WindowsWslRelayConnectionsForPorts {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $connections = Get-WindowsWslRelayConnectionsForPorts -Ports $Ports
    if ($connections.Count -eq 0) {
        Write-Host ("{0}: no wslrelay TCP connections for ports {1}" -f $Name, ($Ports -join ","))
        return
    }

    Write-Host ("{0}: wslrelay TCP connections for ports {1}" -f $Name, ($Ports -join ","))
    $connections |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess |
        Format-Table -AutoSize
}

function Repair-LocalWslRelay {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports,
        [Parameter(Mandatory = $true)]
        [bool]$ForceRepair,
        [Parameter(Mandatory = $true)]
        [int]$Retries,
        [Parameter(Mandatory = $true)]
        [int]$DelaySeconds
    )

    Write-Step "Local WSL relay status"
    Write-Host ("Ports:           {0}" -f ($Ports -join ","))
    Write-WindowsWslRelayConnectionsForPorts -Ports $Ports -Name "Before repair"

    $repairableConnections = @(
        Get-WindowsWslRelayConnectionsForPorts -Ports $Ports |
            Where-Object { $_.State -ne "Listen" }
    )
    if ($repairableConnections.Count -eq 0) {
        Write-Host "No non-listening wslrelay connections found for the target ports. No repair action is required."
        return
    }

    if (-not $ForceRepair) {
        Write-Host "Dry run only. Re-run with -RepairRelay -Force to execute: wsl --shutdown"
        return
    }

    Write-Step "Restarting WSL to clear relay connections"
    wsl --shutdown
    if ($LASTEXITCODE -ne 0) {
        throw "wsl --shutdown failed with exit code ${LASTEXITCODE}."
    }

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        Start-Sleep -Seconds $DelaySeconds
        $connections = Get-WindowsWslRelayConnectionsForPorts -Ports $Ports
        $released = ($connections.Count -eq 0)
        Write-Host ("Relay release: attempt {0}/{1}: ports {2} released={3}" -f $attempt, $Retries, ($Ports -join ","), $released)
        if ($released) {
            Write-WindowsWslRelayConnectionsForPorts -Ports $Ports -Name "After repair"
            Write-Host "Local WSL relay repair completed."
            return
        }
    }

    Write-WindowsWslRelayConnectionsForPorts -Ports $Ports -Name "After repair timeout"
    throw "WSL relay ports were not released after $Retries attempts."
}

if ($null -eq $RelayPorts -or $RelayPorts.Count -eq 0) {
    $RelayPorts = @($ProxyPort, 17666) | Sort-Object -Unique
}
$RelayPorts = Normalize-RelayPorts -Ports $RelayPorts
if ($RepairRelay) {
    Repair-LocalWslRelay -Ports $RelayPorts -ForceRepair:$Force.IsPresent -Retries $HealthRetries -DelaySeconds $HealthDelaySeconds
    return
}

if (-not (Test-Path -LiteralPath $composePath)) {
    throw "Compose file not found: $composePath"
}

$projectRootWsl = ConvertTo-WslPath -WindowsPath $projectRoot
$resolvedLogDir = Resolve-LocalLogDir -ProjectRoot $projectRoot -RelativeLogDir $LogDir
$cacheLayout = Get-LocalPublishCacheLayout -ProjectRoot $projectRoot
$dockerCacheWsl = ConvertTo-WslPath -WindowsPath $cacheLayout.DockerCache
$builderName = Get-DockerBuildxBuilderName -ProjectRoot $projectRoot
$autoBuildProxyUrl = $null
New-Item -ItemType Directory -Force -Path $resolvedLogDir | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $resolvedLogDir "publish-local-wsl-ccs-web-$timestamp.log"

try {
    Start-Transcript -LiteralPath $logPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Step "Preflight"
    Write-Host "Distro:          $Distro"
    Write-Host "Compose file:    $ComposeFile"
    if ($composeFiles.Count -gt 1) {
        Write-Host "Local compose:   $LocalComposeFile"
    }
    Write-Host "Service:         $Service"
    Write-Host "Container:       $ContainerName"
    Write-Host "Image:           $Image"
    Write-Host "Web URL:         $WebHealthUrl"
    Write-Host "API health URL:  $ApiHealthUrl"
    Write-Host "Proxy TCP:       ${ProxyHost}:${ProxyPort}"
    Write-Host "Stop timeout:    ${StopTimeoutSeconds}s"
    Write-Host "WSL shutdown on stale relay: $ForceWslShutdownOnStaleRelay"
    Write-Host "Log file:        $logPath"
    Write-Host "Build cache:     $($cacheLayout.BuildCacheRoot)"
    Write-Host "Docker cache:    $($cacheLayout.DockerCache)"
    Write-Host "No cache:        $NoCache"
    if ($env:CCS_WEB_NODE_IMAGE) { Write-Host "Node image:      <configured>" }
    if ($env:CCS_WEB_RUST_IMAGE) { Write-Host "Rust image:      <configured>" }
    if ($env:CCS_WEB_DEBIAN_IMAGE) { Write-Host "Debian image:    <configured>" }

    Write-Step "Checking WSL Docker"
    Invoke-Wsl "command -v docker >/dev/null && docker version --format '{{.Server.Version}}'"
    $command = "cd " + (Quote-BashArg $projectRootWsl) + " && docker compose version"
    Invoke-Wsl $command
    $autoBuildProxyUrl = Get-HostProxyUrl
    if ([string]::IsNullOrWhiteSpace($autoBuildProxyUrl)) {
        $autoBuildProxyUrl = Get-AutoBuildProxyUrl
    } else {
        $autoBuildProxyUrl = ConvertTo-WslReachableProxyUrl -ProxyUrl $autoBuildProxyUrl
    }
    Write-Host "Build proxy:     $(Format-ConfiguredValue -Value $autoBuildProxyUrl)"

    Write-Step "Current image and container state"
    $command = "docker image inspect " + (Quote-BashArg $Image) + " --format " + (Quote-BashArg "image={{.Id}} created={{.Created}} size={{.Size}}") + " 2>/dev/null || true"
    Invoke-Wsl $command
    $command = "docker ps -a --filter " + (Quote-BashArg "name=^/${ContainerName}$") + " --format " + (Quote-BashArg "name={{.Names}} image={{.Image}} status={{.Status}} ports={{.Ports}}") + " || true"
    Invoke-Wsl $command
    $command = "docker inspect " + (Quote-BashArg $ContainerName) + " --format " + (Quote-BashArg "id={{.Id}} image={{.Image}} created={{.Created}} restart={{.HostConfig.RestartPolicy.Name}} mounts={{range .Mounts}}{{.Source}}:{{.Destination}};{{end}}") + " 2>/dev/null || true"
    Invoke-Wsl $command

    $frontendSnapshot = Ensure-DockerFrontendSnapshot -ProjectRoot $projectRoot -ScriptRoot $scriptRoot -CacheLayout $cacheLayout -SkipFrontendBuild:$SkipFrontendBuild -NoCache:$NoCache
    $snapshotIndexPath = $frontendSnapshot.IndexPath

    if ($SkipBuild -and ($frontendSnapshot.NeedsRefresh -or (-not (Test-Path -LiteralPath $snapshotIndexPath -PathType Leaf)))) {
        throw "Docker frontend snapshot is stale or missing, but -SkipBuild was specified. Run without -SkipBuild to rebuild the image and refresh the snapshot."
    }

    if (-not $SkipBuild) {
        Write-Step "Building local image"
        Ensure-DockerBuildxBuilder -BuilderName $builderName -ProxyUrl $autoBuildProxyUrl
        Invoke-DockerComposeBuildWithCache -ProjectRootWsl $projectRootWsl -ComposeFile $ComposeFile -Service $Service -DockerCacheWsl $dockerCacheWsl -BuilderName $builderName -ProxyUrl $autoBuildProxyUrl -NoCache:$NoCache

        $command = "docker image inspect " + (Quote-BashArg $Image) + " --format " + (Quote-BashArg "image={{.Id}} created={{.Created}} size={{.Size}}")
        Invoke-Wsl $command
    } else {
        Write-Step "Skipping build"
    }

    if ($frontendSnapshot.NeedsRefresh -or (-not (Test-Path -LiteralPath $snapshotIndexPath -PathType Leaf))) {
        Write-Step "Exporting Docker frontend dist snapshot"
        Ensure-DockerBuildxBuilder -BuilderName $builderName -ProxyUrl $autoBuildProxyUrl
        $snapshotIndexPath = Export-DockerFrontendDistWithCache -ProjectRoot $projectRoot -ProjectRootWsl $projectRootWsl -DockerCacheWsl $dockerCacheWsl -BuilderName $builderName -FrontendDistPath $cacheLayout.FrontendDist -ProxyUrl $autoBuildProxyUrl -NoCache:$NoCache
        Set-StoredFrontendFingerprint -FingerprintPath $cacheLayout.FrontendFingerprint -Fingerprint $frontendSnapshot.Fingerprint
    }

    if (-not $NoStart) {
        $publishedPorts = @($ProxyPort, 17666) | Sort-Object -Unique
        $composeArgString = " -f " + (Quote-BashArg $ComposeFile)
        if ($composeFiles.Count -gt 1) {
            $localComposeWsl = ConvertTo-WslPath -WindowsPath $localComposePath
            $composeArgString += " -f " + (Quote-BashArg $localComposeWsl)
        }

        Write-Step "Stopping existing local WSL container"
        Write-WindowsTcpConnectionsForPorts -Ports $publishedPorts -Name "Before stop"
        $command = "cd " + (Quote-BashArg $projectRootWsl) + " && docker compose$composeArgString stop -t $StopTimeoutSeconds " + (Quote-BashArg $Service) + " || true"
        Invoke-Wsl $command
        $command = "cd " + (Quote-BashArg $projectRootWsl) + " && docker compose$composeArgString rm -f " + (Quote-BashArg $Service) + " || true"
        Invoke-Wsl $command
        $command = "docker ps -a --filter " + (Quote-BashArg "name=^/${ContainerName}$") + " --filter " + (Quote-BashArg "label=com.docker.compose.service=$Service") + " --format " + (Quote-BashArg "{{.ID}}") + " | xargs -r docker rm -f"
        Invoke-Wsl $command

        Write-Step "Waiting for old published ports to release"
        Wait-WslTcpPortsReleased -Ports $publishedPorts -Name "WSL port release"
        Write-WindowsTcpConnectionsForPorts -Ports $publishedPorts -Name "After WSL port release"
        if (Test-WindowsStaleWslRelayConnectionsForPorts -Ports $publishedPorts) {
            if ($ForceWslShutdownOnStaleRelay -and $ConfirmWslShutdown) {
                Write-Step "Restarting WSL to clear stale relay connections"
                wsl --shutdown
                if ($LASTEXITCODE -ne 0) {
                    throw "wsl --shutdown failed with exit code ${LASTEXITCODE}."
                }
                Start-Sleep -Seconds 5
                Write-WindowsTcpConnectionsForPorts -Ports $publishedPorts -Name "After WSL shutdown"
            } else {
                Write-Warning "Stale Windows wslrelay connections remain on published ports. Existing clients may keep talking to the old connection until they reconnect. WSL shutdown is disabled by default. To force it, rerun with both -ForceWslShutdownOnStaleRelay and -ConfirmWslShutdown; this stops other WSL workloads."
            }
        }

        Write-Step "Recreating local WSL container"
        $command = "cd " + (Quote-BashArg $projectRootWsl) + " && docker compose$composeArgString up -d --force-recreate --remove-orphans " + (Quote-BashArg $Service)
        Invoke-Wsl $command

        Write-Step "New container state"
        $command = "docker ps --filter " + (Quote-BashArg "name=^/${ContainerName}$") + " --format " + (Quote-BashArg "name={{.Names}} image={{.Image}} status={{.Status}} ports={{.Ports}}")
        Invoke-Wsl $command
        Write-WindowsTcpConnectionsForPorts -Ports $publishedPorts -Name "After start"
    } else {
        Write-Step "Skipping container start"
    }

    if (-not $SkipHealthCheck -and -not $NoStart) {
        Write-Step "Health checks"
        Wait-Http -Url $WebHealthUrl -Name "Web UI" | Out-Null
        Wait-ApiHealth -Url $ApiHealthUrl -Name "API health" | Out-Null
        Wait-TcpPort -TcpHost $ProxyHost -Port $ProxyPort -Name "Proxy port" | Out-Null

        Write-Step "Served build check"
        Assert-ServedBuildMatchesDockerFrontendSnapshot -SnapshotIndexPath $snapshotIndexPath -Url $WebHealthUrl
    }

    Write-Step "Done"
    Write-Host "Local WSL CCS Web publish completed."
    Write-Host "Log file: $logPath"
} catch {
    Write-FailureDiagnostics -ProjectRootWsl $projectRootWsl -ComposeFile $ComposeFile -LocalComposeFile $LocalComposeFile -ContainerName $ContainerName -Service $Service
    throw
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
