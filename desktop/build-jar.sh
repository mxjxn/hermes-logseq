#!/usr/bin/env bash
# Build the logseqd sidecar for the Tauri desktop shell.
#
# Produces:
#   desktop/target/logseq-datalog.jar   executable uberjar (AOT-compiled core)
#   desktop/target/jrt/                 minimal jlink runtime (only with JLINK=1)
#
# Verified on Linux (JDK 21): 13 MB jar, 44 MB jlink runtime, 3.1s cold start,
# reads AND writes verified on the minimal runtime. See docs/PHASE0-AUDIT.md §4.
#
# Usage:
#   ./build-jar.sh            # uberjar only (dev fallback java = system java)
#   JLINK=1 ./build-jar.sh    # also build a jlink runtime to bundle
#
# Requirements: JDK 21+, Clojure CLI, unzip, jar (in JDK).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGSEQD="$ROOT/logseqd"
OUT="$ROOT/desktop/target"
CLASSES="$OUT/classes"

command -v java >/dev/null || { echo "ERROR: JDK (java) required"; exit 1; }
command -v clojure >/dev/null || { echo "ERROR: Clojure CLI required"; exit 1; }
command -v jar >/dev/null || { echo "ERROR: jar (from JDK) required"; exit 1; }

echo "== classpath =="
# NOTE: deps.edn :paths is ["src"] (relative), so every java/clojure invocation
# below must run with cwd=$LOGSEQD or the classpath's relative 'src' won't resolve.
CP="$(cd "$LOGSEQD" && clojure -Spath -M:run)"
N_JARS="$(printf '%s' "$CP" | tr ':' '\n' | grep -c '\.jar$' || true)"
echo "   $N_JARS dependency jars"

echo "== AOT compile logseq-datalog.core =="
rm -rf "$OUT"
mkdir -p "$CLASSES"
(cd "$LOGSEQD" && java -cp "$CP" clojure.main -e "(binding [*compile-path* \"$CLASSES\"] (compile 'logseq-datalog.core))")

echo "== unpack dependencies =="
cd "$CLASSES"
UNZIP_LOG="$OUT/unzip.log"; : > "$UNZIP_LOG"
while IFS= read -r j; do
  [ -n "$j" ] || continue
  case "$j" in /*) : ;; *) continue ;; esac  # skip the relative 'src' entry
  if unzip -oq "$j" -x 'META-INF/*.SF' 'META-INF/*.DSA' 'META-INF/*.RSA' \
    'module-info.class' 'META-INF/versions/*/module-info.class' >> "$UNZIP_LOG" 2>&1; then
    echo "ok   $j" >> "$UNZIP_LOG"
  else
    echo "FAIL($?) $j" >> "$UNZIP_LOG"
  fi
done < <(printf '%s\n' "$CP" | tr ':' '\n')  # NOTE: trailing \n or read drops the last entry
echo "   $(grep -c '^ok' "$UNZIP_LOG" || true) jars ok, $(grep -c '^FAIL' "$UNZIP_LOG" || true) failed"
grep '^FAIL' "$UNZIP_LOG" || true

echo "== sources + manifest =="
cp -r "$LOGSEQD/src/"* .
printf 'Main-Class: logseq_datalog.core\n' > "$OUT/MANIFEST.MF"
jar cfm "$OUT/logseq-datalog.jar" "$OUT/MANIFEST.MF" .

echo "== smoke test (disposable graph, random port) =="
SMOKE_DIR="$OUT/smoke-graph"
rm -rf "$SMOKE_DIR"; mkdir -p "$SMOKE_DIR/pages" "$SMOKE_DIR/journals"
printf -- '- smoke test page\n- links [[Beta]]\n' > "$SMOKE_DIR/pages/Alpha.md"
SMOKE_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
java -jar "$OUT/logseq-datalog.jar" "$SMOKE_DIR" "$SMOKE_PORT" > "$OUT/smoke.log" 2>&1 &
SMOKE_PID=$!
for i in $(seq 1 60); do
  curl -sf -m 2 "http://127.0.0.1:$SMOKE_PORT/health" > "$OUT/smoke-health.json" 2>/dev/null && break
  sleep 0.5
done
if [ -s "$OUT/smoke-health.json" ]; then
  # verify a write, then stop
  curl -sf -m 5 -X POST "http://127.0.0.1:$SMOKE_PORT/append" \
    -H "Content-Type: application/edn" \
    -d '{:title "Alpha" :content "- write path verified"}' > /dev/null \
    && echo "   health+write OK ($(cat "$OUT/smoke-health.json"))" \
    || echo "   WARNING: health OK but write failed — inspect $OUT/smoke.log"
else
  echo "   WARNING: sidecar not healthy after 30s — inspect $OUT/smoke.log"
fi
kill "$SMOKE_PID" 2>/dev/null || true
wait "$SMOKE_PID" 2>/dev/null || true

if [[ "${JLINK:-0}" == "1" ]]; then
  echo "== jlink runtime =="
  MODULES="java.base,java.logging,java.naming,java.xml,java.sql,jdk.unsupported"
  jlink --add-modules "$MODULES" --output "$OUT/jrt" \
    --strip-debug --no-header-files --no-man-pages --compress zip-6
  echo "   $(du -sh "$OUT/jrt" | cut -f1) in $OUT/jrt"
fi

du -h "$OUT/logseq-datalog.jar"
echo "== stage into src-tauri/resources (tauri-build validates these at compile time) =="
RES="$ROOT/desktop/src-tauri/resources"
mkdir -p "$RES"
cp "$OUT/logseq-datalog.jar" "$RES/"
if [[ -d "$OUT/jrt" ]]; then
  rm -rf "$RES/jrt"
  cp -R "$OUT/jrt" "$RES/jrt"
fi
echo "   staged: $(ls "$RES")"
echo "done."
