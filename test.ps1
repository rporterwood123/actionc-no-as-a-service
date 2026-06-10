#requires -Version 5
# Post-install smoke test for the `naas` command on Windows.
$ErrorActionPreference = 'Stop'

$Naas = Join-Path $env:LOCALAPPDATA 'naas\bin\naas.cmd'
if (-not (Test-Path $Naas)) {
    Write-Error "FAIL: $Naas not installed (run .\install.ps1)"
}

# Run 10x: each line must be non-empty; collect for a variation check.
$lines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt 10; $i++) {
    $line = (& $Naas | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($line)) {
        Write-Error "FAIL: empty output on run $i"
    }
    $lines.Add($line)
}

# Expect more than one distinct reason across 10 runs (random index works).
$distinct = ($lines | Sort-Object -Unique).Count
if ($distinct -le 1) {
    Write-Error "FAIL: no variation across 10 runs"
}

# Runs from an unrelated cwd (wrapper cd makes it location-independent).
Push-Location $env:SystemRoot
try { & $Naas | Out-Null } finally { Pop-Location }

Write-Host "PASS: naas prints varied, non-empty reasons ($distinct distinct in 10 runs)"
