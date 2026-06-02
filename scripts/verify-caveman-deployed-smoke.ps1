param(
    [string] $BaseUrl = "http://127.0.0.1:17666",
    [string] $App = "openclaw",
    [string] $OutputPath = ".run\caveman-deployed-smoke\current.json",
    [bool] $RestoreInitialState = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$baseApiUrl = ("{0}/api" -f $BaseUrl.TrimEnd("/"))
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
$expectedOutputRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ".run\caveman-deployed-smoke"))

if (-not $outputFullPath.StartsWith($expectedOutputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw ("-OutputPath must stay inside .run\caveman-deployed-smoke: {0}" -f $OutputPath)
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
$initialStateCanBeRestored = Test-InitialStateCanBeRestored -Prompts $initialPrompts -LivePrompt $initialLive

if ($RestoreInitialState -and -not $initialStateCanBeRestored) {
    throw "Initial prompt state has non-empty live prompt content that cannot be restored safely through the public API. Run this smoke against an isolated deployed test config or set -RestoreInitialState `$false only if state mutation is acceptable."
}

$stateRestored = $false
try {
    $fullId = Invoke-Ccs -Command "create_caveman_style_profile" -Payload @{
        app = $App
        profile = "full"
    }
    $afterCreateFull = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    Assert-True -Condition ($null -ne $afterCreateFull."caveman-full") -Message "Caveman Full was not created"
    Assert-True -Condition ($afterCreateFull."caveman-full".enabled -eq $false) -Message "Caveman Full should be disabled immediately after creation"

    Invoke-Ccs -Command "enable_prompt" -Payload @{ app = $App; id = "caveman-full" } | Out-Null
    $afterFull = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $liveFull = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    $fullEnabled = [bool] $afterFull."caveman-full".enabled
    $fullLivePromptContainsCaveman = ([string] $liveFull).Contains("Caveman Style Profile")
    Assert-True -Condition $fullEnabled -Message "Caveman Full was not enabled"
    Assert-True -Condition $fullLivePromptContainsCaveman -Message "Live prompt did not contain Caveman content after Full"

    $liteId = Invoke-Ccs -Command "create_caveman_style_profile" -Payload @{
        app = $App
        profile = "lite"
    }
    Invoke-Ccs -Command "enable_prompt" -Payload @{ app = $App; id = "caveman-lite" } | Out-Null
    $afterLite = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $liveLite = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    $liteEnabled = [bool] $afterLite."caveman-lite".enabled
    $liteDisabledFull = -not [bool] $afterLite."caveman-full".enabled
    $liteLivePromptContainsModeLite = ([string] $liveLite).Contains("Mode: lite")
    Assert-True -Condition $liteEnabled -Message "Caveman Lite was not enabled"
    Assert-True -Condition $liteDisabledFull -Message "Caveman Full remained enabled after Lite"
    Assert-True -Condition $liteLivePromptContainsModeLite -Message "Live prompt did not contain Lite mode"

    $ultraId = Invoke-Ccs -Command "create_caveman_style_profile" -Payload @{
        app = $App
        profile = "ultra"
    }
    Invoke-Ccs -Command "enable_prompt" -Payload @{ app = $App; id = "caveman-ultra" } | Out-Null
    $afterUltra = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $liveUltra = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    $ultraEnabled = [bool] $afterUltra."caveman-ultra".enabled
    $ultraDisabledLite = -not [bool] $afterUltra."caveman-lite".enabled
    $ultraDisabledFull = -not [bool] $afterUltra."caveman-full".enabled
    $ultraLivePromptContainsModeUltra = ([string] $liveUltra).Contains("Mode: ultra")
    Assert-True -Condition $ultraEnabled -Message "Caveman Ultra was not enabled"
    Assert-True -Condition $ultraDisabledLite -Message "Caveman Lite remained enabled after Ultra"
    Assert-True -Condition $ultraDisabledFull -Message "Caveman Full remained enabled after Ultra"
    Assert-True -Condition $ultraLivePromptContainsModeUltra -Message "Live prompt did not contain Ultra mode"

    $ultraPrompt = $afterUltra."caveman-ultra" | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $ultraPrompt.enabled = $false
    Invoke-Ccs -Command "upsert_prompt" -Payload @{
        app = $App
        id = "caveman-ultra"
        prompt = $ultraPrompt
    } | Out-Null

    $afterOff = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    $liveOff = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
    $turnOffRetainedProfiles = (($null -ne $afterOff."caveman-full") -and ($null -ne $afterOff."caveman-lite") -and ($null -ne $afterOff."caveman-ultra"))
    $turnOffDisabledAll = ((-not [bool] $afterOff."caveman-full".enabled) -and (-not [bool] $afterOff."caveman-lite".enabled) -and (-not [bool] $afterOff."caveman-ultra".enabled))
    $turnOffClearedLive = [string]::IsNullOrEmpty([string] $liveOff)
    Assert-True -Condition $turnOffRetainedProfiles -Message "Caveman profiles were not retained after turn off"
    Assert-True -Condition $turnOffDisabledAll -Message "Some Caveman profiles remained enabled after turn off"
    Assert-True -Condition $turnOffClearedLive -Message "Live prompt was not cleared after turn off"
} finally {
    if ($RestoreInitialState) {
        Restore-PromptState -InitialPrompts $initialPrompts -TargetApp $App
        $stateRestored = $true
    }
}

$postRestorePrompts = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
$postRestoreLive = Invoke-Ccs -Command "get_current_prompt_file_content" -Payload @{ app = $App }
$postRestorePromptIds = @($postRestorePrompts.PSObject.Properties.Name)
$postRestoreEnabledPromptIds = @(Get-EnabledPromptIds -Prompts $postRestorePrompts)
$postRestorePromptIdsMatchInitial = Test-StringSetEqual -Left $postRestorePromptIds -Right @($initialPrompts.PSObject.Properties.Name)
$postRestoreEnabledPromptIdsMatchInitial = Test-StringSetEqual -Left $postRestoreEnabledPromptIds -Right @(Get-EnabledPromptIds -Prompts $initialPrompts)
$postRestoreLivePromptMatchesInitial = (([string] $postRestoreLive) -eq ([string] $initialLive))

if ($RestoreInitialState) {
    Assert-True -Condition $stateRestored -Message "Initial prompt state was not restored"
    Assert-True -Condition $postRestorePromptIdsMatchInitial -Message "Post-restore prompt ids do not match the initial prompt ids"
    Assert-True -Condition $postRestoreEnabledPromptIdsMatchInitial -Message "Post-restore enabled prompt ids do not match the initial enabled prompt ids"
    Assert-True -Condition $postRestoreLivePromptMatchesInitial -Message "Post-restore live prompt content does not match the initial live prompt content"
}

New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($outputFullPath)) | Out-Null
$evidence = [ordered]@{
    schemaVersion = 2
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    target = "deployed-local-docker"
    webBaseUrl = $BaseUrl
    app = $App
    initialPromptIds = @($initialPrompts.PSObject.Properties.Name)
    initialEnabledPromptIds = @(Get-EnabledPromptIds -Prompts $initialPrompts)
    initialLivePromptWasEmpty = [string]::IsNullOrEmpty([string] $initialLive)
    restoreInitialState = [bool] $RestoreInitialState
    initialStateCanBeRestored = [bool] $initialStateCanBeRestored
    createdProfileIds = @($fullId, $liteId, $ultraId)
    fullEnabled = $fullEnabled
    fullLivePromptContainsCaveman = $fullLivePromptContainsCaveman
    liteEnabled = $liteEnabled
    liteDisabledFull = $liteDisabledFull
    liteLivePromptContainsModeLite = $liteLivePromptContainsModeLite
    ultraEnabled = $ultraEnabled
    ultraDisabledLite = $ultraDisabledLite
    ultraDisabledFull = $ultraDisabledFull
    ultraLivePromptContainsModeUltra = $ultraLivePromptContainsModeUltra
    turnOffRetainedProfiles = $turnOffRetainedProfiles
    turnOffDisabledAllCavemanProfiles = $turnOffDisabledAll
    turnOffClearedLivePrompt = $turnOffClearedLive
    finalPromptIds = @($afterOff.PSObject.Properties.Name)
    stateRestored = [bool] $stateRestored
    postRestorePromptIds = $postRestorePromptIds
    postRestoreEnabledPromptIds = $postRestoreEnabledPromptIds
    postRestorePromptIdsMatchInitial = $postRestorePromptIdsMatchInitial
    postRestoreEnabledPromptIdsMatchInitial = $postRestoreEnabledPromptIdsMatchInitial
    postRestoreLivePromptMatchesInitial = $postRestoreLivePromptMatchesInitial
}

$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputFullPath -Encoding UTF8
Write-Host "deployed_caveman_smoke=passed"
Write-Host ("deployed_caveman_smoke_evidence={0}" -f $outputFullPath)
