# NaaS ActionC CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-write `no-as-a-service` from a Node/Express HTTP service into a pure-ActionC CLI that prints a random rejection reason, installed as a `naas` command on Pop!_OS/Ubuntu.

**Architecture:** A single ActionC program (`naas.actionc`) reads a pipe-delimited reasons file, splits it, picks a random index, and prints one reason. A python3 generator produces the data file from canonical `reasons.json`. An idempotent `install.sh` compiles the program with the ActionC compiler and installs a wrapper script (with a baked-in `java` path) to `~/.local/bin/naas`, staging the compiled class + data into `~/.local/share/naas/`.

**Tech Stack:** ActionC (compiled to JVM bytecode via `/projects/ActionC/target/scala-2.12/ActionC.jar`), JDK 21, python3 (data gen), POSIX shell (install + wrapper).

---

## Environment constants (used throughout)

- ActionC compiler jar: `/projects/ActionC/target/scala-2.12/ActionC.jar` (already built).
- JDK 21: `/home/pwood/tools/jdk-21.0.11+10` (not on default PATH).
- Run the compiler: `java -jar <jar> naas.actionc` → produces `naas.class`.
- Run the compiled program: `java naas` (plain JDK, jar NOT needed); reads `reasons.txt` from the **current working directory**.
- Install targets: wrapper → `~/.local/bin/naas`; staged artifacts → `~/.local/share/naas/`.

To get a usable shell for any manual compile/run during implementation:
```bash
export JAVA_HOME=/home/pwood/tools/jdk-21.0.11+10
export PATH="$JAVA_HOME/bin:$PATH"
```

## File structure (created / modified / removed)

| Action | Path | Responsibility |
|---|---|---|
| Create | `naas.actionc` | The program: read → split → random → print. |
| Create | `tools/gen-reasons.py` | Generate `reasons.txt` from `reasons.json`. |
| Create | `reasons.txt` | Generated runtime data (pipe-joined, single line). Committed. |
| Create | `bin/naas.in` | Wrapper template; `@JAVA@` / `@DATADIR@` placeholders. |
| Create | `install.sh` | Build + install, idempotent. |
| Create | `test.sh` | Post-install smoke test. |
| Modify | `README.md` | Rewrite for the ActionC CLI. |
| Keep | `reasons.json`, `assets/`, `LICENSE` | Canonical data, banner, license. |
| Remove | `index.js`, `package.json`, `Dockerfile`, `.dockerignore`, `.devcontainer.json` | Only served the deferred HTTP API. |

---

## Task 1: The ActionC program

**Files:**
- Create: `naas.actionc`
- Test (manual, temp): a tiny fixture `reasons.txt` to compile + run against.

- [ ] **Step 1: Write a temporary 4-line fixture to test against**

```bash
cd /projects/actionc-no-as-a-service
printf 'alpha reason|beta reason|gamma reason|delta reason' > reasons.txt
```

- [ ] **Step 2: Write the program**

Create `naas.actionc`:

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

- [ ] **Step 3: Compile and verify it produces a class**

Run:
```bash
export JAVA_HOME=/home/pwood/tools/jdk-21.0.11+10
export PATH="$JAVA_HOME/bin:$PATH"
java -jar /projects/ActionC/target/scala-2.12/ActionC.jar naas.actionc
ls naas.class
```
Expected: `naas.class` exists, no parser/compiler errors printed.

- [ ] **Step 4: Run it several times and verify varied, non-empty output**

Run:
```bash
for i in 1 2 3 4 5; do java naas; done
```
Expected: 5 lines, each one of `alpha reason` / `beta reason` / `gamma reason` / `delta reason`, with variation across runs.

- [ ] **Step 5: Clean up build artifacts (don't commit the temp fixture or class yet)**

Run:
```bash
rm -f naas.class reasons.txt
```
(`reasons.txt` is regenerated for real in Task 2; `naas.class` is a build output.)

- [ ] **Step 6: Commit the program**

```bash
git add naas.actionc
git commit -m "Add naas.actionc: pick and print a random reason"
```

---

## Task 2: Data generator + generated data file

**Files:**
- Create: `tools/gen-reasons.py`
- Create: `reasons.txt` (generated)

- [ ] **Step 1: Write the generator**

Create `tools/gen-reasons.py`:

```python
#!/usr/bin/env python3
"""Generate reasons.txt (pipe-joined, single line) from canonical reasons.json.

The ActionC program splits on '|'. No reason in reasons.json contains a pipe,
newline, or tab, so a single-line pipe-joined file is unambiguous. We assert
that invariant rather than trust it.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
src = ROOT / "reasons.json"
dst = ROOT / "reasons.txt"

reasons = json.loads(src.read_text(encoding="utf-8"))
if not isinstance(reasons, list) or not reasons:
    sys.exit("reasons.json must be a non-empty JSON array")

bad = [r for r in reasons if "|" in r or "\n" in r or "\t" in r]
if bad:
    sys.exit(f"{len(bad)} reason(s) contain a pipe/newline/tab; pick a different delimiter")

dst.write_text("|".join(reasons), encoding="utf-8")
print(f"wrote {dst} ({len(reasons)} reasons, {dst.stat().st_size} bytes)")
```

- [ ] **Step 2: Make it executable and run it**

Run:
```bash
chmod +x tools/gen-reasons.py
python3 tools/gen-reasons.py
```
Expected: `wrote .../reasons.txt (1055 reasons, 63378 bytes)` (byte count may differ slightly if the dataset changed; reason count should match `reasons.json`).

- [ ] **Step 3: Verify the program runs against the real data**

Run:
```bash
export JAVA_HOME=/home/pwood/tools/jdk-21.0.11+10
export PATH="$JAVA_HOME/bin:$PATH"
java -jar /projects/ActionC/target/scala-2.12/ActionC.jar naas.actionc
for i in 1 2 3; do java naas; done
rm -f naas.class
```
Expected: 3 real rejection reasons from the dataset, varied, including correct unicode (em-dashes / curly quotes render correctly).

- [ ] **Step 4: Commit generator + data**

```bash
git add tools/gen-reasons.py reasons.txt
git commit -m "Add reasons.txt generator and generated data"
```

---

## Task 3: Wrapper template

**Files:**
- Create: `bin/naas.in`

- [ ] **Step 1: Write the wrapper template**

Create `bin/naas.in`:

```sh
#!/bin/sh
# naas — print a random rejection reason. Generated by install.sh.
# The compiled ActionC program reads reasons.txt relative to the process
# working directory, so we cd into the staged data dir before running.
set -e
DATADIR="@DATADIR@"
cd "$DATADIR"
exec "@JAVA@" naas
```

- [ ] **Step 2: Commit the template**

```bash
git add bin/naas.in
git commit -m "Add naas wrapper template"
```

(No standalone test here — exercised by `install.sh` in Task 4 and `test.sh` in Task 5.)

---

## Task 4: Install script

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write the installer**

Create `install.sh`:

```sh
#!/bin/sh
# Build the ActionC program and install the `naas` command to ~/.local/bin.
# Idempotent: safe to re-run.
set -eu

REPO=$(CDPATH= cd "$(dirname "$0")" && pwd)
BINDIR="$HOME/.local/bin"
DATADIR="$HOME/.local/share/naas"

# 1. Resolve a JDK 21 `java`.
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JAVA="$JAVA_HOME/bin/java"
elif [ -x /home/pwood/tools/jdk-21.0.11+10/bin/java ]; then
    JAVA="/home/pwood/tools/jdk-21.0.11+10/bin/java"
elif command -v java >/dev/null 2>&1; then
    JAVA=$(command -v java)
else
    echo "error: no Java found. Install JDK 21 or set JAVA_HOME." >&2
    exit 1
fi

# 2. Resolve the ActionC compiler jar (build-time only).
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

# 3. Generate the data file from canonical reasons.json.
python3 "$REPO/tools/gen-reasons.py"

# 4. Compile naas.actionc -> naas.class (in the repo dir).
( cd "$REPO" && "$JAVA" -jar "$JAR" naas.actionc )

# 5. Stage compiled class + data.
mkdir -p "$DATADIR"
cp "$REPO/naas.class" "$DATADIR/naas.class"
cp "$REPO/reasons.txt" "$DATADIR/reasons.txt"
rm -f "$REPO/naas.class"   # don't leave a build artifact in the repo

# 6. Render the wrapper with the resolved java path + data dir.
mkdir -p "$BINDIR"
sed -e "s#@JAVA@#$JAVA#g" -e "s#@DATADIR@#$DATADIR#g" \
    "$REPO/bin/naas.in" > "$BINDIR/naas"
chmod +x "$BINDIR/naas"

echo "installed: $BINDIR/naas"

# 7. PATH check (non-fatal).
case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *) echo "note: $BINDIR is not on your PATH. Add to ~/.bashrc:" >&2
       echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2 ;;
esac
```

- [ ] **Step 2: Make executable and run it**

Run:
```bash
chmod +x install.sh
./install.sh
```
Expected: prints resolved `java`/`ActionC` paths, the gen-reasons line, `installed: /home/pwood/.local/bin/naas`. No errors. (A PATH note may appear — that's fine.)

- [ ] **Step 3: Verify the installed command works from an unrelated cwd**

Run:
```bash
cd /tmp && /home/pwood/.local/bin/naas
cd /projects/actionc-no-as-a-service
```
Expected: one real rejection reason printed (proves the wrapper's `cd` makes data resolution location-independent).

- [ ] **Step 4: Verify idempotency (re-run install)**

Run:
```bash
./install.sh && /home/pwood/.local/bin/naas
```
Expected: completes cleanly again, prints a reason.

- [ ] **Step 5: Commit the installer**

```bash
git add install.sh
git commit -m "Add install.sh: build and install the naas command"
```

---

## Task 5: Smoke test

**Files:**
- Create: `test.sh`

- [ ] **Step 1: Write the test**

Create `test.sh`:

```sh
#!/bin/sh
# Post-install smoke test for the `naas` command.
set -eu

NAAS="$HOME/.local/bin/naas"
[ -x "$NAAS" ] || { echo "FAIL: $NAAS not installed (run ./install.sh)"; exit 1; }

# Run 10x: each line must be non-empty; collect for a variation check.
out=$(mktemp)
i=0
while [ "$i" -lt 10 ]; do
    line=$("$NAAS")
    [ -n "$line" ] || { echo "FAIL: empty output on run $i"; exit 1; }
    echo "$line" >> "$out"
    i=$((i + 1))
done

# Expect more than one distinct reason across 10 runs (random index works).
distinct=$(sort -u "$out" | wc -l)
rm -f "$out"
[ "$distinct" -gt 1 ] || { echo "FAIL: no variation across 10 runs"; exit 1; }

# Runs from an unrelated cwd (wrapper cd makes it location-independent).
( cd / && "$NAAS" >/dev/null ) || { echo "FAIL: errored from cwd=/"; exit 1; }

echo "PASS: naas prints varied, non-empty reasons ($distinct distinct in 10 runs)"
```

- [ ] **Step 2: Make executable and run it**

Run:
```bash
chmod +x test.sh
./test.sh
```
Expected: `PASS: naas prints varied, non-empty reasons (N distinct in 10 runs)` with N > 1, exit 0.

- [ ] **Step 3: Commit the test**

```bash
git add test.sh
git commit -m "Add post-install smoke test"
```

---

## Task 6: Remove the Node/Docker service files

**Files:**
- Remove: `index.js`, `package.json`, `Dockerfile`, `.dockerignore`, `.devcontainer.json`

- [ ] **Step 1: Remove the files**

Run:
```bash
git rm index.js package.json Dockerfile .dockerignore .devcontainer.json
```
Expected: git stages 5 deletions.

- [ ] **Step 2: Confirm nothing else references them**

Run:
```bash
grep -rIl --exclude-dir=.git -e 'index.js' -e 'package.json' -e 'Dockerfile' . || echo "no stray references"
```
Expected: only `README.md` may match (rewritten in Task 7) and/or the spec/plan docs (historical, fine). Note any matches to fix in Task 7.

- [ ] **Step 3: Commit the removals**

```bash
git commit -m "Remove Node/Express HTTP service (replaced by ActionC CLI)"
```

---

## Task 7: Rewrite the README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README.md**

Replace the contents of `README.md` with the following (keep the banner image and the Author/License/Testimonials flavor; replace all API/self-host/Node sections with the ActionC CLI):

````markdown
# ❌ No-as-a-Service — ActionC edition

<p align="center">
  <img src="https://raw.githubusercontent.com/hotheadhacker/no-as-a-service/main/assets/imgs/naas-with-no-logo-bunny.png" width="800" alt="No-as-a-Service Banner"/>
</p>

Ever needed a graceful way to say "no"? This is the same 1000+ creative rejection
reasons — re-implemented as a **command-line tool written in
[ActionC](https://github.com/lhartikk/ArnoldC)**, an esoteric language whose keywords are
action-movie one-liners. Run `naas`, get a `no`.

> **Why a CLI and not the API?** ActionC compiles to JVM bytecode and has no networking
> primitive, so the original Express `/no` HTTP endpoint can't be reproduced in pure
> ActionC. Reviving an HTTP interface is tracked as a separate future effort. The local
> `naas` command is the supported interface today.

---

## 🚀 Usage

```bash
naas
```

```
This feels like something Future Me would yell at Present Me for agreeing to.
```

Prints one random rejection reason to stdout and exits. Use it in shell scripts, aliases,
git hooks, or whenever you need a polite (or witty) no.

---

## 🛠️ Install (Pop!_OS / Ubuntu)

**Requirements:** JDK 21 and python3. The build also needs the ActionC compiler jar
(`ActionC.jar`); the installer auto-detects it next to this repo (`../ActionC`) or via the
`ACTIONC_JAR` environment variable.

```bash
git clone <this repo>
cd actionc-no-as-a-service
./install.sh
```

This:
1. generates `reasons.txt` from `reasons.json`,
2. compiles `naas.actionc` to a `.class` with the ActionC compiler,
3. stages the class + data into `~/.local/share/naas/`,
4. installs a `naas` wrapper (with the resolved `java` path baked in) into
   `~/.local/bin/`.

If `~/.local/bin` isn't on your `PATH`, the installer tells you the line to add:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verify the install:

```bash
./test.sh
naas
```

---

## 📁 Project structure

```
actionc-no-as-a-service/
├── naas.actionc        # the program (ActionC)
├── reasons.json        # 1000+ rejection reasons (canonical source)
├── reasons.txt         # generated, pipe-delimited runtime data
├── tools/gen-reasons.py# regenerates reasons.txt from reasons.json
├── bin/naas.in         # wrapper template (java path + data dir baked at install)
├── install.sh          # build + install to ~/.local
├── test.sh             # post-install smoke test
└── README.md
```

## ✏️ Editing the reasons

`reasons.json` is canonical. After editing it, regenerate and re-install:

```bash
python3 tools/gen-reasons.py
./install.sh
```

## 🎬 How it works

`naas.actionc` reads `reasons.txt`, splits it on `|` into an array, picks a random index
with `GO AHEAD MAKE MY DAY`, and prints the reason with `TALK TO THE HAND`. The compiled
class runs on a plain JDK — the ActionC compiler is only needed at build time.

---

## 👤 Author

Original No-as-a-Service by [hotheadhacker](https://github.com/hotheadhacker).
ActionC port: an exercise in saying "no" via action-movie bytecode.

## 📄 License

MIT — do whatever, just don't say yes when you should say no.

## 🐧 Testimonials

> "I tried to integrate No-as-a-Service into the Linux kernel to reject bad patches
> automatically, but it started rejecting my own commits. 10/10, absolutely ruthless."
>
> — **Linus Torvalds** (probably)
````

- [ ] **Step 2: Verify no stale references remain**

Run:
```bash
grep -nI -e 'npm' -e 'index.js' -e 'express' -e 'PORT=' README.md || echo "clean"
```
Expected: `clean` (no Node/Express/npm references left in the README body).

- [ ] **Step 3: Commit the README**

```bash
git add README.md
git commit -m "Rewrite README for the ActionC CLI"
```

---

## Task 8: Final end-to-end verification

**Files:** none (verification only)

- [ ] **Step 1: Clean rebuild from scratch**

Run:
```bash
rm -rf "$HOME/.local/share/naas" "$HOME/.local/bin/naas"
./install.sh
```
Expected: installs cleanly, `installed: /home/pwood/.local/bin/naas`.

- [ ] **Step 2: Run the smoke test**

Run:
```bash
./test.sh
```
Expected: `PASS: naas prints varied, non-empty reasons (...)`.

- [ ] **Step 3: Confirm working tree is clean and review the log**

Run:
```bash
git status --short
git log --oneline -8
```
Expected: no uncommitted changes (note: `naas.class` must NOT appear — it's removed by install; if it shows up, add it to `.gitignore` and commit). The log shows the task commits in order.

- [ ] **Step 4 (if needed): gitignore build artifacts**

If `git status` shows `naas.class`:
```bash
printf 'naas.class\n' >> .gitignore
git add .gitignore
git commit -m "Ignore naas.class build artifact"
```

---

## Self-review notes

- **Spec coverage:** program (T1), data gen + reasons.txt (T2), wrapper template (T3),
  install.sh w/ JDK+jar resolution + ~/.local install + PATH warn (T4), verification/test.sh
  (T5), removal of Node/Docker files (T6), README rewrite (T7), end-to-end + clean-tree (T8).
  All spec sections map to a task.
- **Deferred per spec:** HTTP endpoint / rate-limit / CORS — intentionally not in any task.
- **Naming consistency:** delimiter `|` everywhere; staged dir `~/.local/share/naas`;
  wrapper placeholders `@JAVA@` / `@DATADIR@` defined in T3 and substituted in T4;
  data file `reasons.txt` produced in T2, consumed by T1's program and T4's stage step.
