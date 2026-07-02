param()

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptRoot "..")

function Read-Text {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Encoding UTF8 -Raw
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle
    )
    if (-not $Text.Contains($Needle)) {
        throw "$Name is missing expected text: $Needle"
    }
}

$dockerfile = Read-Text "Dockerfile.web"
$compose = Read-Text "docker-compose.ccs-web.yml"
$publish = Read-Text "scripts/publish-local-wsl-ccs-web.ps1"
$fingerprint = Read-Text "scripts/get-local-wsl-publish-fingerprint.ps1"

Assert-Contains -Name "Dockerfile.web" -Text $dockerfile -Needle "ARG CCS_WEB_PROFILE=full"
Assert-Contains -Name "Dockerfile.web" -Text $dockerfile -Needle 'VITE_CCS_WEB_PROFILE=${CCS_WEB_PROFILE}'
Assert-Contains -Name "Dockerfile.web" -Text $dockerfile -Needle 'CCS_WEB_PROFILE=${CCS_WEB_PROFILE}'

Assert-Contains -Name "docker-compose.ccs-web.yml" -Text $compose -Needle 'CCS_WEB_PROFILE: ${CCS_WEB_PROFILE:-full}'

Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle '[ValidateSet("full", "slim")]'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle '${Service}.args.CCS_WEB_PROFILE=$Profile'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle '${Service}.context=$BuildContextWsl'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Slim profile publishing requires health and profile checks'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Assert-ServedProfileMatches -WebHealthUrl $WebHealthUrl -Profile $Profile'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'CCS_WEB_SLIM_ALLOW_NO_AUTH is not allowed when publishing -Profile slim.'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle "--build-arg CCS_WEB_PROFILE="
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle '$proxyArgs += " --set "'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle '$proxyArgs += " --build-arg HTTP_PROXY='
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'frontend-dist.$Profile.fingerprint'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'CCS_WEB_PROFILE=" + (Quote-BashArg $Profile)'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Read-HttpExceptionResponse'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Test-DbVersionTooNewHealth'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'db_version_too_new'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'foundDbVersion'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'supportedDbVersion'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'HTTP check returned db_version_too_new'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Get-LocalUpgradeProtectionSnapshot'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Write-LocalUpgradeProtectionSnapshot'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Assert-LocalUpgradePreservedConfig'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Initial protection snapshot'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Pre-stop protection snapshot'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Post-upgrade protection snapshot'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Config preservation check'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Local CCS upgrade changed proxy-related runtime environment'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Get-PersistentProxyConfigHash'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'persistent_config_hash'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Local CCS upgrade changed persistent proxy/provider configuration'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Local CCS proxy status is not reachable after publish.'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle '[int]$Attempts = 1'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'function Wait-ProxyStatus'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Wait-ProxyStatus -TcpHost $ProxyHost -Port $ProxyPort -Name "Proxy status"'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle '$proxyStatusRetries = [Math]::Max($HealthRetries, 36)'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle '-ProxyStatusAttempts $proxyStatusRetries -ProxyStatusDelaySeconds $HealthDelaySeconds'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Local CCS upgrade changed published port bindings'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Local CCS upgrade changed persistent mounts'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Local compose override is required for local WSL publishing'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle 'Write-Host "Local compose:   $LocalComposeFile"'
Assert-Contains -Name "publish-local-wsl-ccs-web.ps1" -Text $publish -Needle '"{0}|{1}|{2}|{3}" -f [string]$mount.Source, [string]$mount.Destination, [bool]$mount.RW, [string]$mount.Type'

Assert-Contains -Name "get-local-wsl-publish-fingerprint.ps1" -Text $fingerprint -Needle '[ValidateSet("full", "slim")]'
Assert-Contains -Name "get-local-wsl-publish-fingerprint.ps1" -Text $fingerprint -Needle 'profile=$Profile'

Write-Output "publish profile static checks passed"
