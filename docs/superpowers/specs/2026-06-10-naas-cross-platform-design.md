# Cross-platform `naas` (Linux + macOS + Windows) — Design

**Date:** 2026-06-10
**Status:** Approved (design), pending implementation plan

## Summary

Extend the `naas` ActionC CLI to run on **macOS** and **Windows (PowerShell)** in addition
to Linux, and harden Java detection on Linux while doing so.

The compiled `naas.class` is **portable JVM bytecode** — it already runs unchanged on all
three operating systems given a JDK. The program (`naas.actionc`) therefore does not change.
All cross-platform work lives in three layers: a maintainer **build** step that produces the
committed artifacts, per-platform **install** scripts, and per-platform **wrapper** scripts.

This also resolves a Linux wart: the installer currently hardcodes a personal JDK path
(`/home/pwood/tools/jdk-21.0.11+10`). The new unified POSIX installer replaces it with proper
auto-detection.

## Goals

- `naas` installs and runs on macOS (POSIX) and Windows (PowerShell), printing a random
  rejection reason — same behavior as Linux.
- Replace the hardcoded Linux JDK fallback with OS-aware Java auto-detection (applies to
  Linux and macOS).
- Keep end users free of the build toolchain: macOS/Windows need only a JDK 21 runtime, not
  the ActionC compiler or Python.

## Non-goals

- HTTP service / networking (still deferred — ActionC has no socket primitive).
- Flags/options on `naas` (single-reason stdout only).
- Verifying the macOS and Windows scripts on real macOS/Windows hardware from this Linux
  development box (see **Testing & verification caveat**).

## Key decisions (resolved during brainstorming)

1. **Build model:** ship a **prebuilt `naas.class`**, committed to the repo. Installers on all
   platforms consume it; none compile at install time.
2. **Java lookup:** installers **auto-detect and bake an absolute `java` path** into the
   wrapper (robust even when `java` is not on PATH), failing loudly if no JDK 21 is found.
3. **Installer layout:** a maintainer **`build.sh`** (Linux, needs ActionC.jar) produces the
   committed `naas.class` + `reasons.txt`; thin installers consume them. One POSIX `install.sh`
   covers Linux + macOS; a PowerShell `install.ps1` covers Windows.
4. **Windows PATH:** the Windows installer **auto-updates the user PATH** (idempotently) so
   `naas` works in new shells immediately.

## Architecture

Two phases, cleanly separated:

- **Build (maintainer, Linux-only, occasional):** `build.sh` regenerates `reasons.txt` from
  `reasons.json` and compiles `naas.actionc` → `naas.class` using the ActionC compiler jar.
  Both artifacts are committed. Run only when `naas.actionc` or `reasons.json` changes.
- **Install (end user, per-platform, common):** copy the committed `naas.class` + `reasons.txt`
  into a per-user data dir, detect a JDK 21 `java`, and render a wrapper that `cd`s into the
  data dir and runs `java naas`.

### Components

| File | Status | Role |
|---|---|---|
| `naas.actionc` | unchanged | The program. Reads `reasons.txt` → split on `\|` → random index → print one. |
| `build.sh` | **new** | Maintainer build (needs ActionC.jar + python3 + JDK 21): `gen-reasons.py` → `reasons.txt`, then compile `naas.actionc` → `naas.class`. Leaves both committed in the repo root. |
| `naas.class` | **now committed** | Prebuilt JVM bytecode (removed from `.gitignore`). Consumed by every installer. |
| `reasons.txt` | already committed | Generated, pipe-joined runtime data. |
| `reasons.json` | unchanged | Canonical data source. |
| `tools/gen-reasons.py` | unchanged | Regenerates `reasons.txt`. Now invoked by `build.sh`, not `install.sh`. |
| `bin/naas.in` | unchanged | POSIX wrapper template (`@JAVA@`, `@DATADIR@`). Used on Linux + macOS. |
| `bin/naas.cmd.in` | **new** | Windows wrapper template — a `.cmd` shim (runnable from PowerShell and cmd.exe) with `@JAVA@` / `@DATADIR@` placeholders. |
| `install.sh` | **modified** | Unified POSIX installer for Linux + macOS. No compile: copies committed `naas.class` + `reasons.txt` → `~/.local/share/naas/`, renders `~/.local/bin/naas`. OS-aware Java detection. |
| `install.ps1` | **new** | Windows (PowerShell) installer: copy artifacts → `%LOCALAPPDATA%\naas`, render `naas.cmd` into a user bin dir, auto-update user PATH, bake absolute `java.exe` path. |
| `test.sh` | unchanged | Post-install smoke test (Linux + macOS). |
| `test.ps1` | **new** | Post-install smoke test (Windows/PowerShell). |
| `README.md` | modified | Add macOS + Windows install/usage sections. |

### Java auto-detection

`install.sh` detects the OS via `uname -s` and resolves an absolute `java`, baked into the
wrapper. Resolution order on both POSIX platforms:

1. `$JAVA_HOME/bin/java` if executable.
2. Platform probe:
   - **Linux:** first match of `/usr/lib/jvm/*21*/bin/java` then `$HOME/tools/jdk-21*/bin/java`.
     (This generalizes the old hardcoded `/home/pwood/tools/jdk-21.0.11+10` path into a glob
     of the same locations — the dev box still works, nothing personal is baked in.)
   - **macOS:** `/usr/libexec/java_home -v 21` (standard macOS mechanism), then
     `$(/usr/libexec/java_home)/bin/java`.
3. `command -v java`.
4. Else: fail loudly — "no JDK 21 found; install one or set JAVA_HOME."

`install.ps1` resolution order:

1. `$env:JAVA_HOME\bin\java.exe` if it exists.
2. `(Get-Command java -ErrorAction SilentlyContinue).Source`.
3. Else: fail loudly with the same guidance.

### Install locations

| Platform | Wrapper | Data dir |
|---|---|---|
| Linux / macOS | `~/.local/bin/naas` | `~/.local/share/naas/` (`naas.class`, `reasons.txt`) |
| Windows | `<userbin>\naas.cmd` (userbin = `%LOCALAPPDATA%\naas\bin`) | `%LOCALAPPDATA%\naas\` (`naas.class`, `reasons.txt`) |

### Data flow (runtime) — unchanged

```
naas                              # user runs the command (from any cwd)
  └─ wrapper: cd <data dir> && exec <java> naas
       └─ naas.class reads reasons.txt (cwd-relative, now the data dir)
            └─ split on "|" → array of reasons → random index → print one, exit 0
```

POSIX wrapper: `cd "$DATADIR"; exec "<java>" naas`.
Windows `.cmd` wrapper: `cd /d "<datadir>" && "<java>" naas`.

## Error handling

- **`build.sh`:** `set -eu`; fails loudly if ActionC.jar, python3, or a JDK 21 `java` is
  missing (resolves ActionC.jar via `$ACTIONC_JAR` → `../ActionC/target/scala-2.12/ActionC.jar`,
  same as today).
- **`install.sh`:** `set -eu`; clear message if no JDK 21 found; also fails if the committed
  `naas.class` / `reasons.txt` are absent (tells the user to run `./build.sh` first).
  Non-fatal PATH warning if `~/.local/bin` is absent from PATH (prints the `export` line).
- **`install.ps1`:** terminates with a clear message if no JDK 21 found or artifacts are
  missing. PATH update is idempotent (only appends the bin dir if not already present).

## Testing & verification caveat

This work is developed on a **Linux** box. Verification splits accordingly:

- **Fully verified here:** `build.sh` (compile + data gen), the Linux branch of `install.sh`
  (clean install → `test.sh` smoke test → run from an unrelated cwd), and that the committed
  `naas.class` runs on a plain JDK 21.
- **Authored but NOT executable here:** the macOS branch of `install.sh`, `install.ps1`,
  `bin/naas.cmd.in`, and `test.ps1`. These are verified by careful review plus static analysis
  where available — `shellcheck` for the POSIX scripts, `PSScriptAnalyzer` for PowerShell.
  The README flags them as authored-but-unverified-on-hardware; `test.sh` / `test.ps1` are
  provided so the user can confirm on real macOS / Windows machines.

`test.sh` (unchanged) and `test.ps1` each: run `naas` ~10×, assert non-empty output every
time, assert more than one distinct reason across runs (random index works), and run once from
an unrelated cwd to prove the wrapper's `cd` makes data resolution location-independent.

## Open decisions (resolved)

- Build model: **ship prebuilt `naas.class`** (committed).
- Java lookup: **auto-detect, bake absolute path.**
- Installer layout: **maintainer `build.sh` + thin per-platform installers** (unified POSIX
  for Linux+macOS, PowerShell for Windows).
- Linux JDK fallback: **replaced with auto-detection** (the requested runtime improvement).
- Windows PATH: **auto-update the user PATH** (idempotent).
