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
            for j in /usr/lib/jvm/*21*/bin/java "${HOME:-}"/tools/jdk-21*/bin/java; do
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
