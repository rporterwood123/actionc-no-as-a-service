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
    for j in /usr/lib/jvm/*21*/bin/java "${HOME:-}"/tools/jdk-21*/bin/java; do
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
