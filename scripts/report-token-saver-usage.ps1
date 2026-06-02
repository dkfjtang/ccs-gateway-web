param(
    [string[]] $LogPath = @(),
    [string] $LogDirectory,
    [string] $Pattern = "*.log",
    [int] $Tail = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-InputFiles {
    $files = New-Object System.Collections.Generic.List[string]

    foreach ($path in $LogPath) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        $resolved = Resolve-Path -LiteralPath $path -ErrorAction Stop
        foreach ($item in $resolved) {
            $files.Add($item.ProviderPath)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LogDirectory)) {
        $dir = Resolve-Path -LiteralPath $LogDirectory -ErrorAction Stop
        Get-ChildItem -LiteralPath $dir.ProviderPath -Filter $Pattern -File | ForEach-Object {
            $files.Add($_.FullName)
        }
    }

    $files | Sort-Object -Unique
}

function Add-Metric {
    param(
        [hashtable] $Target,
        [string] $Key,
        [long] $Value
    )

    if (-not $Target.ContainsKey($Key)) {
        $Target[$Key] = [int64]0
    }
    $Target[$Key] = [int64]$Target[$Key] + $Value
}

$files = @(Get-InputFiles)
if ($files.Count -eq 0) {
    throw "Provide -LogPath or -LogDirectory."
}

$totals = @{}
$byReason = @{}
$requestCount = 0
$matchedLineCount = 0

foreach ($file in $files) {
    $lines = if ($Tail -gt 0) {
        Get-Content -LiteralPath $file -Encoding UTF8 -Tail $Tail
    } else {
        Get-Content -LiteralPath $file -Encoding UTF8
    }

    foreach ($line in $lines) {
        if ($line -notmatch "\[TokenSaver\]\s+request_summary\s+") {
            continue
        }
        $matchedLineCount++
        $requestCount++
        foreach ($match in [regex]::Matches($line, "([A-Za-z_]+)=(-?\d+)")) {
            $key = $match.Groups[1].Value
            $value = [int64]$match.Groups[2].Value
            Add-Metric -Target $totals -Key $key -Value $value
            if ($key.StartsWith("skipped_")) {
                Add-Metric -Target $byReason -Key $key -Value $value
            }
        }
    }
}

Write-Host "token_saver_usage_report"
Write-Host ("files={0}" -f $files.Count)
Write-Host ("matched_lines={0}" -f $matchedLineCount)
Write-Host ("requests={0}" -f $requestCount)

$orderedTotals = @(
    "candidate_fields",
    "compressed_fields",
    "original_chars",
    "output_chars",
    "saved_chars",
    "omitted_chars"
)
foreach ($key in $orderedTotals) {
    $value = if ($totals.ContainsKey($key)) { $totals[$key] } else { 0 }
    Write-Host ("{0}={1}" -f $key, $value)
}

Write-Host "skip_reasons"
foreach ($key in @($byReason.Keys | Sort-Object)) {
    Write-Host ("{0}={1}" -f $key, $byReason[$key])
}

if ($requestCount -gt 0) {
    $saved = if ($totals.ContainsKey("saved_chars")) { [double]$totals["saved_chars"] } else { 0.0 }
    $original = if ($totals.ContainsKey("original_chars")) { [double]$totals["original_chars"] } else { 0.0 }
    $rate = if ($original -gt 0) { $saved / $original } else { 0.0 }
    Write-Host ("saved_ratio={0:P2}" -f $rate)
}
