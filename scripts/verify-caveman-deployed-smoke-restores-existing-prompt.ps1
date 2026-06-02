param(
    [string] $BaseUrl = "http://127.0.0.1:17666",
    [string] $App = "openclaw",
    [string] $OutputPath = ".run\caveman-deployed-smoke-restore\current.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$baseApiUrl = ("{0}/api" -f $BaseUrl.TrimEnd("/"))
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
$expectedOutputRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ".run\caveman-deployed-smoke-restore"))

if (-not $outputFullPath.StartsWith($expectedOutputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw ("-OutputPath must stay inside .run\caveman-deployed-smoke-restore: {0}" -f $OutputPath)
}

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
        -Uri "$baseApiUrl/invoke" `
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

function Get-PromptById {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Prompts,
        [Parameter(Mandatory = $true)]
        [string] $Id
    )

    $property = $Prompts.PSObject.Properties[$Id]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Copy-PromptObject {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Prompt
    )

    return ($Prompt | ConvertTo-Json -Depth 50 | ConvertFrom-Json)
}

function Get-EnabledPromptIds {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Prompts
    )

    $enabledIds = @()
    foreach ($id in @($Prompts.PSObject.Properties.Name)) {
        $prompt = Get-PromptById -Prompts $Prompts -Id $id
        if ($null -ne $prompt -and [bool] $prompt.enabled) {
            $enabledIds += $id
        }
    }

    return $enabledIds
}

function Test-StringSetEqual {
    param(
        [AllowEmptyCollection()]
        [string[]] $Left,
        [AllowEmptyCollection()]
        [string[]] $Right
    )

    $leftSorted = @($Left | Sort-Object)
    $rightSorted = @($Right | Sort-Object)

    if ($leftSorted.Count -ne $rightSorted.Count) {
        return $false
    }

    for ($index = 0; $index -lt $leftSorted.Count; $index++) {
        if ($leftSorted[$index] -ne $rightSorted[$index]) {
            return $false
        }
    }

    return $true
}

function Test-InitialStateCanBeRestored {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Prompts,
        [AllowNull()]
        [object] $LivePrompt
    )

    $liveText = [string] $LivePrompt
    if ([string]::IsNullOrEmpty($liveText)) {
        return $true
    }

    $enabledIds = @(Get-EnabledPromptIds -Prompts $Prompts)
    if ($enabledIds.Count -ne 1) {
        return $false
    }

    $enabledPrompt = Get-PromptById -Prompts $Prompts -Id $enabledIds[0]
    return (([string] $enabledPrompt.content) -eq $liveText)
}

function Restore-PromptState {
    param(
        [Parameter(Mandatory = $true)]
        [object] $InitialPrompts,
        [Parameter(Mandatory = $true)]
        [string] $TargetApp
    )

    $initialIds = @($InitialPrompts.PSObject.Properties.Name)
    $currentPrompts = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $TargetApp }
    $currentIds = @($currentPrompts.PSObject.Properties.Name)

    foreach ($id in $currentIds) {
        if ($initialIds -contains $id) {
            continue
        }

        $currentPrompt = Get-PromptById -Prompts $currentPrompts -Id $id
        if ($null -eq $currentPrompt) {
            continue
        }

        if ([bool] $currentPrompt.enabled) {
            $disabledPrompt = Copy-PromptObject -Prompt $currentPrompt
            $disabledPrompt.enabled = $false
            Invoke-Ccs -Command "upsert_prompt" -Payload @{
                app = $TargetApp
                id = $id
                prompt = $disabledPrompt
            } | Out-Null
        }

        Invoke-Ccs -Command "delete_prompt" -Payload @{
            app = $TargetApp
            id = $id
        } | Out-Null
    }

    foreach ($id in $initialIds) {
        $initialPrompt = Copy-PromptObject -Prompt (Get-PromptById -Prompts $InitialPrompts -Id $id)
        Invoke-Ccs -Command "upsert_prompt" -Payload @{
            app = $TargetApp
            id = $id
            prompt = $initialPrompt
        } | Out-Null
    }
}

try {
    $null = Invoke-RestMethod -Uri $BaseUrl -Method Get
} catch {
    throw ("Deployed Web endpoint is not reachable: {0}" -f $BaseUrl)
}

$initialPrompts = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
$initialLive = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
$initialCanRestore = Test-InitialStateCanBeRestored -Prompts $initialPrompts -LivePrompt $initialLive

if (-not $initialCanRestore) {
    throw "Initial prompt state cannot be restored safely through the public API. Run this verifier against an isolated deployed test config."
}

$probeId = "caveman-restore-probe-normal"
$probeContent = "# Caveman deployed smoke restore probe`n`nThis normal prompt must survive the deployed Caveman smoke."
$probePrompt = [ordered] @{
    id = $probeId
    name = "Caveman restore probe normal prompt"
    content = $probeContent
    description = "Temporary prompt used to verify deployed Caveman smoke state restoration."
    enabled = $false
}

$baselineRestoredAfterSmoke = $false
$originalRestoredAfterProbe = $false

try {
    Invoke-Ccs -Command "upsert_prompt" -Payload @{
        app = $App
        id = $probeId
        prompt = $probePrompt
    } | Out-Null
    Invoke-Ccs -Command "enable_prompt" -Payload @{ app = $App; id = $probeId } | Out-Null

    $baselinePrompts = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $baselineLive = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    Assert-True -Condition ([string] $baselineLive -eq $probeContent) -Message "Probe prompt was not written to the live prompt before smoke"

    $smokeEvidencePath = ".run\caveman-deployed-smoke-restore\inner-smoke.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\verify-caveman-deployed-smoke.ps1") `
        -BaseUrl $BaseUrl `
        -App $App `
        -OutputPath $smokeEvidencePath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw ("verify-caveman-deployed-smoke.ps1 failed with exit code {0}" -f $LASTEXITCODE)
    }

    $afterSmokePrompts = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $afterSmokeLive = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    $afterSmokeEnabledIds = @(Get-EnabledPromptIds -Prompts $afterSmokePrompts)
    $baselineRestoredAfterSmoke = (
        (Test-StringSetEqual -Left @($afterSmokePrompts.PSObject.Properties.Name) -Right @($baselinePrompts.PSObject.Properties.Name)) -and
        (Test-StringSetEqual -Left $afterSmokeEnabledIds -Right @($probeId)) -and
        ([string] $afterSmokeLive -eq $probeContent)
    )
    Assert-True -Condition $baselineRestoredAfterSmoke -Message "Deployed smoke did not restore the pre-smoke normal prompt state"
} finally {
    Restore-PromptState -InitialPrompts $initialPrompts -TargetApp $App
}

$finalPrompts = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
$finalLive = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
$originalRestoredAfterProbe = (
    (Test-StringSetEqual -Left @($finalPrompts.PSObject.Properties.Name) -Right @($initialPrompts.PSObject.Properties.Name)) -and
    (Test-StringSetEqual -Left @(Get-EnabledPromptIds -Prompts $finalPrompts) -Right @(Get-EnabledPromptIds -Prompts $initialPrompts)) -and
    ([string] $finalLive -eq [string] $initialLive)
)
Assert-True -Condition $originalRestoredAfterProbe -Message "Original deployed prompt state was not restored after the restore probe"

New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($outputFullPath)) | Out-Null
$evidence = [ordered] @{
    schemaVersion = 1
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    target = "deployed-local-docker"
    webBaseUrl = $BaseUrl
    app = $App
    probePromptId = $probeId
    initialPromptIds = @($initialPrompts.PSObject.Properties.Name)
    initialEnabledPromptIds = @(Get-EnabledPromptIds -Prompts $initialPrompts)
    baselineRestoredAfterSmoke = $baselineRestoredAfterSmoke
    originalRestoredAfterProbe = $originalRestoredAfterProbe
    finalPromptIds = @($finalPrompts.PSObject.Properties.Name)
    finalEnabledPromptIds = @(Get-EnabledPromptIds -Prompts $finalPrompts)
}

$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputFullPath -Encoding UTF8
Write-Host "deployed_caveman_smoke_restore=passed"
Write-Host ("deployed_caveman_smoke_restore_evidence={0}" -f $outputFullPath)
