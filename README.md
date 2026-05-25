# vibe-fork

A Claude Code skill for **sequential translation of a known-working upstream codebase to a new substrate** — e.g. C kernel → Rust kernel, PyTorch C++ → Rust ML framework, COBOL → Java.

It installs a 4-agent loop, two PreToolUse hooks, a route table, and a binding `goal.md` contract that together prevent the most common failure mode: the agent reads the upstream once, hand-waves the "vibe" of it, writes plausible-looking target-language code that compiles but silently diverges from upstream on edge cases (NaN propagation, overflow, broadcasting, dtype promotion, error sentinel values).

The fix is mechanical discipline: every translation unit goes through a read → write → verify → commit loop where verification is adversarial (a critic agent hunts divergence) and the divergence pin is a failing test, not prose.

## When to use

- "I want to vibe fork PyTorch into Rust"
- "Let's translate Linux + grsec to Rust"
- "Port this Python lib to Go"
- "Set up the same agent-loop scaffolding as the other project"

## When NOT to use

- Greenfield projects with no upstream to translate (use `/design` or `/feature` instead)
- Standalone library work where there's nothing to port from
- Documentation-only or tooling-only projects

## Install

Clone this repo somewhere persistent and symlink the skill into `~/.claude/skills/`:

```bash
git clone <this-repo> ~/src/vibe-fork
ln -s ~/src/vibe-fork/vibe-fork ~/.claude/skills/vibe-fork
```

Claude Code picks up the skill on next launch. Trigger it by saying "vibe fork", "translate X to Y", "port codebase", or invoking `/vibe-fork`.

## Bootstrap into a new project

```bash
cd /path/to/new-project   # must be a git repo
bash ~/.claude/skills/vibe-fork/bootstrap.sh
```

The script is idempotent — existing files are skipped, not overwritten. It lays down:

1. `.claude/agents/` — the four `acto-*` agent specs
2. `tooling/translate-discipline.py` + `tooling/anti-pattern-gate.py` — PreToolUse hooks
3. `tooling/translate-routes.toml` — route table starter
4. `goal.md` — the binding contract (customize placeholders)
5. `.design/00-index.md` — design-doc index
6. `.claude/settings.json` — hook registration

After bootstrap: customize `goal.md`, customize the hook constants (`UPSTREAM_ROOT`, `TARGET_CRATE_PREFIXES`), add your first route, and begin the loop on your first translation unit.

## What's inside

### The four agents

| Agent | Role | Tools |
|---|---|---|
| `acto-doc-author` | Writes design docs that ADAPT to existing code. No `Edit` on production. | `Read, Write, Bash, Grep, Glob` |
| `acto-builder` | Ships cross-cutting infrastructure with a pre-declared file manifest. | `Read, Edit, Write, Bash, Grep, Glob` |
| `acto-critic` | Hunts semantic divergence. Writes FAILING tests pinning each divergence. Never fixes. | `Read, Write, Bash, Grep, Glob` |
| `acto-fixer` | Applies the MINIMAL fix for ONE pinned divergence. Never bundles. | `Read, Edit, Write, Bash, Grep, Glob` |

The loop: `builder → critic → (fixer → critic)* → next unit`. Every builder/fixer dispatch is followed by a critic. No exceptions.

### The two hooks

- **`translate-discipline.py`** — gates `Edit`/`Write` on routed target files. Requires that in the SAME session the agent has Read (1) `goal.md`, (2) at least one upstream file from the route, and (3) the route's design doc. Per-worktree state at `.crosslink/.translate-reads.json`.
- **`anti-pattern-gate.py`** — blocks `todo!()` / `unimplemented!()` / `unreachable!()`, `.unwrap()` / `.expect()` outside `#[cfg(test)]`, `panic!()` in production, module-root `#![allow]`, and silent CPU↔GPU round trips.

### The route table

`tooling/translate-routes.toml` maps every target file to its upstream source(s) and design doc — the single source of truth the hook reads to enforce "read before write". Files without a matching route are blocked until one is added.

### The 8-step loop

1. Read the target file
2. Read every upstream file in the route
3. Read the design doc (or dispatch `acto-doc-author` if missing)
4. File an issue / plan comment listing upstream cites and verification ops
5. Write the implementation — no stubs, no `todo!()`, no vocabulary-only shipping
6. Update the `## REQ status` table in the module's `//!` doc-comment (SHIPPED or NOT-STARTED — two states only)
7. Run the gauntlet: per-crate tests, parity/conformance ops, clippy `-D warnings`, fmt check
8. Commit with the structured message (upstream files opened, design doc read, REQ status, verification results)

Full reference in [`vibe-fork/SKILL.md`](vibe-fork/SKILL.md).

## Repo layout

```
vibe-fork/
  SKILL.md              # full skill specification (loaded by Claude Code)
  bootstrap.sh          # idempotent installer for new projects
  templates/
    goal.md             # binding-contract template with placeholders
    agents/             # the four acto-* agent specs
    tooling/            # the two hooks + route-table starter
```

## Provenance

Derived from two production deployments that share the same architecture:

- **ferrotorch** — PyTorch C++ → Rust ML framework
- **Rookery-Kernel** — Linux 7.1 + grsec C → Rust kernel

The harness is language-and-target-agnostic. Substrate-specific rules go in `goal.md`'s "Anti-drift rules" section, which the user customizes per translation.

## License

See [LICENSE](LICENSE).
