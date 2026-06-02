param(
    [switch] $AllowEnvironmentBlocked,
    [string] $RunDir = ".run\caveman-desktop-preflight"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$runPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $RunDir))
$targetPath = Join-Path $runPath "tauri-target"
$configPath = Join-Path $runPath "tauri-npm-build-config.json"
$logPath = Join-Path $runPath "tauri-build-no-bundle.log"
$stdoutPath = Join-Path $runPath "tauri-build-no-bundle.stdout.log"
$stderrPath = Join-Path $runPath "tauri-build-no-bundle.stderr.log"

New-Item -ItemType Directory -Force -Path $runPath | Out-Null
New-Item -ItemType Directory -Force -Path $targetPath | Out-Null

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Actual,
        [Parameter(Mandatory = $true)]
        [string] $Expected
    )

    if ($Actual -ne $Expected) {
        throw ("{0} expected {1}, got {2}" -f $Name, $Expected, $Actual)
    }
}

$packageJson = Get-Content -LiteralPath (Join-Path $repoRoot "package.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal -Name "@tauri-apps/cli" -Actual $packageJson.devDependencies."@tauri-apps/cli" -Expected "2.10.1"
Assert-Equal -Name "@tauri-apps/api" -Actual $packageJson.dependencies."@tauri-apps/api" -Expected "2.10.1"
Assert-Equal -Name "@tauri-apps/plugin-dialog" -Actual $packageJson.dependencies."@tauri-apps/plugin-dialog" -Expected "2.6.0"
Assert-Equal -Name "@tauri-apps/plugin-updater" -Actual $packageJson.dependencies."@tauri-apps/plugin-updater" -Expected "2.10.1"

$tauriConfig = @{
    build = @{
        beforeBuildCommand = "npm run build:renderer"
    }
} | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $configPath -Value $tauriConfig -Encoding UTF8

$npm = (Get-Command npm.cmd -ErrorAction SilentlyContinue)
if (-not $npm) {
    $npm = Get-Command npm -ErrorAction Stop
}

$process = New-Object System.Diagnostics.Process
$process.StartInfo.FileName = $npm.Source
$process.StartInfo.WorkingDirectory = $repoRoot
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.RedirectStandardOutput = $false
$process.StartInfo.RedirectStandardError = $false
$process.StartInfo.Arguments = "exec -- tauri build --config `"$configPath`" --no-bundle"
$process.StartInfo.Environment["CARGO_TARGET_DIR"] = $targetPath

Remove-Item -LiteralPath $stdoutPath, $stderrPath, $logPath -Force -ErrorAction SilentlyContinue
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
$process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

if (-not $process.Start()) {
    throw "Failed to start Tauri desktop preflight"
}

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
$combinedOutput = $stdout + [Environment]::NewLine + $stderr
Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding UTF8
Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding UTF8
Set-Content -LiteralPath $logPath -Value $combinedOutput -Encoding UTF8

if ($process.ExitCode -eq 0) {
    Write-Host "Caveman desktop preflight passed."
    Write-Host ("tauri_config={0}" -f $configPath)
    Write-Host ("cargo_target_dir={0}" -f $targetPath)
    Write-Host "desktop_preflight=artifact_build_no_bundle_passed"
    exit 0
}

$blockedByLocalExecutionPolicy =
    ($combinedOutput -match "os error 5" -or $combinedOutput -match "拒绝访问") -and
    ($combinedOutput -match "build-script-build" -or $combinedOutput -match "failed to run custom build command")

if ($blockedByLocalExecutionPolicy) {
    Write-Host "Caveman desktop preflight reached Rust build-script execution."
    Write-Host ("tauri_config={0}" -f $configPath)
    Write-Host ("cargo_target_dir={0}" -f $targetPath)
    Write-Host ("log={0}" -f $logPath)
    Write-Host "desktop_preflight=environment_blocked_os_error_5"

    if ($AllowEnvironmentBlocked) {
        exit 0
    }

    throw "Desktop artifact build is blocked by local Windows execution policy. Rerun on CI/build host or pass -AllowEnvironmentBlocked only for local evidence classification."
}

Write-Host $combinedOutput
throw ("Desktop preflight failed with exit code {0}; see {1}" -f $process.ExitCode, $logPath)
