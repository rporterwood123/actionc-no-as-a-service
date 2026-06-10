#requires -Version 5
# Install the `naas` command on Windows. Consumes the committed naas.class +
# reasons.txt (refresh them with ./build.sh on a Linux box). Idempotent.
$ErrorActionPreference = 'Stop'

$Repo    = $PSScriptRoot
$DataDir = Join-Path $env:LOCALAPPDATA 'naas'
$BinDir  = Join-Path $DataDir 'bin'

# 1. Require the committed build artifacts.
foreach ($f in 'naas.class', 'reasons.txt') {
    if (-not (Test-Path (Join-Path $Repo $f))) {
        Write-Error "$f missing. Run ./build.sh on a Linux box and commit it first."
    }
}

# 2. Resolve a JDK 21 java.exe. Order: JAVA_HOME, then PATH.
if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    $Java = Join-Path $env:JAVA_HOME 'bin\java.exe'
} else {
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd) {
        $Java = $cmd.Source
    } else {
        Write-Error 'no JDK 21 found. Install one or set JAVA_HOME.'
    }
}

Write-Host "java: $Java"

# 3. Stage committed class + data.
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
Copy-Item (Join-Path $Repo 'naas.class')  (Join-Path $DataDir 'naas.class')  -Force
Copy-Item (Join-Path $Repo 'reasons.txt') (Join-Path $DataDir 'reasons.txt') -Force

# 4. Render the .cmd wrapper with the resolved java path + data dir.
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$tpl = Get-Content (Join-Path (Join-Path $Repo 'bin') 'naas.cmd.in') -Raw
$tpl = $tpl.Replace('@JAVA@', $Java).Replace('@DATADIR@', $DataDir)
# Normalize to CRLF so the generated .cmd is valid on Windows regardless of the
# template's (Linux-committed) line endings.
$tpl = ($tpl -replace "`r`n", "`n") -replace "`n", "`r`n"
Set-Content -Path (Join-Path $BinDir 'naas.cmd') -Value $tpl -Encoding Oem -NoNewline

Write-Host "installed: $(Join-Path $BinDir 'naas.cmd')"

# 5. Auto-update the user PATH (idempotent).
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$onPath = $userPath -and (($userPath -split ';') -contains $BinDir)
if (-not $onPath) {
    $newPath = if ($userPath) { $userPath.TrimEnd(';') + ';' + $BinDir } else { $BinDir }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "added $BinDir to your user PATH. Open a new terminal to use 'naas'."
} else {
    Write-Host "$BinDir already on your user PATH."
}
