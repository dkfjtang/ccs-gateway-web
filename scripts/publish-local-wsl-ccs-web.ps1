<#
.SYNOPSIS
Publishes the local CCS Web build to the WSL Docker container.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -SkipBuild
#>

param(
    [string]$Distro = $(if ($env:CCS_WSL_DISTRO) { $env:CCS_WSL_DISTRO } else { "Ubuntu" }),
    [string]$ComposeFile = "docker-compose.ccs-web.yml",
    [string]$Service = "ccs-gateway-web",
    [string]$ContainerName = "ccs-gateway-web",
    [string]$Image = "ccs-gateway-web:local",
    [string]$WebHealthUrl = "http://127.0.0.1:17666/",
    [string]$ApiHealthUrl = "http://127.0.0.1:17666/api/invoke",
    [string]$ProxyHost = "127.0.0.1",
    [int]$ProxyPort = 15721,
    [int]$HealthRetries = 12,
    [int]$HealthDelaySeconds = 5,
    [string]$LogDir = ".run/local-wsl-publish",
    [switch]$SkipBuild,
    [switch]$SkipFrontendBuild,
    [switch]$NoStart,
    [switch]$SkipHealthCheck,
    [switch]$NoCache
)

$ErrorActionPreference = "Stop"
$transcriptStarted = $false

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

    $probe = "python3 -c 'import socket,sys; host=""$TcpHost""; port=$Port; sock=socket.create_connection((host, port), timeout=3); sock.close()'"

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

    $command = "cd " + (Quote-BashArg $ProjectRootWsl) + " && ${proxyPrefix}DOCKER_BUILDKIT=1 docker buildx bake --builder " + (Quote-BashArg $BuilderName) + " --file " + (Quote-BashArg $ComposeFile) + " " + (Quote-BashArg $Service) + " --load --set " + (Quote-BashArg "$Service.cache-from=type=local,src=$DockerCacheWsl") + " --set " + (Quote-BashArg "$Service.cache-to=type=local,dest=$DockerCacheWsl,mode=max") + $proxyArgs
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

    $command = "cd " + (Quote-BashArg $ProjectRootWsl) + " && ${proxyPrefix}DOCKER_BUILDKIT=1 docker buildx build --builder " + (Quote-BashArg $BuilderName) + " --file Dockerfile.web --target frontend-dist --output " + (Quote-BashArg "type=local,dest=$frontendDistWsl") + " --cache-from " + (Quote-BashArg "type=local,src=$DockerCacheWsl") + " --cache-to " + (Quote-BashArg "type=local,dest=$DockerCacheWsl,mode=max") + $proxyArgs
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
        [string]$ContainerName,
        [string]$Service
    )

    Write-Warning "Collecting failure diagnostics..."
    try {
        $command = "cd " + (Quote-BashArg $ProjectRootWsl) + " && docker compose -f " + (Quote-BashArg $ComposeFile) + " ps || true"
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
    Write-Host "Service:         $Service"
    Write-Host "Container:       $ContainerName"
    Write-Host "Image:           $Image"
    Write-Host "Web URL:         $WebHealthUrl"
    Write-Host "API health URL:  $ApiHealthUrl"
    Write-Host "Proxy TCP:       ${ProxyHost}:${ProxyPort}"
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
        Write-Step "Recreating local WSL container"
        $command = "cd " + (Quote-BashArg $projectRootWsl) + " && docker compose -f " + (Quote-BashArg $ComposeFile) + " up -d --force-recreate " + (Quote-BashArg $Service)
        Invoke-Wsl $command

        Write-Step "New container state"
        $command = "docker ps --filter " + (Quote-BashArg "name=^/${ContainerName}$") + " --format " + (Quote-BashArg "name={{.Names}} image={{.Image}} status={{.Status}} ports={{.Ports}}")
        Invoke-Wsl $command
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
    Write-FailureDiagnostics -ProjectRootWsl $projectRootWsl -ComposeFile $ComposeFile -ContainerName $ContainerName -Service $Service
    throw
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
