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
