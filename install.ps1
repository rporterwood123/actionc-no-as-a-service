#requires -Version 5
# Install the `naas` command. Cross-platform: runs under Windows PowerShell 5.1 and
# under PowerShell 7+ (pwsh) on Windows, Linux, and macOS. Consumes the committed
# naas.class + reasons.txt (refresh them with ./build.sh on a Linux box). Idempotent.
$ErrorActionPreference = 'Stop'

$Repo = $PSScriptRoot

# 0. Detect platform. $IsWindows/$IsLinux/$IsMacOS exist only in PowerShell 6+; on
#    Windows PowerShell 5.1 they're undefined ($null), which implies Windows.
$onWindows = if ($null -ne $IsWindows) { [bool]$IsWindows } else { $true }
$onMacOS   = [bool]$IsMacOS
$osName    = if ($onMacOS) { 'macOS' } elseif ($onWindows) { 'Windows' } else { 'Linux' }

# 1. Require the committed build artifacts.
foreach ($f in 'naas.class', 'reasons.txt') {
    if (-not (Test-Path (Join-Path $Repo $f))) {
        Write-Error "$f missing. Run ./build.sh on a Linux box and commit it first."
    }
}

if ($onWindows) {
    # ---------------------------------------------------------------- Windows ---
    $DataDir = Join-Path $env:LOCALAPPDATA 'naas'
    $BinDir  = Join-Path $DataDir 'bin'

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

    Write-Host "os:   $osName"
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
} else {
    # ------------------------------------------------------- Linux / macOS ---
    # Mirrors install.sh: same locations, wrapper template, and JDK probe order.
    $DataDir = Join-Path $HOME '.local/share/naas'
    $BinDir  = Join-Path $HOME '.local/bin'

    # 2. Resolve a JDK 21 `java`. Order: JAVA_HOME, platform probe, PATH.
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin/java'))) {
        $Java = Join-Path $env:JAVA_HOME 'bin/java'
    } else {
        $Java = $null
        if ($onMacOS) {
            # Standard macOS mechanism.
            if (Test-Path '/usr/libexec/java_home') {
                $jhome = (& /usr/libexec/java_home -v 21 2>$null)
                if (-not $jhome) { $jhome = (& /usr/libexec/java_home 2>$null) }
                if ($jhome -and (Test-Path (Join-Path $jhome 'bin/java'))) {
                    $Java = Join-Path $jhome 'bin/java'
                }
            }
        } else {
            # Linux: glob common JVM locations + this dev box's ~/tools JDK.
            $candidates = @()
            $candidates += Get-ChildItem -Path '/usr/lib/jvm' -Filter '*21*' -Directory -ErrorAction Ignore |
                ForEach-Object { Join-Path $_.FullName 'bin/java' }
            $candidates += Get-ChildItem -Path (Join-Path $HOME 'tools') -Filter 'jdk-21*' -Directory -ErrorAction Ignore |
                ForEach-Object { Join-Path $_.FullName 'bin/java' }
            foreach ($c in $candidates) { if (Test-Path $c) { $Java = $c; break } }
        }
        if (-not $Java) {
            $cmd = Get-Command java -ErrorAction SilentlyContinue
            if ($cmd) {
                $Java = $cmd.Source
            } else {
                Write-Error 'no JDK 21 found. Install one or set JAVA_HOME.'
            }
        }
    }

    Write-Host "os:   $osName"
    Write-Host "java: $Java"

    # 3. Stage committed class + data.
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    Copy-Item (Join-Path $Repo 'naas.class')  (Join-Path $DataDir 'naas.class')  -Force
    Copy-Item (Join-Path $Repo 'reasons.txt') (Join-Path $DataDir 'reasons.txt') -Force

    # 4. Render the POSIX wrapper with the resolved java path + data dir.
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $tpl = Get-Content (Join-Path (Join-Path $Repo 'bin') 'naas.in') -Raw
    $tpl = $tpl.Replace('@JAVA@', $Java).Replace('@DATADIR@', $DataDir)
    # POSIX shells want LF endings and no BOM (the shebang must be the first bytes).
    $tpl = $tpl -replace "`r`n", "`n"
    $Naas = Join-Path $BinDir 'naas'
    Set-Content -Path $Naas -Value $tpl -Encoding utf8NoBOM -NoNewline
    & chmod +x $Naas

    Write-Host "installed: $Naas"

    # 5. PATH check (non-fatal).
    $onPath = ($env:PATH -split ':') -contains $BinDir
    if (-not $onPath) {
        Write-Host "note: $BinDir is not on your PATH. Add to your shell rc:"
        Write-Host '  export PATH="$HOME/.local/bin:$PATH"'
    } else {
        Write-Host "$BinDir already on your PATH."
    }
}
