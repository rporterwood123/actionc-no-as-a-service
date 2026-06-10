# NaaS as a pure-ActionC CLI — Design

**Date:** 2026-06-10
**Status:** Approved (design), pending implementation plan

## Summary

Re-write `no-as-a-service` from a Node/Express HTTP service into a **pure-ActionC
command-line tool**. The new codebase is a single ActionC program (`naas.actionc`) that
reads the rejection-reason dataset, picks one at random, and prints it. A thin install
layer compiles the program and installs a `naas` command to the user's `PATH` on
Pop!_OS/Ubuntu.

The original HTTP API (`GET /no`, CORS, rate-limiting) is **deferred** — ActionC has no
networking/socket primitive, so the HTTP service cannot be reproduced in pure ActionC.
Reviving it is tracked as a separate future effort and is out of scope here.

## Goals

- Replace the Node codebase with ActionC as the project's implementation language.
- Compile the ActionC program successfully against the ActionC compiler.
- Provide a local `naas` command that prints a random rejection reason, installed and
  working on this Pop!_OS/Ubuntu machine.

## Non-goals (deferred)

- HTTP `/no` endpoint, rate-limiting, CORS — require a networking primitive that ActionC
  does not have. Flagged to the user; nothing needs to be added to ActionC for the CLI.
- Flags/options on `naas` (e.g. `--json`, `--count N`). Single-reason stdout only.

## Feasibility (verified 2026-06-10)

Smoke-tested end-to-end against the real 1055-reason dataset using
`/projects/ActionC/target/scala-2.12/ActionC.jar`:

- `WHAT'S IN THE BOX <path>` (`ReadFileNode`) reads file contents as a String.
- `DIVIDE AND CONQUER <name> <str> <delim>` splits into a String[] (literal delimiter via
  `Pattern.quote`).
- `HOW MANY OF THEM <arr>` yields the element count.
- `GO AHEAD MAKE MY DAY <bound>` (`RandomNode`) returns a random **int** in `[0, bound)`.
- `GET IN LINE <arr> AT <idx>` + `TALK TO THE HAND` reads and prints the element.
- Unicode (em-dashes `—`, curly quotes `'` `"`) survives read → split → print.
- The **compiled `naas.class` runs on a plain JDK 21** with the ActionC.jar **not** on the
  classpath. The ActionC.jar is a build-time-only dependency.
- `Files.readString` resolves the data path **relative to the process working directory**
  (not the classpath) — so the wrapper must `cd` into the data directory before running.

Delimiter choice: `|` (pipe). Zero reasons in `reasons.json` contain a pipe, newline,
backtick, or tab, so a single-line pipe-joined file is unambiguous.

## Architecture

### Components

| File | Role |
|---|---|
| `naas.actionc` | The program (the new codebase). Reads `reasons.txt` → split on `\|` → `random(count)` → print one reason. |
| `reasons.json` | **Canonical** data, kept (1055 reasons, matches upstream). |
| `reasons.txt` | Generated runtime data: all reasons joined by `\|` on a single line. Committed for a self-contained repo; regenerated from `reasons.json`. |
| `tools/gen-reasons.py` | Regenerates `reasons.txt` from `reasons.json` (python3, preinstalled on Pop!_OS/Ubuntu). |
| `bin/naas.in` | Wrapper-script template. Install bakes in the resolved `java` path and the data dir. |
| `install.sh` | Build + install to `~/.local`. Idempotent. |
| `test.sh` | Post-install smoke test. |
| `README.md` | Rewritten for the ActionC CLI. |

### Removed (only served the deferred HTTP API)

`index.js`, `package.json`, `Dockerfile`, `.dockerignore`, `.devcontainer.json`.

### Kept

`assets/` (README banner), `LICENSE`.

### `naas.actionc` (reference shape — verified to compile and run)

```actionc
IT'S SHOWTIME
    I HAVE COME HERE TO CHEW BUBBLEGUM content
    AND KICK ASS WHAT'S IN THE BOX "reasons.txt"
    DIVIDE AND CONQUER reasons content "|"
    HEY CHRISTMAS TREE count
    YOU SET US UP HOW MANY OF THEM reasons
    HEY CHRISTMAS TREE idx
    YOU SET US UP GO AHEAD MAKE MY DAY count
    TALK TO THE HAND GET IN LINE reasons AT idx
YOU HAVE BEEN TERMINATED
```

## Data flow (runtime)

```
naas                         # user runs the command (from any cwd)
  └─ wrapper: cd ~/.local/share/naas && exec <java> naas
       └─ naas.class reads reasons.txt (cwd-relative, now the data dir)
            └─ split on "|" → array of 1055 reasons
                 └─ GO AHEAD MAKE MY DAY count  -> random index [0,count)
                      └─ TALK TO THE HAND prints reasons[idx] to stdout, exit 0
```

## Build / install flow (`install.sh`)

1. **Resolve JDK 21**: `$JAVA_HOME/bin/java` → `/home/pwood/tools/jdk-21.0.11+10/bin/java`
   → `command -v java`. Fail loudly if none found.
2. **Resolve ActionC.jar**: `$ACTIONC_JAR` → `../ActionC/target/scala-2.12/ActionC.jar`
   → build via `sbt assembly` in the ActionC repo. Fail loudly if it can't be located/built.
3. **Generate data**: `tools/gen-reasons.py` → `reasons.txt`.
4. **Compile**: `java -jar <ActionC.jar> naas.actionc` → `naas.class`.
5. **Stage**: copy `naas.class` + `reasons.txt` → `~/.local/share/naas/`.
6. **Install wrapper**: render `bin/naas.in` with the resolved `java` path → `~/.local/bin/naas`,
   `chmod +x`. Warn if `~/.local/bin` is not on `PATH`.

Runtime needs only the baked `java` path; the ActionC.jar is not required to run `naas`.

## Error handling

- `install.sh`: `set -euo pipefail`; clear, actionable messages on missing JDK 21 / jar;
  non-fatal warning if `~/.local/bin` is absent from `PATH` (with the line to add).
- `naas.actionc`: minimal by nature (esolang). The wrapper's `cd` guarantees `reasons.txt`
  is found; the only normal-use failure is a broken/incomplete install, surfaced as a JVM
  exception.

## Verification (`test.sh`)

- Run `naas` ~10× — assert each prints non-empty output and exits 0.
- Confirm output varies across runs (random index is exercised).
- Run `naas` from an unrelated cwd to prove the wrapper's `cd` makes data resolution
  location-independent.

## Toolchain notes

- Build-time: JDK 21 + ActionC.jar (the compiler) + python3 (data gen).
- Runtime: a JDK 21 `java` only (path baked into the wrapper at install time).
- On this machine the JDK lives at `/home/pwood/tools/jdk-21.0.11+10` and is not on the
  default `PATH`; `install.sh` resolves and bakes the absolute path so `naas` works from a
  normal shell.

## Open decisions (resolved)

- HTTP service: **CLI now, HTTP as a separate future effort.**
- Install location: **`~/.local/bin/naas`** (user-level, no sudo).
- Node/Docker files: **removed** outright (not left as dead code).
- Data: **`reasons.json` canonical, `reasons.txt` generated.**
