#!/usr/bin/env bash
# Create a disposable test graph for the desktop PoC (desktop/target/dev-graph).
# Contains the Phase 0 fixture cases: namespace subdir, fenced [[ref]], inline
# id::, property-zone id::, TODO, multi-line block, journal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$ROOT/desktop/target/dev-graph"
rm -rf "$G"; mkdir -p "$G/pages/deep" "$G/journals"

cat > "$G/pages/Alpha.md" <<'EOF'
type:: note
status:: active

- Alpha intro with #tag1 and link to [[Beta]]
	- child block with multi-line continuation
	  second line here
- TODO test task state
- code fence pollution test
	- ```bash
	  [[NotARealPage]] inside fence
	  ```
- multi-line block after fence
  still same block
EOF

cat > "$G/pages/Beta.md" <<'EOF'
- Beta links back to [[Alpha]] and to [[deep/Nested Page]]
- block with property-zone uuid
  id:: aabbccdd-1111-2222-3333-444455556666
	- child of the referenced block
EOF

printf -- '- Nested page under namespace\n- refs [[Alpha]]\n' > "$G/pages/deep/Nested Page.md"
cat > "$G/journals/2026_01_01.md" <<'EOF'
- journal entry one
	- indented sub-thought
EOF

echo "dev graph ready: $G"
echo "run:  LOGSEQ_GRAPH=\"$G\" cargo tauri dev"
