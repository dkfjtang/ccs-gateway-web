param(
    [int] $Port = 18779,
    [string] $App = "openclaw",
    [string] $TestHome = ".run\caveman-api-smoke",
    [int] $StartupTimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$testHomePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $TestHome))
New-Item -ItemType Directory -Force -Path $testHomePath | Out-Null

$cargo = (Get-Command cargo.exe -ErrorAction Stop).Source
$serverRoot = "http://127.0.0.1:$Port"
$baseUrl = "http://127.0.0.1:$Port/api"
$createdIds = New-Object System.Collections.Generic.List[string]

function Invoke-Ccs {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,
        [hashtable] $Payload = @{}
    )

    $body = @{
        command = $Command
        payload = $Payload
    } | ConvertTo-Json -Depth 50

    $response = Invoke-RestMethod `
        -Uri "$baseUrl/invoke" `
        -Method Post `
        -ContentType "application/json" `
        -Body $body

    $hasError = $response.PSObject.Properties.Name -contains "error"
    if ($hasError -and $null -ne $response.error) {
        throw ("{0}: {1}" -f $Command, $response.error)
    }

    $hasResult = $response.PSObject.Properties.Name -contains "result"
    if ($hasResult) {
        return $response.result
    }

    return $response
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool] $Condition,
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Test-LocalPortInUse {
    param(
        [Parameter(Mandatory = $true)]
        [int] $LocalPort
    )

    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), $LocalPort)
        $listener.Start()
        return $false
    } catch {
        return $true
    } finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

if (Test-LocalPortInUse -LocalPort $Port) {
    throw ("Caveman API smoke port is already in use before server start: 127.0.0.1:{0}" -f $Port)
}

$process = New-Object System.Diagnostics.Process
$process.StartInfo.FileName = $cargo
$process.StartInfo.WorkingDirectory = $repoRoot
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.Arguments = "run --quiet --manifest-path crates/server/Cargo.toml"
$process.StartInfo.Environment["CC_SWITCH_TEST_HOME"] = $testHomePath
$process.StartInfo.Environment["HOME"] = $testHomePath
$process.StartInfo.Environment["CC_SWITCH_PORT"] = [string] $Port
$process.StartInfo.Environment["CC_SWITCH_HOST"] = "127.0.0.1"
$process.StartInfo.Environment["CC_SWITCH_AUTO_PORT"] = "false"
$process.StartInfo.Environment["CC_SWITCH_START_PROXY"] = "false"

try {
    if (-not $process.Start()) {
        throw "Failed to start cc-switch server"
    }

    $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
    do {
        if ($process.HasExited) {
            throw ("Server exited before becoming healthy on {0}; exitCode={1}" -f $serverRoot, $process.ExitCode)
        }
        try {
            $null = Invoke-RestMethod -Uri "$serverRoot/health" -Method Get
            break
        } catch {
            Start-Sleep -Milliseconds 500
        }
    } while ((Get-Date) -lt $deadline)

    try {
        $null = Invoke-RestMethod -Uri "$serverRoot/health" -Method Get
    } catch {
        throw "Server did not become healthy on $serverRoot"
    }

    $configDir = Invoke-Ccs -Command "get_config_dir" -Payload @{ app = $App }
    Assert-True `
        -Condition ([string] $configDir).StartsWith($testHomePath, [System.StringComparison]::OrdinalIgnoreCase) `
        -Message ("Expected isolated config dir under {0}, got {1}" -f $testHomePath, $configDir)

    $initialPrompts = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    Assert-True `
        -Condition (($initialPrompts.PSObject.Properties | Measure-Object).Count -eq 0) `
        -Message "Smoke test requires an empty isolated prompt set"

    $fullId = Invoke-Ccs -Command "create_caveman_style_profile" -Payload @{
        app = $App
        profile = "full"
    }
    $createdIds.Add($fullId) | Out-Null

    $afterCreate = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    Assert-True -Condition ($afterCreate."caveman-full".enabled -eq $false) -Message "Caveman Full must be disabled immediately after creation"

    Invoke-Ccs -Command "enable_prompt" -Payload @{ app = $App; id = "caveman-full" } | Out-Null
    $afterEnableFull = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $liveAfterFull = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    Assert-True -Condition ($afterEnableFull."caveman-full".enabled -eq $true) -Message "Caveman Full was not enabled"
    Assert-True -Condition ([string] $liveAfterFull).Contains("Caveman Style Profile") -Message "Live prompt file does not contain Caveman content after enabling Full"

    $liteId = Invoke-Ccs -Command "create_caveman_style_profile" -Payload @{
        app = $App
        profile = "lite"
    }
    $createdIds.Add($liteId) | Out-Null

    Invoke-Ccs -Command "enable_prompt" -Payload @{ app = $App; id = "caveman-lite" } | Out-Null
    $afterEnableLite = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $liveAfterLite = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    Assert-True -Condition ($afterEnableLite."caveman-lite".enabled -eq $true) -Message "Caveman Lite was not enabled"
    Assert-True -Condition ($afterEnableLite."caveman-full".enabled -eq $false) -Message "Caveman Full remained enabled after switching to Lite"
    Assert-True -Condition ([string] $liveAfterLite).Contains("Mode: lite") -Message "Live prompt file does not contain Lite mode after switching"

    $ultraId = Invoke-Ccs -Command "create_caveman_style_profile" -Payload @{
        app = $App
        profile = "ultra"
    }
    $createdIds.Add($ultraId) | Out-Null

    Invoke-Ccs -Command "enable_prompt" -Payload @{ app = $App; id = "caveman-ultra" } | Out-Null
    $afterEnableUltra = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $liveAfterUltra = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    Assert-True -Condition ($afterEnableUltra."caveman-ultra".enabled -eq $true) -Message "Caveman Ultra was not enabled"
    Assert-True -Condition ($afterEnableUltra."caveman-lite".enabled -eq $false) -Message "Caveman Lite remained enabled after switching to Ultra"
    Assert-True -Condition ($afterEnableUltra."caveman-full".enabled -eq $false) -Message "Caveman Full remained enabled after switching to Ultra"
    Assert-True -Condition ([string] $liveAfterUltra).Contains("Mode: ultra") -Message "Live prompt file does not contain Ultra mode after switching"

    $ultraPrompt = $afterEnableUltra."caveman-ultra"
    $ultraPrompt.enabled = $false
    Invoke-Ccs -Command "upsert_prompt" -Payload @{
        app = $App
        id = "caveman-ultra"
        prompt = $ultraPrompt
    } | Out-Null

    $afterTurnOff = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $liveAfterTurnOff = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    Assert-True -Condition ($null -ne $afterTurnOff."caveman-ultra") -Message "Caveman Ultra preset was deleted when turning off"
    Assert-True -Condition ($afterTurnOff."caveman-ultra".enabled -eq $false) -Message "Caveman Ultra remained enabled after turn off"
    Assert-True -Condition ($afterTurnOff."caveman-lite".enabled -eq $false) -Message "Caveman Lite unexpectedly enabled after turn off"
    Assert-True -Condition ($afterTurnOff."caveman-full".enabled -eq $false) -Message "Caveman Full unexpectedly enabled after turn off"
    Assert-True -Condition ([string]::IsNullOrEmpty([string] $liveAfterTurnOff)) -Message "Live prompt file was not cleared after turn off"

    Write-Host "Caveman API smoke passed."
    Write-Host ("config_dir={0}" -f $configDir)
    Write-Host "created_full=caveman-full disabled_then_enabled=true"
    Write-Host "switch_to_lite=lite_enabled_full_disabled"
    Write-Host "switch_to_ultra=ultra_enabled_lite_full_disabled"
    Write-Host "turn_off=preset_retained_live_prompt_cleared"
} finally {
    foreach ($id in $createdIds) {
        try {
            Invoke-Ccs -Command "delete_prompt" -Payload @{ app = $App; id = $id } | Out-Null
        } catch {
            Write-Warning ("Failed to cleanup prompt {0}: {1}" -f $id, $_.Exception.Message)
        }
    }

    if (-not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit()
    }
}
