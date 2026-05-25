#!/usr/bin/env bash
# vibe-fork bootstrap — lay the harness templates into a target repo.
#
# Usage:
#   cd /path/to/new-project
#   bash /home/doll/.claude/skills/vibe-fork/bootstrap.sh
#
# Idempotent: existing files are NOT overwritten; the script reports
# which ones already exist and which it created.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SKILL_DIR/templates"
TARGET_REPO="$(pwd)"

echo "vibe-fork bootstrap"
echo "  skill dir:    $SKILL_DIR"
echo "  target repo:  $TARGET_REPO"
echo ""

if [[ ! -d "$TARGET_REPO/.git" ]]; then
  echo "ERROR: $TARGET_REPO is not a git repository. Run 'git init' first."
  exit 1
fi

# Helper: copy template if target doesn't exist
copy_if_absent() {
  local src="$1"
  local dst="$2"
  if [[ -e "$dst" ]]; then
    echo "  SKIP   $dst (already exists)"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  CREATE $dst"
  fi
}

echo "[1/6] Creating .claude/agents/ ..."
copy_if_absent "$TEMPLATES/agents/acto-doc-author.md"  "$TARGET_REPO/.claude/agents/acto-doc-author.md"
copy_if_absent "$TEMPLATES/agents/acto-builder.md"     "$TARGET_REPO/.claude/agents/acto-builder.md"
copy_if_absent "$TEMPLATES/agents/acto-critic.md"      "$TARGET_REPO/.claude/agents/acto-critic.md"
copy_if_absent "$TEMPLATES/agents/acto-fixer.md"       "$TARGET_REPO/.claude/agents/acto-fixer.md"

echo ""
echo "[2/6] Creating tooling/ ..."
copy_if_absent "$TEMPLATES/tooling/translate-discipline.py" "$TARGET_REPO/tooling/translate-discipline.py"
copy_if_absent "$TEMPLATES/tooling/anti-pattern-gate.py"    "$TARGET_REPO/tooling/anti-pattern-gate.py"
copy_if_absent "$TEMPLATES/tooling/translate-routes.toml"   "$TARGET_REPO/tooling/translate-routes.toml"
chmod +x "$TARGET_REPO/tooling/translate-discipline.py" "$TARGET_REPO/tooling/anti-pattern-gate.py" 2>/dev/null || true

echo ""
echo "[3/6] Creating goal.md ..."
copy_if_absent "$TEMPLATES/goal.md" "$TARGET_REPO/goal.md"

echo ""
echo "[4/6] Creating .design/ ..."
mkdir -p "$TARGET_REPO/.design"
if [[ ! -e "$TARGET_REPO/.design/00-index.md" ]]; then
  cat > "$TARGET_REPO/.design/00-index.md" <<'EOF'
# Design index

This directory holds the per-translation-unit design docs. Each file
corresponds to a routed source file (see `tooling/translate-routes.toml`).

## Structure

```
.design/
  00-index.md             (this file)
  <area>/
    <doc>.md              (one per routed source file)
```

## Authoring

Design docs are authored by the `acto-doc-author` agent. They adapt to
existing code — quoted-code evidence from the source is mandatory. See
the agent spec at `.claude/agents/acto-doc-author.md`.
EOF
  echo "  CREATE $TARGET_REPO/.design/00-index.md"
else
  echo "  SKIP   $TARGET_REPO/.design/00-index.md (already exists)"
fi

echo ""
echo "[5/6] Registering hooks in .claude/settings.json ..."
if [[ -e "$TARGET_REPO/.claude/settings.json" ]]; then
  echo "  SKIP   .claude/settings.json exists; merge hooks manually."
  echo "         Template at: $TEMPLATES/.claude/settings.json"
else
  copy_if_absent "$TEMPLATES/.claude/settings.json" "$TARGET_REPO/.claude/settings.json"
fi

echo ""
echo "[6/6] Verifying crosslink ..."
if [[ ! -d "$TARGET_REPO/.crosslink" ]]; then
  echo "  WARNING: $TARGET_REPO/.crosslink does not exist."
  echo "  Initialize crosslink: run 'crosslink init' in this repo."
else
  echo "  OK     .crosslink/ exists"
fi

echo ""
echo "Bootstrap complete. Next steps:"
echo ""
echo "  1. Customize goal.md (search for <PROJECT-NAME>, <UPSTREAM-NAME>, etc.)"
echo "     File the PROJECT CUSTOMIZATION CHECKLIST at the bottom of goal.md."
echo ""
echo "  2. Customize tooling/translate-discipline.py and anti-pattern-gate.py:"
echo "     Edit the PROJECT CUSTOMIZATION constants at the top of each file"
echo "     (UPSTREAM_ROOT, TARGET_CRATE_PREFIXES, etc.)."
echo ""
echo "  3. Add your first route to tooling/translate-routes.toml."
echo ""
echo "  4. (Optional) Initialize crosslink if not already done: 'crosslink init'."
echo ""
echo "  5. Begin the 8-step loop on your first translation unit:"
echo "     - Read goal.md, the upstream source, and the (to-be-authored) design doc"
echo "     - Dispatch acto-doc-author for the first design doc"
echo "     - Dispatch acto-builder for the first translation unit"
echo "     - Dispatch acto-critic to audit, etc."
echo ""
echo "  Skill reference: $SKILL_DIR/SKILL.md"
