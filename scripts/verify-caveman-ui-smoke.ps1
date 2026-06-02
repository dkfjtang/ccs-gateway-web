param(
    [int] $Port = 18780,
    [string] $App = "openclaw",
    [string] $TestHome = ".run\caveman-ui-smoke",
    [string] $EvidencePath = ".run\caveman-ui-smoke\caveman-ui-smoke-evidence.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$testHomePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $TestHome))
$playwrightRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ".run\playwright-smoke"))
$playwrightBrowsersPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ".run\playwright-browsers"))
$screenshotsRoot = [System.IO.Path]::GetFullPath((Join-Path $testHomePath "screenshots"))
$resolvedEvidencePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EvidencePath))

$expectedTestHomePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ".run\caveman-ui-smoke"))
if (-not $testHomePath.Equals($expectedTestHomePath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw ("Refusing to clear non-default smoke test home: {0}" -f $testHomePath)
}
if (-not $resolvedEvidencePath.StartsWith($testHomePath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw ("-EvidencePath must stay inside the Caveman UI smoke test home: {0}" -f $EvidencePath)
}
if (Test-Path -LiteralPath $testHomePath) {
    Remove-Item -LiteralPath $testHomePath -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $testHomePath | Out-Null
New-Item -ItemType Directory -Force -Path $playwrightRoot | Out-Null
New-Item -ItemType Directory -Force -Path $playwrightBrowsersPath | Out-Null
New-Item -ItemType Directory -Force -Path $screenshotsRoot | Out-Null

$cargo = (Get-Command cargo.exe -ErrorAction Stop).Source
$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($npmCommand) {
    $npm = $npmCommand.Source
} else {
    $npm = $null
}
if (-not $npm) {
    $npm = (Get-Command npm -ErrorAction Stop).Source
}

$serverRoot = "http://127.0.0.1:$Port"
$baseUrl = "http://127.0.0.1:$Port/api"
$createdIds = New-Object System.Collections.Generic.List[string]
$process = $null
$browserExecutable = $null

function Find-SystemBrowser {
    $candidates = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    foreach ($name in @("chrome", "msedge", "chromium")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            return $command.Source
        }
    }

    return $null
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

function Write-UiSmokeEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string] $ScreenshotDir,
        [Parameter(Mandatory = $true)]
        [string] $ConfigDir
    )

    $requiredScreenshots = @(
        "00-home.png",
        "01-openclaw-prompts.png",
        "02-caveman-full.png",
        "03-caveman-lite.png",
        "04-caveman-ultra.png",
        "05-caveman-off.png"
    )
    $screenshotArtifacts = [ordered] @{}
    foreach ($screenshot in $requiredScreenshots) {
        $screenshotPath = Join-Path $ScreenshotDir $screenshot
        Assert-True -Condition (Test-Path -LiteralPath $screenshotPath -PathType Leaf) -Message ("Required UI smoke screenshot is missing: {0}" -f $screenshot)
        $screenshotArtifacts[$screenshot] = [ordered] @{
            path = $screenshotPath
            sha256 = (Get-FileHash -LiteralPath $screenshotPath -Algorithm SHA256).Hash
        }
    }

    $evidence = [ordered] @{
        schemaVersion = 1
        createdAt = (Get-Date).ToUniversalTime().ToString("o")
        target = "web-ui-smoke"
        webBaseUrl = $serverRoot
        app = $App
        configDir = $ConfigDir
        screenshotsDir = $ScreenshotDir
        uiControls = "openclaw_prompt_entry_lite_full_ultra_turn_off"
        uiFlow = "full_to_lite_to_ultra_to_off"
        turnOff = "preset_retained_live_prompt_cleared"
        screenshots = $screenshotArtifacts
    }

    $evidenceDirectory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Ensure-Playwright {
    $packageJson = Join-Path $playwrightRoot "package.json"
    if (-not (Test-Path -LiteralPath $packageJson)) {
        Push-Location $playwrightRoot
        try {
            & $npm init -y | Out-Null
        } finally {
            Pop-Location
        }
    }

    $playwrightPackage = Join-Path $playwrightRoot "node_modules\playwright\package.json"
    if (-not (Test-Path -LiteralPath $playwrightPackage)) {
        Push-Location $playwrightRoot
        try {
            & $npm install playwright@1.57.0 --no-save
            if ($LASTEXITCODE -ne 0) {
                throw "npm install playwright failed with exit code $LASTEXITCODE"
            }
        } finally {
            Pop-Location
        }
    }

    $script:browserExecutable = Find-SystemBrowser
    if ($script:browserExecutable) {
        Write-Host ("Using system browser for UI smoke: {0}" -f $script:browserExecutable)
        return
    }

    Push-Location $playwrightRoot
    try {
        $env:PLAYWRIGHT_BROWSERS_PATH = $playwrightBrowsersPath
        & $npm exec -- playwright install chromium
        if ($LASTEXITCODE -ne 0) {
            throw "playwright install chromium failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
        Remove-Item Env:\PLAYWRIGHT_BROWSERS_PATH -ErrorAction SilentlyContinue
    }
}

function Write-SmokeScript {
    $scriptPath = Join-Path $playwrightRoot "caveman-ui-smoke.mjs"
    $script = @'
import assert from "node:assert/strict";
import path from "node:path";
import { chromium } from "playwright";

const serverRoot = process.env.CCS_SERVER_ROOT;
const baseUrl = `${serverRoot}/api`;
const app = process.env.CCS_APP || "openclaw";
const screenshotDir = process.env.CCS_SCREENSHOT_DIR;
const executablePath = process.env.CCS_BROWSER_EXECUTABLE || undefined;

async function invoke(command, payload = {}) {
  const res = await fetch(`${baseUrl}/invoke`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ command, payload }),
  });
  const text = await res.text();
  assert.equal(res.ok, true, `${command} HTTP ${res.status}: ${text}`);
  const json = text ? JSON.parse(text) : {};
  if (json.error) throw new Error(`${command}: ${json.error}`);
  return Object.prototype.hasOwnProperty.call(json, "result") ? json.result : json;
}

async function promptState() {
  const prompts = await invoke("get_prompts", { app });
  const live = await invoke("get_current_prompt_file_content", { app });
  return { prompts, live };
}

async function buttonDump() {
  return page.locator("button").evaluateAll((buttons) =>
    buttons.map((button) => ({
      text: button.textContent?.trim() || "",
      aria: button.getAttribute("aria-label") || "",
      title: button.getAttribute("title") || "",
      disabled: button.hasAttribute("disabled"),
    })),
  );
}

async function expectState(label, checks) {
  let lastError;
  let lastState;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    lastState = await promptState();
    try {
      checks(lastState);
      console.log(`${label}=ok`);
      return;
    } catch (error) {
      lastError = error;
      await page.waitForTimeout(250);
    }
  }

  console.log(`${label}_state=${JSON.stringify(lastState)}`);
  console.log(`${label}_buttons=${JSON.stringify(await buttonDump())}`);
  throw lastError;
}

async function clickCavemanMode(mode) {
  const button = page
    .getByRole("button", {
      name: new RegExp(`(^|\\\\b)(Enable )?Caveman ${mode}( enabled)?($|\\\\b)`, "i"),
    })
    .first();
  await button.waitFor({ state: "visible" });
  await button.click();
}

const browser = await chromium.launch({ headless: true, executablePath });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

try {
  await page.goto(serverRoot, { waitUntil: "networkidle" });
  await page.screenshot({ path: path.join(screenshotDir, "00-home.png"), fullPage: true });

  const welcomeDismiss = page.getByRole("button", { name: /\u6211\u77e5\u9053\u4e86|Got it|OK/i }).first();
  if ((await welcomeDismiss.count()) > 0) {
    await welcomeDismiss.click();
  }

  await page.getByRole("button", { name: "OpenClaw" }).click();

  const promptsButton = page.getByRole("button", { name: /Prompts|\u63d0\u793a\u8bcd/i }).first();
  assert.equal(await promptsButton.count(), 1, `Prompt entry button missing. Body: ${await page.locator("body").innerText({ timeout: 1000 }).catch(() => "<no body>")}`);
  await promptsButton.click();

  await page.getByRole("button", { name: /Caveman Full/i }).waitFor();
  await page.screenshot({ path: path.join(screenshotDir, "01-openclaw-prompts.png"), fullPage: true });

  await clickCavemanMode("Full");
  await expectState("ui_full", ({ prompts, live }) => {
    assert.equal(prompts["caveman-full"]?.enabled, true);
    assert.match(String(live || ""), /Mode: full/);
  });
  await page.screenshot({ path: path.join(screenshotDir, "02-caveman-full.png"), fullPage: true });

  await clickCavemanMode("Lite");
  await expectState("ui_lite", ({ prompts, live }) => {
    assert.equal(prompts["caveman-lite"]?.enabled, true);
    assert.equal(prompts["caveman-full"]?.enabled, false);
    assert.match(String(live || ""), /Mode: lite/);
  });
  await page.screenshot({ path: path.join(screenshotDir, "03-caveman-lite.png"), fullPage: true });

  await clickCavemanMode("Ultra");
  await expectState("ui_ultra", ({ prompts, live }) => {
    assert.equal(prompts["caveman-ultra"]?.enabled, true);
    assert.equal(prompts["caveman-lite"]?.enabled, false);
    assert.match(String(live || ""), /Mode: ultra/);
  });
  await page.screenshot({ path: path.join(screenshotDir, "04-caveman-ultra.png"), fullPage: true });

  await page.getByRole("button", { name: /Turn off Caveman|\u5173\u95ed Caveman|Caveman \u3092\u30aa\u30d5/i }).click();
  await expectState("ui_off", ({ prompts, live }) => {
    assert.equal(prompts["caveman-ultra"]?.enabled, false);
    assert.ok(prompts["caveman-ultra"], "Caveman Ultra preset should be retained");
    assert.equal(String(live || ""), "");
  });

  await page.screenshot({ path: path.join(screenshotDir, "05-caveman-off.png"), fullPage: true });
  await page.screenshot({ path: path.join(screenshotDir, "02-caveman-off.png"), fullPage: true });
} finally {
  await browser.close();
}
'@

    Set-Content -LiteralPath $scriptPath -Value $script -Encoding UTF8
    return $scriptPath
}

try {
    Ensure-Playwright

    Write-Host "==> build web assets"
    rtk powershell -NoProfile -Command "& .\node_modules\.bin\vite.cmd build --mode web"
    if ($LASTEXITCODE -ne 0) {
        throw "vite build failed with exit code $LASTEXITCODE"
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

    if (-not $process.Start()) {
        throw "Failed to start cc-switch server"
    }

    $deadline = (Get-Date).AddSeconds(90)
    do {
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

    foreach ($id in @("caveman-lite", "caveman-full", "caveman-ultra")) {
        try {
            Invoke-Ccs -Command "delete_prompt" -Payload @{ app = $App; id = $id } | Out-Null
        } catch {
            Write-Verbose ("No stale prompt to cleanup for {0}: {1}" -f $id, $_.Exception.Message)
        }
    }

    $initialPrompts = Invoke-Ccs -Command "get_prompts" -Payload @{ app = $App }
    Assert-True `
        -Condition (($initialPrompts.PSObject.Properties | Measure-Object).Count -eq 0) `
        -Message "Smoke test requires an empty isolated prompt set"

    $scriptPath = Write-SmokeScript
    $env:CCS_SERVER_ROOT = $serverRoot
    $env:CCS_APP = $App
    $env:CCS_SCREENSHOT_DIR = $screenshotsRoot
    $env:NODE_PATH = Join-Path $playwrightRoot "node_modules"
    $env:PLAYWRIGHT_BROWSERS_PATH = $playwrightBrowsersPath
    if ($browserExecutable) {
        $env:CCS_BROWSER_EXECUTABLE = $browserExecutable
    }

    Push-Location $playwrightRoot
    try {
        node $scriptPath
        if ($LASTEXITCODE -ne 0) {
            throw "Playwright Caveman UI smoke failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
        Remove-Item Env:\CCS_SERVER_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:\CCS_APP -ErrorAction SilentlyContinue
        Remove-Item Env:\CCS_SCREENSHOT_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:\NODE_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\PLAYWRIGHT_BROWSERS_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\CCS_BROWSER_EXECUTABLE -ErrorAction SilentlyContinue
    }

    Write-UiSmokeEvidence -Path $resolvedEvidencePath -ScreenshotDir $screenshotsRoot -ConfigDir $configDir

    foreach ($id in @("caveman-lite", "caveman-full", "caveman-ultra")) {
        $createdIds.Add($id) | Out-Null
    }

    Write-Host "Caveman UI smoke passed."
    Write-Host ("config_dir={0}" -f $configDir)
    Write-Host ("screenshots={0}" -f $screenshotsRoot)
    Write-Host ("ui_smoke_evidence={0}" -f $resolvedEvidencePath)
    Write-Host "ui_controls=openclaw_prompt_entry_lite_full_ultra_turn_off"
    Write-Host "ui_flow=full_to_lite_to_ultra_to_off"
    Write-Host "turn_off=preset_retained_live_prompt_cleared"
} finally {
    foreach ($id in $createdIds) {
        try {
            Invoke-Ccs -Command "delete_prompt" -Payload @{ app = $App; id = $id } | Out-Null
        } catch {
            Write-Warning ("Failed to cleanup prompt {0}: {1}" -f $id, $_.Exception.Message)
        }
    }

    if ($process -and -not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit()
    }
}
