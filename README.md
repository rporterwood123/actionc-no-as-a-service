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
`ACTIONC_JAR` environment variable. If `java` isn't on your `PATH`, point the installer at
your JDK 21 with `JAVA_HOME=/path/to/jdk-21 ./install.sh`.

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
