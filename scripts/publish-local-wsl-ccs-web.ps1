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
    [ValidateSet("full", "slim")]
    [string]$Profile = "full",
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
$ConfirmPreference = "None"
$ProgressPreference = "SilentlyContinue"
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
if (-not $RepairRelay -and $Profile -eq "slim" -and $SkipHealthCheck) {
    throw "Slim profile publishing requires health and profile checks. Do not use -SkipHealthCheck with -Profile slim."
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

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = wsl -d $Distro -- bash -lc "export CI=1 DOCKER_CLI_HINTS=false BUILDKIT_PROGRESS=plain; $Command" 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $output | ForEach-Object {
        Write-Host $_
    }
    if ($exitCode -ne 0) {
        throw "WSL command failed with exit code ${exitCode}: $Command"
    }
}

function Invoke-WslCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = wsl -d $Distro -- bash -lc "export CI=1 DOCKER_CLI_HINTS=false BUILDKIT_PROGRESS=plain; $Command" 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "WSL command failed with exit code ${exitCode}: $Command"
    }

    return (($output | ForEach-Object { "$_" }) -join "`n").Trim()
}

function Read-HttpExceptionResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $Exception = $ErrorRecord.Exception
    $response = $Exception.Response
    if ($null -eq $response) {
        return @{
            status = 0
            body = if ($null -ne $ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) { $ErrorRecord.ErrorDetails.Message } else { $Exception.Message }
        }
    }

    $status = 0
    try {
        if ($null -ne $response.StatusCode) {
            $status = [int]$response.StatusCode
        }
    } catch {
        $status = 0
    }

    $body = $null
    if ($null -ne $ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $body = $ErrorRecord.ErrorDetails.Message
    }

    try {
        if ([string]::IsNullOrWhiteSpace($body) -and $null -ne $response.Content -and $response.Content.PSObject.Methods.Name -contains "ReadAsStringAsync") {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
    } catch {
        $body = $null
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        try {
            $stream = $response.GetResponseStream()
            if ($null -ne $stream) {
                $reader = [System.IO.StreamReader]::new($stream)
                try {
                    $body = $reader.ReadToEnd()
                } finally {
                    $reader.Dispose()
                }
            }
        } catch {
            $body = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        $body = $Exception.Message
    }

    return @{
        status = $status
        body = ($body | Out-String).Trim()
    }
}

function Test-DbVersionTooNewHealth {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    if ([string]::IsNullOrWhiteSpace($Result.body)) {
        return $null
    }

    try {
        $health = $Result.body | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }

    if ($health.error -ne "db_version_too_new") {
        return $null
    }

    return $health
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
        $failure = Read-HttpExceptionResponse -ErrorRecord $_
        return @{
            ok = $false
            status = $failure.status
            body = $failure.body
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
        $dbVersionTooNew = Test-DbVersionTooNewHealth -Result $result
        if ($null -ne $dbVersionTooNew) {
            throw ("{0} HTTP check returned db_version_too_new: foundDbVersion={1} supportedDbVersion={2} profile={3} body={4}" -f $Name, $dbVersionTooNew.foundDbVersion, $dbVersionTooNew.supportedDbVersion, $dbVersionTooNew.profile, $result.body)
        }
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

function Get-BuildInfoUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebHealthUrl
    )

    $builder = [System.UriBuilder]::new([System.Uri]$WebHealthUrl)
    $builder.Path = "/build-info.json"
    $builder.Query = $null
    $builder.Fragment = $null
    return $builder.Uri.AbsoluteUri
}

function Assert-ServedProfileMatches {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebHealthUrl,
        [Parameter(Mandatory = $true)]
        [ValidateSet("full", "slim")]
        [string]$Profile
    )

    $url = Get-BuildInfoUrl -WebHealthUrl $WebHealthUrl
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
    $info = $response.Content | ConvertFrom-Json
    $servedProfile = [string]$info.profile
    Write-Host ("Served profile: expected={0} served={1}" -f $Profile, $servedProfile)
    if ($servedProfile -ne $Profile) {
        throw "Served build profile mismatch. expected=${Profile}; served=${servedProfile}; url=${url}"
    }
}

function Get-Sha256Text {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Get-FirstJsonLine {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("{") -or $trimmed.StartsWith("[")) {
            return $trimmed
        }
    }

    return $null
}

function ConvertTo-OrderedJson {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    return ($Value | ConvertTo-Json -Depth 20 -Compress)
}

function Convert-EnvListToMap {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $EnvList
    )

    $map = @{}
    foreach ($entry in @($EnvList)) {
        $text = [string]$entry
        $separator = $text.IndexOf("=")
        if ($separator -lt 0) {
            continue
        }

        $key = $text.Substring(0, $separator)
        $value = $text.Substring($separator + 1)
        $map[$key] = $value
    }

    return $map
}

function Get-EnvMapValue {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($Map.ContainsKey($Key)) {
        return [string]$Map[$Key]
    }

    return ""
}

function Get-DockerInspectJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        [Parameter(Mandatory = $true)]
        [string]$Format
    )

    $command = "docker inspect " + (Quote-BashArg $ContainerName) + " --format " + (Quote-BashArg $Format) + " 2>/dev/null || true"
    $text = Invoke-WslCapture $command
    return Get-FirstJsonLine -Text $text
}

function Get-NormalizedDockerMounts {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return ""
    }

    $mounts = $Json | ConvertFrom-Json
    $lines = @(
        foreach ($mount in @($mounts)) {
            "{0}|{1}|{2}|{3}" -f [string]$mount.Source, [string]$mount.Destination, [bool]$mount.RW, [string]$mount.Type
        }
    ) | Sort-Object

    return ($lines -join "`n")
}

function Get-NormalizedDockerPortBindings {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return ""
    }

    $bindings = $Json | ConvertFrom-Json
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($containerPort in @($bindings.PSObject.Properties.Name | Sort-Object)) {
        $entries = @($bindings.$containerPort)
        foreach ($entry in ($entries | Sort-Object HostIp, HostPort)) {
            $lines.Add(("{0}={1}:{2}" -f $containerPort, [string]$entry.HostIp, [string]$entry.HostPort))
        }
    }

    return ($lines -join "`n")
}

function Get-NormalizedProxyRuntimeEnv {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return ""
    }

    $envList = $Json | ConvertFrom-Json
    $envMap = Convert-EnvListToMap -EnvList $envList
    $keys = @(
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "no_proxy",
        "CC_SWITCH_START_PROXY",
        "CC_SWITCH_HOST",
        "CC_SWITCH_PORT",
        "CC_SWITCH_AUTO_PORT",
        "CC_SWITCH_ALLOW_EXTENSION_SESSION_HEADER"
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($keys | Sort-Object)) {
        $lines.Add(("{0}={1}" -f $key, (Get-EnvMapValue -Map $envMap -Key $key)))
    }

    return ($lines -join "`n")
}

function Get-StableProxyStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TcpHost,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [int]$Attempts = 1,
        [int]$DelaySeconds = 1
    )

    $url = "http://${TcpHost}:${Port}/status"
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
            $status = $response.Content | ConvertFrom-Json
            return ConvertTo-OrderedJson -Value ([ordered]@{
                running = [bool]$status.running
                address = [string]$status.address
                port = [int]$status.port
                current_provider_id = [string]$status.current_provider_id
                current_provider = [string]$status.current_provider
            })
        } catch {
            if ($attempt -lt $Attempts) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }

    return $null
}

function Wait-ProxyStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TcpHost,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $attempts = [Math]::Max($HealthRetries, 36)
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $status = Get-StableProxyStatus -TcpHost $TcpHost -Port $Port
        $statusHash = if ($null -eq $status) { "<unavailable>" } else { Get-Sha256Text -Text $status }
        Write-Host ("{0}: attempt {1}/{2}: status={3}" -f $Name, $attempt, $attempts, $statusHash)
        if ($null -ne $status) {
            return $status
        }

        if ($attempt -lt $attempts) {
            Start-Sleep -Seconds $HealthDelaySeconds
        }
    }

    throw "$Name check failed after $attempts attempts: http://${TcpHost}:${Port}/status"
}

function Get-PersistentProxyConfigHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    $safeContainer = ($ContainerName -replace '[^A-Za-z0-9_.-]', '-')
    $stamp = [System.Guid]::NewGuid().ToString("N")
    $containerDbCopy = "/tmp/cc-switch-config-${stamp}.db"
    $hostDbCopy = "/tmp/cc-switch-config-${safeContainer}-${stamp}.db"
    $localPythonScript = Join-Path ([System.IO.Path]::GetTempPath()) "cc-switch-config-${safeContainer}-${stamp}.py"

    try {
        Invoke-WslCapture ("docker exec " + (Quote-BashArg $ContainerName) + " sh -c " + (Quote-BashArg ("cp /root/.cc-switch/cc-switch.db $containerDbCopy"))) | Out-Null
        Invoke-WslCapture ("docker cp " + (Quote-BashArg "${ContainerName}:$containerDbCopy") + " " + (Quote-BashArg $hostDbCopy)) | Out-Null
        $settingsHashText = Invoke-WslCapture ("docker exec " + (Quote-BashArg $ContainerName) + " sh -c " + (Quote-BashArg "sha256sum /root/.cc-switch/settings.json 2>/dev/null || true"))
        $settingsHash = ""
        foreach ($line in ($settingsHashText -split "`r?`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^[0-9a-fA-F]{64}\b') {
                $settingsHash = $Matches[0].ToLowerInvariant()
                break
            }
        }

        $python = @"
import hashlib, json, sqlite3, sys
db_path = sys.argv[1]
settings_hash = sys.argv[2]
con = sqlite3.connect(db_path)
con.row_factory = sqlite3.Row

def rows(table, order_by):
    cols = [row[1] for row in con.execute(f"pragma table_info({table})")]
    return [
        {col: row[col] for col in cols}
        for row in con.execute(f"select * from {table} order by {order_by}")
    ]

payload = {
    "settings_json_sha256": settings_hash,
    "providers": rows("providers", "app_type, id, name"),
    "settings": rows("settings", "key"),
}
text = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
print(hashlib.sha256(text.encode("utf-8")).hexdigest())
"@
        [System.IO.File]::WriteAllText($localPythonScript, $python, [System.Text.Encoding]::UTF8)
        $localPythonScriptWsl = ConvertTo-WslPath -WindowsPath $localPythonScript
        $hashText = Invoke-WslCapture ("python3 " + (Quote-BashArg $localPythonScriptWsl) + " " + (Quote-BashArg $hostDbCopy) + " " + (Quote-BashArg $settingsHash))
        foreach ($line in ($hashText -split "`r?`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^[0-9a-fA-F]{64}$') {
                return $trimmed.ToLowerInvariant()
            }
        }

        throw "Persistent proxy config hash command did not return a SHA256 hash."
    } finally {
        try {
            Invoke-WslCapture ("docker exec " + (Quote-BashArg $ContainerName) + " rm -f " + (Quote-BashArg $containerDbCopy) + " 2>/dev/null || true") | Out-Null
        } catch {
        }
        try {
            Invoke-WslCapture ("rm -f " + (Quote-BashArg $hostDbCopy) + " 2>/dev/null || true") | Out-Null
        } catch {
        }
        try {
            if (Test-Path -LiteralPath $localPythonScript) {
                Remove-Item -LiteralPath $localPythonScript -Force
            }
        } catch {
        }
    }
}

function Get-LocalUpgradeProtectionSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        [Parameter(Mandatory = $true)]
        [string]$ProxyHost,
        [Parameter(Mandatory = $true)]
        [int]$ProxyPort,
        [int]$ProxyStatusAttempts = 1,
        [int]$ProxyStatusDelaySeconds = 1
    )

    $mountsJson = Get-DockerInspectJson -ContainerName $ContainerName -Format "{{json .Mounts}}"
    $portsJson = Get-DockerInspectJson -ContainerName $ContainerName -Format "{{json .HostConfig.PortBindings}}"
    $envJson = Get-DockerInspectJson -ContainerName $ContainerName -Format "{{json .Config.Env}}"
    $exists = -not ([string]::IsNullOrWhiteSpace($mountsJson) -and [string]::IsNullOrWhiteSpace($portsJson) -and [string]::IsNullOrWhiteSpace($envJson))

    $mounts = Get-NormalizedDockerMounts -Json $mountsJson
    $ports = Get-NormalizedDockerPortBindings -Json $portsJson
    $proxyEnv = Get-NormalizedProxyRuntimeEnv -Json $envJson
    $proxyStatus = Get-StableProxyStatus -TcpHost $ProxyHost -Port $ProxyPort -Attempts $ProxyStatusAttempts -DelaySeconds $ProxyStatusDelaySeconds
    $persistentConfigHash = if ($exists) { Get-PersistentProxyConfigHash -ContainerName $ContainerName } else { "<missing>" }

    return [ordered]@{
        exists = $exists
        mounts = $mounts
        ports = $ports
        proxy_env = $proxyEnv
        proxy_status = $proxyStatus
        persistent_config_hash = $persistentConfigHash
        mounts_hash = Get-Sha256Text -Text $mounts
        ports_hash = Get-Sha256Text -Text $ports
        proxy_env_hash = Get-Sha256Text -Text $proxyEnv
        proxy_status_hash = if ($null -eq $proxyStatus) { "<unavailable>" } else { Get-Sha256Text -Text $proxyStatus }
    }
}

function Write-LocalUpgradeProtectionSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [hashtable]$Snapshot
    )

    Write-Host ("{0}: exists={1} mounts={2} ports={3} proxy_env={4} persistent_config={5} proxy_status={6}" -f $Name, $Snapshot.exists, $Snapshot.mounts_hash, $Snapshot.ports_hash, $Snapshot.proxy_env_hash, $Snapshot.persistent_config_hash, $Snapshot.proxy_status_hash)
}

function Assert-LocalUpgradePreservedConfig {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Before,
        [Parameter(Mandatory = $true)]
        [hashtable]$After
    )

    if (-not [bool]$Before.exists) {
        Write-Host "No existing local CCS container was found before publish; config preservation comparison is skipped."
        return
    }

    if (-not [bool]$After.exists) {
        throw "Local CCS upgrade did not recreate the expected container; refusing to treat this as a config-preserving upgrade."
    }

    if ($Before.mounts -ne $After.mounts) {
        throw "Local CCS upgrade changed persistent mounts. This path may replace user configuration and is not allowed."
    }

    if ($Before.ports -ne $After.ports) {
        throw "Local CCS upgrade changed published port bindings. This path may change proxy exposure and is not allowed."
    }

    if ($Before.proxy_env -ne $After.proxy_env) {
        throw "Local CCS upgrade changed proxy-related runtime environment. This path may change proxy behavior and is not allowed."
    }

    if ($Before.persistent_config_hash -ne $After.persistent_config_hash) {
        throw "Local CCS upgrade changed persistent proxy/provider configuration. This path may change user configuration and is not allowed."
    }

    if ($null -eq $After.proxy_status) {
        throw "Local CCS proxy status is not reachable after publish."
    }

    if ($null -eq $Before.proxy_status) {
        Write-Host "Proxy status was not reachable before publish; post-publish proxy reachability was verified."
    }
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

function Assert-SlimPublishAuthBoundary {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$LocalComposePath,
        [Parameter(Mandatory = $true)]
        [ValidateSet("full", "slim")]
        [string]$Profile
    )

    if ($Profile -ne "slim") {
        return
    }

    if ($env:CCS_WEB_SLIM_ALLOW_NO_AUTH) {
        throw "CCS_WEB_SLIM_ALLOW_NO_AUTH is not allowed when publishing -Profile slim."
    }

    if (-not [string]::IsNullOrWhiteSpace($LocalComposePath) -and (Test-Path -LiteralPath $LocalComposePath -PathType Leaf)) {
        $localCompose = Get-Content -LiteralPath $LocalComposePath -Encoding UTF8 -Raw
        if ($localCompose -match 'CCS_WEB_SLIM_ALLOW_NO_AUTH') {
            throw "Local compose overlay must not set CCS_WEB_SLIM_ALLOW_NO_AUTH for -Profile slim: $LocalComposePath"
        }
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
        [string]$ProjectRoot,
        [ValidateSet("full", "slim")]
        [string]$Profile = "full"
    )

    $buildCacheRoot = Resolve-LocalRunPath -ProjectRoot $ProjectRoot -RelativePath ".run/build-cache"
    $metaRoot = Join-Path $buildCacheRoot "meta"
    $profileCacheRoot = Join-Path $buildCacheRoot $Profile

    $layout = [ordered]@{
        BuildCacheRoot = $buildCacheRoot
        ProfileCacheRoot = $profileCacheRoot
        FrontendDist = Join-Path $profileCacheRoot "frontend-dist"
        DockerCache = Join-Path $profileCacheRoot "docker"
        MetaRoot = $metaRoot
        FrontendFingerprint = Join-Path $metaRoot "frontend-dist.$Profile.fingerprint"
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
        [string]$ScriptRoot,
        [ValidateSet("full", "slim")]
        [string]$Profile = "full"
    )

    $fingerprintScript = Join-Path $ScriptRoot "get-local-wsl-publish-fingerprint.ps1"
    if (-not (Test-Path -LiteralPath $fingerprintScript)) {
        throw "Fingerprint script not found: $fingerprintScript"
    }

    $fingerprint = powershell -NoProfile -ExecutionPolicy Bypass -File $fingerprintScript -ProjectRoot $ProjectRoot -Profile $Profile
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
        [ValidateSet("full", "slim")]
        [string]$Profile = "full",
        [switch]$SkipFrontendBuild,
        [switch]$NoCache
    )

    $snapshotIndexPath = Join-Path $CacheLayout.FrontendDist "index.html"
    $currentFingerprint = Get-FrontendFingerprint -ProjectRoot $ProjectRoot -ScriptRoot $ScriptRoot -Profile $Profile
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

function Get-WslBuildContextPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $rootName = Split-Path -Leaf $ProjectRoot
    $sanitized = ($rootName -replace '[^A-Za-z0-9_.-]', '-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        $sanitized = "ccs-gateway-web"
    }

    return "/tmp/${sanitized}-docker-context"
}

function Sync-WslBuildContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRootWsl,
        [Parameter(Mandatory = $true)]
        [string]$BuildContextWsl
    )

    if (-not ($BuildContextWsl.StartsWith("/tmp/") -and $BuildContextWsl.EndsWith("-docker-context"))) {
        throw "Refusing unsafe Docker build context path: $BuildContextWsl"
    }

    $source = (Quote-BashArg ($ProjectRootWsl.TrimEnd("/") + "/"))
    $dest = Quote-BashArg ($BuildContextWsl.TrimEnd("/") + "/")
    $context = Quote-BashArg $BuildContextWsl
    $syncNext = Quote-BashArg ($BuildContextWsl.TrimEnd("/") + "/.sync-next")
    $excludePatterns = @(
        ".git",
        "node_modules",
        ".pnpm-store",
        ".codex",
        ".learnings",
        ".serena",
        ".run",
        ".upstream",
        ".worktrees",
        "tmp",
        "dist",
        "target",
        "src-tauri/target",
        "crates/*/target"
    )
    $excludes = $excludePatterns | ForEach-Object { "--exclude=" + (Quote-BashArg $_) }
    $excludeArgs = $excludes -join " "
    $tarExcludes = $excludePatterns | ForEach-Object { "--exclude=" + (Quote-BashArg $_) }
    $tarExcludeArgs = $tarExcludes -join " "
    $command = "set -euo pipefail; mkdir -p $context; if command -v rsync >/dev/null 2>&1; then rsync -a --delete $excludeArgs $source $dest; else echo rsync not found in WSL, falling back to tar-based context sync; rm -rf $syncNext; mkdir -p $syncNext; (cd $source && tar $tarExcludeArgs -cf - .) | (cd $syncNext && tar -xf -); find $context -mindepth 1 -maxdepth 1 ! -name .sync-next -exec rm -rf {} +; find $syncNext -mindepth 1 -maxdepth 1 -exec mv -t $context {} +; rmdir $syncNext; fi"
    Invoke-Wsl $command
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
        [string]$BuildContextWsl,
        [Parameter(Mandatory = $true)]
        [string]$ComposeFile,
        [Parameter(Mandatory = $true)]
        [string]$Service,
        [Parameter(Mandatory = $true)]
        [string]$DockerCacheWsl,
        [Parameter(Mandatory = $true)]
        [string]$BuilderName,
        [ValidateSet("full", "slim")]
        [string]$Profile = "full",
        [string]$ProxyUrl,
        [switch]$NoCache
    )

    $proxyPrefix = ""
    $proxyArgs = " --set " + (Quote-BashArg "${Service}.args.CCS_WEB_PROFILE=$Profile")
    if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
        $proxyArg = Quote-BashArg $ProxyUrl
        $proxyPrefix = "HTTP_PROXY=$proxyArg HTTPS_PROXY=$proxyArg http_proxy=$proxyArg https_proxy=$proxyArg "
        $proxyArgs += " --set " + (Quote-BashArg "${Service}.args.HTTP_PROXY=$ProxyUrl") + " --set " + (Quote-BashArg "${Service}.args.HTTPS_PROXY=$ProxyUrl") + " --set " + (Quote-BashArg "${Service}.args.http_proxy=$ProxyUrl") + " --set " + (Quote-BashArg "${Service}.args.https_proxy=$ProxyUrl")
    }

    if ($env:CCS_WEB_NODE_IMAGE) {
        $proxyArgs += " --set " + (Quote-BashArg "${Service}.args.NODE_IMAGE=$($env:CCS_WEB_NODE_IMAGE)")
    }
    if ($env:CCS_WEB_RUST_IMAGE) {
        $proxyArgs += " --set " + (Quote-BashArg "${Service}.args.RUST_IMAGE=$($env:CCS_WEB_RUST_IMAGE)")
    }
    if ($env:CCS_WEB_DEBIAN_IMAGE) {
        $proxyArgs += " --set " + (Quote-BashArg "${Service}.args.DEBIAN_IMAGE=$($env:CCS_WEB_DEBIAN_IMAGE)")
    }

    $command = "cd " + (Quote-BashArg $BuildContextWsl) + " && ${proxyPrefix}DOCKER_BUILDKIT=1 docker buildx bake --pull=false --builder " + (Quote-BashArg $BuilderName) + " --file " + (Quote-BashArg $ComposeFile) + " " + (Quote-BashArg $Service) + " --load --set " + (Quote-BashArg "${Service}.context=$BuildContextWsl") + " --set " + (Quote-BashArg "${Service}.cache-from=type=local,src=$DockerCacheWsl") + " --set " + (Quote-BashArg "${Service}.cache-to=type=local,dest=$DockerCacheWsl,mode=max") + $proxyArgs
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
        [ValidateSet("full", "slim")]
        [string]$Profile = "full",
        [string]$ProxyUrl,
        [switch]$NoCache
    )

    $frontendDistWsl = ConvertTo-WslPath -WindowsPath $FrontendDistPath
    if (Test-Path -LiteralPath $FrontendDistPath) {
        Remove-Item -LiteralPath $FrontendDistPath -Recurse -Force
    }
    Ensure-Directory -Path $FrontendDistPath

    $proxyPrefix = ""
    $proxyArgs = " --build-arg CCS_WEB_PROFILE=" + (Quote-BashArg $Profile)
    if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
        $proxyArg = Quote-BashArg $ProxyUrl
        $proxyPrefix = "HTTP_PROXY=$proxyArg HTTPS_PROXY=$proxyArg http_proxy=$proxyArg https_proxy=$proxyArg "
        $proxyArgs += " --build-arg HTTP_PROXY=$proxyArg --build-arg HTTPS_PROXY=$proxyArg --build-arg http_proxy=$proxyArg --build-arg https_proxy=$proxyArg"
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
if (-not $RepairRelay) {
    if ([string]::IsNullOrWhiteSpace($LocalComposeFile)) {
        throw "Local compose override is required for local WSL publishing. Pass -LocalComposeFile or restore docker-compose.ccs-web.local.yml."
    }
    if (-not (Test-Path -LiteralPath $localComposePath -PathType Leaf)) {
        throw "Local compose override is required for local WSL publishing but was not found: $localComposePath"
    }
}
if ($localComposePath -and (Test-Path -LiteralPath $localComposePath -PathType Leaf)) {
    $composeFiles.Add($LocalComposeFile)
}
Assert-SlimPublishAuthBoundary -LocalComposePath $localComposePath -Profile $Profile

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
$cacheLayout = Get-LocalPublishCacheLayout -ProjectRoot $projectRoot -Profile $Profile
$dockerCacheWsl = ConvertTo-WslPath -WindowsPath $cacheLayout.DockerCache
$builderName = Get-DockerBuildxBuilderName -ProjectRoot $projectRoot
$buildContextWsl = Get-WslBuildContextPath -ProjectRoot $projectRoot
$autoBuildProxyUrl = $null
New-Item -ItemType Directory -Force -Path $resolvedLogDir | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $resolvedLogDir "publish-local-wsl-ccs-web-$timestamp.log"
$preUpgradeSnapshot = $null
$postUpgradeSnapshot = $null

try {
    Start-Transcript -LiteralPath $logPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Step "Preflight"
    Write-Host "Distro:          $Distro"
    Write-Host "Compose file:    $ComposeFile"
    Write-Host "Local compose:   $LocalComposeFile"
    Write-Host "Service:         $Service"
    Write-Host "Container:       $ContainerName"
    Write-Host "Image:           $Image"
    Write-Host "Profile:         $Profile"
    Write-Host "Web URL:         $WebHealthUrl"
    Write-Host "API health URL:  $ApiHealthUrl"
    Write-Host "Proxy TCP:       ${ProxyHost}:${ProxyPort}"
    Write-Host "Stop timeout:    ${StopTimeoutSeconds}s"
    Write-Host "WSL shutdown on stale relay: $ForceWslShutdownOnStaleRelay"
    Write-Host "Log file:        $logPath"
    Write-Host "Build cache:     $($cacheLayout.BuildCacheRoot)"
    Write-Host "Docker cache:    $($cacheLayout.DockerCache)"
    Write-Host "Build context:   $buildContextWsl"
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
    $preUpgradeSnapshot = Get-LocalUpgradeProtectionSnapshot -ContainerName $ContainerName -ProxyHost $ProxyHost -ProxyPort $ProxyPort
    Write-LocalUpgradeProtectionSnapshot -Name "Initial protection snapshot" -Snapshot $preUpgradeSnapshot

    $frontendSnapshot = Ensure-DockerFrontendSnapshot -ProjectRoot $projectRoot -ScriptRoot $scriptRoot -CacheLayout $cacheLayout -Profile $Profile -SkipFrontendBuild:$SkipFrontendBuild -NoCache:$NoCache
    $snapshotIndexPath = $frontendSnapshot.IndexPath

    if ($SkipBuild -and ($frontendSnapshot.NeedsRefresh -or (-not (Test-Path -LiteralPath $snapshotIndexPath -PathType Leaf)))) {
        throw "Docker frontend snapshot is stale or missing, but -SkipBuild was specified. Run without -SkipBuild to rebuild the image and refresh the snapshot."
    }

    if (-not $SkipBuild) {
        Write-Step "Syncing WSL-local Docker build context"
        Sync-WslBuildContext -ProjectRootWsl $projectRootWsl -BuildContextWsl $buildContextWsl

        Write-Step "Building local image"
        Ensure-DockerBuildxBuilder -BuilderName $builderName -ProxyUrl $autoBuildProxyUrl
        Invoke-DockerComposeBuildWithCache -ProjectRootWsl $projectRootWsl -BuildContextWsl $buildContextWsl -ComposeFile $ComposeFile -Service $Service -DockerCacheWsl $dockerCacheWsl -BuilderName $builderName -Profile $Profile -ProxyUrl $autoBuildProxyUrl -NoCache:$NoCache

        $command = "docker image inspect " + (Quote-BashArg $Image) + " --format " + (Quote-BashArg "image={{.Id}} created={{.Created}} size={{.Size}}")
        Invoke-Wsl $command
    } else {
        Write-Step "Skipping build"
    }

    if ($frontendSnapshot.NeedsRefresh -or (-not (Test-Path -LiteralPath $snapshotIndexPath -PathType Leaf))) {
        Write-Step "Exporting Docker frontend dist snapshot"
        Ensure-DockerBuildxBuilder -BuilderName $builderName -ProxyUrl $autoBuildProxyUrl
        $snapshotIndexPath = Export-DockerFrontendDistWithCache -ProjectRoot $projectRoot -ProjectRootWsl $projectRootWsl -DockerCacheWsl $dockerCacheWsl -BuilderName $builderName -FrontendDistPath $cacheLayout.FrontendDist -Profile $Profile -ProxyUrl $autoBuildProxyUrl -NoCache:$NoCache
        Set-StoredFrontendFingerprint -FingerprintPath $cacheLayout.FrontendFingerprint -Fingerprint $frontendSnapshot.Fingerprint
    }

    if (-not $NoStart) {
        $publishedPorts = @($ProxyPort, 17666) | Sort-Object -Unique
        $composeArgString = " -f " + (Quote-BashArg $ComposeFile)
        $profileEnvPrefix = "CCS_WEB_PROFILE=" + (Quote-BashArg $Profile) + " "
        if ($composeFiles.Count -gt 1) {
            $localComposeWsl = ConvertTo-WslPath -WindowsPath $localComposePath
            $composeArgString += " -f " + (Quote-BashArg $localComposeWsl)
        }

        Write-Step "Pre-stop protection snapshot"
        $preUpgradeSnapshot = Get-LocalUpgradeProtectionSnapshot -ContainerName $ContainerName -ProxyHost $ProxyHost -ProxyPort $ProxyPort -ProxyStatusAttempts $HealthRetries -ProxyStatusDelaySeconds $HealthDelaySeconds
        Write-LocalUpgradeProtectionSnapshot -Name "Pre-stop protection snapshot" -Snapshot $preUpgradeSnapshot

        Write-Step "Stopping existing local WSL container"
        Write-WindowsTcpConnectionsForPorts -Ports $publishedPorts -Name "Before stop"
        $command = "cd " + (Quote-BashArg $projectRootWsl) + " && ${profileEnvPrefix}docker compose$composeArgString stop -t $StopTimeoutSeconds " + (Quote-BashArg $Service) + " || true"
        Invoke-Wsl $command
        $command = "cd " + (Quote-BashArg $projectRootWsl) + " && ${profileEnvPrefix}docker compose$composeArgString rm -f " + (Quote-BashArg $Service) + " || true"
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
        $command = "cd " + (Quote-BashArg $projectRootWsl) + " && ${profileEnvPrefix}docker compose$composeArgString up -d --force-recreate --remove-orphans " + (Quote-BashArg $Service)
        Invoke-Wsl $command

        Write-Step "New container state"
        $command = "docker ps --filter " + (Quote-BashArg "name=^/${ContainerName}$") + " --format " + (Quote-BashArg "name={{.Names}} image={{.Image}} status={{.Status}} ports={{.Ports}}")
        Invoke-Wsl $command
        Write-WindowsTcpConnectionsForPorts -Ports $publishedPorts -Name "After start"
        $postUpgradeSnapshot = Get-LocalUpgradeProtectionSnapshot -ContainerName $ContainerName -ProxyHost $ProxyHost -ProxyPort $ProxyPort
        Write-LocalUpgradeProtectionSnapshot -Name "Post-upgrade protection snapshot" -Snapshot $postUpgradeSnapshot
    } else {
        Write-Step "Skipping container start"
    }

    if (-not $SkipHealthCheck -and -not $NoStart) {
        Write-Step "Health checks"
        Wait-Http -Url $WebHealthUrl -Name "Web UI" | Out-Null
        Wait-ApiHealth -Url $ApiHealthUrl -Name "API health" | Out-Null
        Wait-TcpPort -TcpHost $ProxyHost -Port $ProxyPort -Name "Proxy port" | Out-Null
        Wait-ProxyStatus -TcpHost $ProxyHost -Port $ProxyPort -Name "Proxy status" | Out-Null

        Write-Step "Served build check"
        Assert-ServedBuildMatchesDockerFrontendSnapshot -SnapshotIndexPath $snapshotIndexPath -Url $WebHealthUrl
        Assert-ServedProfileMatches -WebHealthUrl $WebHealthUrl -Profile $Profile
    }

    if (-not $NoStart) {
        Write-Step "Config preservation check"
        $proxyStatusRetries = [Math]::Max($HealthRetries, 36)
        $postUpgradeSnapshot = Get-LocalUpgradeProtectionSnapshot -ContainerName $ContainerName -ProxyHost $ProxyHost -ProxyPort $ProxyPort -ProxyStatusAttempts $proxyStatusRetries -ProxyStatusDelaySeconds $HealthDelaySeconds
        Write-LocalUpgradeProtectionSnapshot -Name "Post-upgrade protection snapshot" -Snapshot $postUpgradeSnapshot
        Assert-LocalUpgradePreservedConfig -Before $preUpgradeSnapshot -After $postUpgradeSnapshot
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
