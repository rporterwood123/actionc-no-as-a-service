# Cross-platform `naas` (macOS + Windows) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `naas` CLI install and run on macOS and Windows (PowerShell) in addition to Linux, shipping a prebuilt `naas.class` and replacing the hardcoded Linux JDK path with OS-aware auto-detection.

**Architecture:** The compiled `naas.class` is portable JVM bytecode, so the program is unchanged. A maintainer `build.sh` (Linux, needs the ActionC compiler) produces the committed `naas.class` + `reasons.txt`. Thin installers consume those: one POSIX `install.sh` for Linux + macOS (no compile, OS-aware Java detection), and a PowerShell `install.ps1` for Windows that auto-updates the user PATH.

**Tech Stack:** ActionC (build-time only), JDK 21 runtime, POSIX shell, PowerShell 5+/7, Windows `.cmd` shim, python3 (build-time data gen only).

---

## Environment constants (used throughout)

- ActionC compiler jar (build-time only): `/projects/ActionC/target/scala-2.12/ActionC.jar` (present).
- This dev box's JDK 21: `/home/pwood/tools/jdk-21.0.11+10` (not on PATH; matched by the `$HOME/tools/jdk-21*` glob).
- POSIX install targets: wrapper → `~/.local/bin/naas`; data → `~/.local/share/naas/`.
- Windows install targets: wrapper → `%LOCALAPPDATA%\naas\bin\naas.cmd`; data → `%LOCALAPPDATA%\naas\`.
- `shellcheck` is **not** installed here — do not rely on it.
- `pwsh` (PowerShell 7.6.2) **is** installed — use it to **parse-check** the `.ps1` files. Full Windows behavior (`%LOCALAPPDATA%`, `.cmd` execution, user-PATH writes) cannot run on this Linux box; those are verified by review + parse-check only.

To get a usable shell for any manual compile/run during implementation:
```bash
export JAVA_HOME=/home/pwood/tools/jdk-21.0.11+10
export PATH="$JAVA_HOME/bin:$PATH"
```

## File structure (created / modified)

| Action | Path | Responsibility |
|---|---|---|
| Create | `build.sh` | Maintainer build: gen `reasons.txt` + compile `naas.class`. Linux + ActionC.jar. |
| Modify | `.gitignore` | Stop ignoring `naas.class` (now committed). |
| Create (committed) | `naas.class` | Prebuilt bytecode, produced by `build.sh`. |
| Modify | `install.sh` | Unified POSIX installer (Linux + macOS): copy artifacts, OS-aware Java detect, render wrapper. No compile. |
| Create | `bin/naas.cmd.in` | Windows `.cmd` wrapper template (`@JAVA@`, `@DATADIR@`). |
| Create | `install.ps1` | Windows installer: copy artifacts, detect Java, render `naas.cmd`, auto-update user PATH. |
| Create | `test.ps1` | Windows post-install smoke test. |
| Keep | `bin/naas.in`, `test.sh`, `naas.actionc`, `reasons.json`, `reasons.txt`, `tools/gen-reasons.py` | Unchanged. |
| Modify | `README.md` | Add macOS + Windows install/usage sections. |

**Note on TDD style:** these are install/wrapper scripts, not unit-testable functions. Mirroring the existing repo pattern (the original `naas-actionc-cli` plan), each task writes the script then runs a concrete verification with expected output. The smoke tests (`test.sh`, `test.ps1`) are the regression tests.

---

## Task 1: Maintainer build step + commit prebuilt class

**Files:**
- Create: `build.sh`
- Modify: `.gitignore`
- Create (committed output): `naas.class`

- [ ] **Step 1: Write `build.sh`**

Create `build.sh`:

```sh
#!/bin/sh
# Maintainer build: regenerate reasons.txt and compile naas.actionc -> naas.class.
# Run on Linux with the ActionC compiler available, whenever naas.actionc or
# reasons.json changes. Commits the resulting naas.class + reasons.txt.
set -eu

REPO=$(CDPATH= cd "$(dirname "$0")" && pwd)

# Resolve a JDK 21 `java` (build needs it to run the ActionC compiler).
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JAVA="$JAVA_HOME/bin/java"
else
    JAVA=
    for j in /usr/lib/jvm/*21*/bin/java "$HOME"/tools/jdk-21*/bin/java; do
        [ -x "$j" ] && { JAVA="$j"; break; }
    done
    if [ -z "$JAVA" ]; then
        if command -v java >/dev/null 2>&1; then JAVA=$(command -v java); else
            echo "error: no JDK 21 found. Install one or set JAVA_HOME." >&2
            exit 1
        fi
    fi
fi

# Resolve the ActionC compiler jar (build-time only).
if [ -n "${ACTIONC_JAR:-}" ] && [ -f "$ACTIONC_JAR" ]; then
    JAR="$ACTIONC_JAR"
elif [ -f "$REPO/../ActionC/target/scala-2.12/ActionC.jar" ]; then
    JAR="$REPO/../ActionC/target/scala-2.12/ActionC.jar"
else
    echo "error: ActionC.jar not found. Set ACTIONC_JAR, or build it:" >&2
    echo "  (in the ActionC repo) sbt assembly" >&2
    exit 1
fi

echo "java:    $JAVA"
echo "ActionC: $JAR"

# 1. Generate the data file from canonical reasons.json.
python3 "$REPO/tools/gen-reasons.py"

# 2. Compile naas.actionc -> naas.class (in the repo dir).
( cd "$REPO" && "$JAVA" -jar "$JAR" naas.actionc )

echo "built: $REPO/naas.class + $REPO/reasons.txt"
echo "commit these so the per-platform installers can consume them."
```

- [ ] **Step 2: Make it executable and run it**

Run:
```bash
cd /projects/actionc-no-as-a-service
chmod +x build.sh
./build.sh
```
Expected: prints resolved `java`/`ActionC` paths, the `gen-reasons` line (`wrote .../reasons.txt (1055 reasons, ...)`), and `built: .../naas.class + .../reasons.txt`. No errors.

- [ ] **Step 3: Verify the class exists and runs on a plain JDK**

Run:
```bash
cd /projects/actionc-no-as-a-service
ls -l naas.class
( cd /projects/actionc-no-as-a-service && /home/pwood/tools/jdk-21.0.11+10/bin/java naas )
```
Expected: `naas.class` exists; the `java naas` invocation prints one real rejection reason.

- [ ] **Step 4: Stop ignoring `naas.class`**

Edit `.gitignore` — remove the `naas.class` line. The file currently reads:

```
# Build / run artifacts
naas.class
__pycache__/
*.pyc
```

Change it to:

```
# Build / run artifacts
__pycache__/
*.pyc
```

- [ ] **Step 5: Verify `naas.class` is no longer ignored**

Run:
```bash
cd /projects/actionc-no-as-a-service
git check-ignore naas.class || echo "not ignored (good)"
```
Expected: `not ignored (good)`.

- [ ] **Step 6: Commit build script + prebuilt class + gitignore change**

```bash
cd /projects/actionc-no-as-a-service
git add build.sh .gitignore naas.class reasons.txt
git commit -m "Add build.sh; commit prebuilt naas.class for cross-platform installers"
```

---

## Task 2: Unified POSIX installer (Linux + macOS)

**Files:**
- Modify: `install.sh` (full rewrite — no compile, OS-aware Java detection, copy committed artifacts)

- [ ] **Step 1: Rewrite `install.sh`**

Replace the entire contents of `install.sh` with:

```sh
#!/bin/sh
# Install the `naas` command to ~/.local/bin on Linux or macOS.
# Consumes the committed naas.class + reasons.txt (run ./build.sh to refresh them).
# Idempotent: safe to re-run.
set -eu

REPO=$(CDPATH= cd "$(dirname "$0")" && pwd)
BINDIR="$HOME/.local/bin"
DATADIR="$HOME/.local/share/naas"

# 1. Require the committed build artifacts.
[ -f "$REPO/naas.class" ]  || { echo "error: naas.class missing. Run ./build.sh first." >&2; exit 1; }
[ -f "$REPO/reasons.txt" ] || { echo "error: reasons.txt missing. Run ./build.sh first." >&2; exit 1; }

# 2. Resolve a JDK 21 `java`, OS-aware. Order: JAVA_HOME, platform probe, PATH.
OS=$(uname -s)
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JAVA="$JAVA_HOME/bin/java"
else
    JAVA=
    case "$OS" in
        Linux)
            # Glob common JVM locations + this dev box's ~/tools JDK.
            for j in /usr/lib/jvm/*21*/bin/java "$HOME"/tools/jdk-21*/bin/java; do
                [ -x "$j" ] && { JAVA="$j"; break; }
            done
            ;;
        Darwin)
            # Standard macOS mechanism.
            if [ -x /usr/libexec/java_home ]; then
                home=$(/usr/libexec/java_home -v 21 2>/dev/null) \
                    || home=$(/usr/libexec/java_home 2>/dev/null) || home=
                [ -n "$home" ] && [ -x "$home/bin/java" ] && JAVA="$home/bin/java"
            fi
            ;;
    esac
    if [ -z "$JAVA" ]; then
        if command -v java >/dev/null 2>&1; then
            JAVA=$(command -v java)
        else
            echo "error: no JDK 21 found. Install one or set JAVA_HOME." >&2
            exit 1
        fi
    fi
fi

echo "os:   $OS"
echo "java: $JAVA"

# 3. Stage committed class + data.
mkdir -p "$DATADIR"
cp "$REPO/naas.class"  "$DATADIR/naas.class"
cp "$REPO/reasons.txt" "$DATADIR/reasons.txt"

# 4. Render the wrapper with the resolved java path + data dir.
mkdir -p "$BINDIR"
sed -e "s#@JAVA@#$JAVA#g" -e "s#@DATADIR@#$DATADIR#g" \
    "$REPO/bin/naas.in" > "$BINDIR/naas"
chmod +x "$BINDIR/naas"

echo "installed: $BINDIR/naas"

# 5. PATH check (non-fatal).
case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *) echo "note: $BINDIR is not on your PATH. Add to your shell rc:" >&2
       echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2 ;;
esac
```

- [ ] **Step 2: Clean install and verify**

Run:
```bash
cd /projects/actionc-no-as-a-service
rm -rf "$HOME/.local/share/naas" "$HOME/.local/bin/naas"
./install.sh
```
Expected: prints `os:   Linux`, `java: /home/pwood/tools/jdk-21.0.11+10/bin/java` (resolved via the `~/tools/jdk-21*` glob — proves the hardcoded path is gone), and `installed: /home/pwood/.local/bin/naas`. No errors.

- [ ] **Step 3: Run the smoke test (unchanged `test.sh`)**

Run:
```bash
cd /projects/actionc-no-as-a-service
./test.sh
```
Expected: `PASS: naas prints varied, non-empty reasons (N distinct in 10 runs)` with N > 1.

- [ ] **Step 4: Verify idempotency**

Run:
```bash
cd /projects/actionc-no-as-a-service
./install.sh && /home/pwood/.local/bin/naas
```
Expected: completes cleanly again, prints a reason.

- [ ] **Step 5: Verify the macOS branch is syntactically valid (review-only)**

Run:
```bash
cd /projects/actionc-no-as-a-service
sh -n install.sh && echo "install.sh: syntax OK"
```
Expected: `install.sh: syntax OK`. (The `Darwin` branch can't execute on Linux; this confirms the script parses. Manual review of the `Darwin` case is part of this step — confirm it uses `/usr/libexec/java_home -v 21`.)

- [ ] **Step 6: Commit**

```bash
cd /projects/actionc-no-as-a-service
git add install.sh
git commit -m "Make install.sh a unified Linux+macOS installer with OS-aware Java detection"
```

---

## Task 3: Windows `.cmd` wrapper template

**Files:**
- Create: `bin/naas.cmd.in`

- [ ] **Step 1: Write the Windows wrapper template**

Create `bin/naas.cmd.in`:

```bat
@echo off
rem naas - print a random rejection reason. Generated by install.ps1.
rem The compiled ActionC program reads reasons.txt relative to the process
rem working directory, so we cd into the staged data dir before running.
cd /d "@DATADIR@"
"@JAVA@" naas
```

- [ ] **Step 2: Verify placeholders are present**

Run:
```bash
cd /projects/actionc-no-as-a-service
grep -c '@DATADIR@' bin/naas.cmd.in && grep -c '@JAVA@' bin/naas.cmd.in
```
Expected: each prints `1` (both placeholders present, ready for `install.ps1` substitution).

- [ ] **Step 3: Commit**

```bash
cd /projects/actionc-no-as-a-service
git add bin/naas.cmd.in
git commit -m "Add Windows .cmd wrapper template"
```

---

## Task 4: Windows installer (`install.ps1`)

**Files:**
- Create: `install.ps1`

- [ ] **Step 1: Write `install.ps1`**

Create `install.ps1`:

```powershell
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
Set-Content -Path (Join-Path $BinDir 'naas.cmd') -Value $tpl -Encoding Ascii

Write-Host "installed: $(Join-Path $BinDir 'naas.cmd')"

# 5. Auto-update the user PATH (idempotent).
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$onPath = $userPath -and (($userPath -split ';') -contains $BinDir)
if (-not $onPath) {
    $newPath = if ($userPath) { "$userPath;$BinDir" } else { $BinDir }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "added $BinDir to your user PATH. Open a new terminal to use 'naas'."
} else {
    Write-Host "$BinDir already on your user PATH."
}
```

- [ ] **Step 2: Parse-check the script with the PowerShell parser**

Run:
```bash
cd /projects/actionc-no-as-a-service
pwsh -NoProfile -Command '$errs=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ./install.ps1).Path, [ref]$null, [ref]$errs) | Out-Null; if ($errs) { $errs | ForEach-Object { $_.Message }; exit 1 } else { "install.ps1: parse OK" }'
```
Expected: `install.ps1: parse OK` (no syntax errors). Full execution needs Windows (`$env:LOCALAPPDATA`, user-PATH writes); this confirms the script is well-formed.

- [ ] **Step 3: Commit**

```bash
cd /projects/actionc-no-as-a-service
git add install.ps1
git commit -m "Add Windows PowerShell installer with auto PATH update"
```

---

## Task 5: Windows smoke test (`test.ps1`)

**Files:**
- Create: `test.ps1`

- [ ] **Step 1: Write `test.ps1`**

Create `test.ps1`:

```powershell
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
```

- [ ] **Step 2: Parse-check the script with the PowerShell parser**

Run:
```bash
cd /projects/actionc-no-as-a-service
pwsh -NoProfile -Command '$errs=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ./test.ps1).Path, [ref]$null, [ref]$errs) | Out-Null; if ($errs) { $errs | ForEach-Object { $_.Message }; exit 1 } else { "test.ps1: parse OK" }'
```
Expected: `test.ps1: parse OK`.

- [ ] **Step 3: Commit**

```bash
cd /projects/actionc-no-as-a-service
git add test.ps1
git commit -m "Add Windows post-install smoke test"
```

---

## Task 6: README — macOS + Windows sections

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Install section**

In `README.md`, replace the section that currently starts with `## 🛠️ Install (Pop!_OS / Ubuntu)` and ends just before `## 📁 Project structure` with the following:

````markdown
## 🛠️ Install

`naas` ships a prebuilt, platform-independent `naas.class` (JVM bytecode), so installing
needs only a **JDK 21 runtime** — no compiler, no Python. (Maintainers regenerate the class
with `./build.sh`; see *Rebuilding* below.)

### Linux / macOS

```bash
git clone <this repo>
cd actionc-no-as-a-service
./install.sh
```

The installer auto-detects a JDK 21 (`$JAVA_HOME`, then platform-standard locations — on
macOS `/usr/libexec/java_home`, on Linux `/usr/lib/jvm` and `~/tools` — then `java` on PATH),
bakes the resolved path into the wrapper, stages the class + data into
`~/.local/share/naas/`, and installs a `naas` wrapper into `~/.local/bin/`.

If `~/.local/bin` isn't on your `PATH`, the installer prints the line to add:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verify: `./test.sh && naas`

### Windows (PowerShell)

```powershell
git clone <this repo>
cd actionc-no-as-a-service
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The installer detects a JDK 21 (`$env:JAVA_HOME`, then `java` on PATH), stages the class +
data into `%LOCALAPPDATA%\naas\`, installs a `naas.cmd` wrapper into `%LOCALAPPDATA%\naas\bin`,
and **adds that directory to your user PATH** automatically. Open a new terminal, then:

```powershell
.\test.ps1
naas
```

> **Note:** the macOS and Windows installers are authored and statically checked on a Linux
> development machine but have not been run on real macOS / Windows hardware. Run `test.sh`
> (macOS) or `test.ps1` (Windows) after installing to confirm.

### Rebuilding (maintainers)

`naas.class` and `reasons.txt` are committed. Regenerate them after editing `naas.actionc` or
`reasons.json` — requires Linux, a JDK 21, python3, and the ActionC compiler jar
(auto-detected at `../ActionC` or via `ACTIONC_JAR`):

```bash
./build.sh
git add naas.class reasons.txt
```
````

- [ ] **Step 2: Update the Project structure block**

In `README.md`, replace the `## 📁 Project structure` code block with:

````markdown
```
actionc-no-as-a-service/
├── naas.actionc        # the program (ActionC)
├── naas.class          # prebuilt JVM bytecode (committed; regenerated by build.sh)
├── reasons.json        # 1000+ rejection reasons (canonical source)
├── reasons.txt         # generated, pipe-delimited runtime data (committed)
├── tools/gen-reasons.py# regenerates reasons.txt from reasons.json
├── bin/naas.in         # POSIX wrapper template (Linux + macOS)
├── bin/naas.cmd.in     # Windows .cmd wrapper template
├── build.sh            # maintainer build: gen data + compile (Linux + ActionC)
├── install.sh          # install to ~/.local (Linux + macOS)
├── install.ps1         # install to %LOCALAPPDATA% (Windows)
├── test.sh             # smoke test (Linux + macOS)
├── test.ps1            # smoke test (Windows)
└── README.md
```
````

- [ ] **Step 3: Update the "Editing the reasons" section**

In `README.md`, replace the body of `## ✏️ Editing the reasons` (the lines between that
heading and `## 🎬 How it works`) with:

````markdown
`reasons.json` is canonical. After editing it, rebuild the committed artifacts and re-install:

```bash
./build.sh        # regenerates reasons.txt and recompiles naas.class
./install.sh      # (or install.ps1 on Windows)
```
````

- [ ] **Step 4: Verify no stale single-platform phrasing remains**

Run:
```bash
cd /projects/actionc-no-as-a-service
grep -nI -e 'Pop!_OS / Ubuntu)' -e 'npm' -e 'express' README.md || echo "clean"
```
Expected: `clean` (the old single-platform install heading is gone; no Node references).

- [ ] **Step 5: Commit**

```bash
cd /projects/actionc-no-as-a-service
git add README.md
git commit -m "Document macOS + Windows install in README"
```

---

## Task 7: Final end-to-end verification

**Files:** none (verification only)

- [ ] **Step 1: Clean rebuild of artifacts + clean install (Linux)**

Run:
```bash
cd /projects/actionc-no-as-a-service
./build.sh
rm -rf "$HOME/.local/share/naas" "$HOME/.local/bin/naas"
./install.sh
./test.sh
```
Expected: `build.sh` rebuilds the artifacts; install prints `installed: ...`; `test.sh` prints `PASS: ...`.

- [ ] **Step 2: Parse-check both PowerShell scripts together**

Run:
```bash
cd /projects/actionc-no-as-a-service
for f in install.ps1 test.ps1; do
  pwsh -NoProfile -Command "\$e=\$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ./$f).Path, [ref]\$null, [ref]\$e) | Out-Null; if (\$e) { \$e | ForEach-Object { \$_.Message }; exit 1 } else { '$f: parse OK' }"
done
```
Expected: `install.ps1: parse OK` and `test.ps1: parse OK`.

- [ ] **Step 3: Confirm working tree is clean and review the log**

Run:
```bash
cd /projects/actionc-no-as-a-service
git status --short
git log --oneline -7
```
Expected: working tree clean (note: `naas.class` is now tracked and should NOT appear as modified after a fresh `build.sh` unless the program changed; `reasons.txt` likewise). The log shows the task commits in order.

- [ ] **Step 4 (if the tree is dirty): commit refreshed artifacts**

If `git status` shows `naas.class` or `reasons.txt` changed (build is deterministic, so this is unexpected, but if it happens):
```bash
cd /projects/actionc-no-as-a-service
git add naas.class reasons.txt
git commit -m "Refresh prebuilt artifacts"
```

---

## Self-review notes

- **Spec coverage:** build step + committed class (T1), unified Linux+macOS installer with
  OS-aware Java detection incl. the Linux hardcoded-path replacement (T2), Windows wrapper
  (T3), Windows installer with auto-PATH (T4), Windows smoke test (T5), README for macOS +
  Windows incl. the verification caveat (T6), end-to-end + parse-checks + clean tree (T7).
  Every spec section maps to a task.
- **Verification honesty (per spec):** Linux fully run here; macOS branch is `sh -n` +
  review; Windows `.ps1` are parse-checked under the installed `pwsh`; full Windows behavior
  is review-only. The README states this.
- **Naming consistency:** data dir `~/.local/share/naas` (POSIX) / `%LOCALAPPDATA%\naas`
  (Windows); bin `~/.local/bin/naas` / `%LOCALAPPDATA%\naas\bin\naas.cmd`; placeholders
  `@JAVA@` / `@DATADIR@` defined in T3 and substituted in T4; artifacts `naas.class` +
  `reasons.txt` produced in T1, consumed by T2 and T4.
- **No compile at install:** `install.sh`/`install.ps1` only copy committed artifacts; the
  ActionC compiler + python3 are needed only by `build.sh`.
