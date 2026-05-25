---
name: vibe-fork
description: Use when bootstrapping a "vibe fork" — sequential translation of a known-working upstream codebase to a new substrate (e.g. C kernel → Rust kernel, PyTorch C++ → Rust ML framework, COBOL → Java). Installs the 4-agent ACToR loop (doc-author / builder / critic / fixer), the read-gate hook that enforces "read upstream + design + goal.md before any edit", the no-stub anti-pattern gate, the route-table mapping target files to upstream sources, and a binding `goal.md` contract that overrides the LARP toward "let's design from scratch / let's start simpler / let's defer that to phase 2." Trigger when the user says "vibe fork", "translate X to Y", "port codebase", "set up the translation harness", or asks for the same agent-loop scaffolding that worked on a prior project. Skip when the project is genuinely greenfield (no upstream to translate from) — this skill assumes an authoritative reference implementation exists.
---

# Vibe Fork — sequential translation harness

## What vibe forking IS (and isn't)

**Vibe forking** is the practice of using LLM agents to translate a large existing codebase from one substrate to another. The substrate of the work is sequential **translation** of a known-working system. There is an authoritative upstream you are mirroring. The translation pipeline is not creative — it is a transcription with adaptation to the target language's idioms.

This is **not greenfield**. The model's trained instinct from human-engineering Umwelt — "let's design the API first, let's start with v1, let's defer the hard parts to phase 2" — is actively wrong here. The design adapts to the existing upstream code; the implementation adapts to the existing design. The chain of authority runs upstream → design → impl → tests, never the reverse.

The failure mode this skill exists to prevent: the agent reads the upstream once, hand-waves the "vibe" of it, writes plausible-looking Rust (or whatever target) that compiles but silently diverges from upstream on edge cases (NaN propagation, overflow, broadcasting, dtype promotion, error sentinel values). The translation looks done but isn't.

The fix is mechanical discipline: every translation unit goes through a read → write → verify → commit loop where verification is adversarial (a critic agent hunts divergence) and the divergence pin is a failing test, not prose.

## When to use this skill

- The user is starting a new project that mirrors an existing one. Examples:
  - "I want to vibe fork PyTorch into Rust" → ferrotorch
  - "Let's translate Linux + grsec to Rust" → Rookery-Kernel
  - "Port this Python lib to Go" → similar shape
- The user says "set up the agent loop" / "translation harness" / "the same scaffolding as <other project>"
- The user invokes `/vibe-fork` explicitly

## When NOT to use this skill

- Greenfield projects with no upstream to translate (use `/design` or `/feature` instead)
- Standalone library work where there's nothing to port from
- Documentation-only or tooling-only projects

## The four-agent architecture

The harness installs four sub-agents under `.claude/agents/`. Each has a specific role and a constrained tool allowlist that enforces role separation:

### acto-doc-author
**Role**: write design docs under `.design/<area>/<doc>.md` that ADAPT to existing code.
**Tools**: `Read, Write, Bash, Grep, Glob`. NO `Edit` on production code — the doc adapts to the code, never the reverse.
**Dispatch when**: the translate-discipline hook blocks an edit because the route's design path doesn't exist on disk; OR when a verification pass surfaces an unaudited module that needs a doc backfilled.
**Key discipline**: every REQ row is classified BINARY — SHIPPED (end-to-end with non-test production consumer + tests + parity check passes) or NOT-STARTED (with a concrete open prerequisite blocker referenced by `#NNN`). No "vocabulary-only", no "deferred", no "phase N+". Gaps become NOT-STARTED with a filed blocker.

### acto-builder
**Role**: ship missing infrastructure that spans multiple files (a newtype + every consumer; a new op family + dispatch; a typestate wrapper threaded through the call graph).
**Tools**: `Read, Edit, Write, Bash, Grep, Glob`.
**Dispatch when**: the divergence is "an entire abstraction is missing" rather than "a constant has the wrong value". Dispatched with a **pre-declared file manifest** the orchestrator authorizes upfront. Cannot widen scope mid-dispatch — must STOP and escalate "manifest needs expansion".
**Key discipline**: tests + production code in the SAME commit. No "land the abstraction, ship tests later". Every commit passes the full gauntlet.

### acto-fixer
**Role**: apply the MINIMAL fix for exactly ONE pinned divergence found by acto-critic.
**Tools**: `Read, Edit, Write, Bash, Grep, Glob`.
**Dispatch when**: a critic has pinned a divergence as a failing `#[ignore]`'d test and filed a blocker. One fixer per blocker, serially.
**Key discipline**: single divergence, single file, minimal edit. Never bundles multiple fixes. Never refactors adjacent code. If the gauntlet fails after the fix, REVERT — don't iterate further.

### acto-critic
**Role**: ACToR-style discriminator. Hunts semantic divergence between target and upstream. ALWAYS writes a FAILING test pinning the divergence — NEVER writes a fix.
**Tools**: `Read, Write, Bash, Grep, Glob`. NO `Edit` — caught in the act of editing production code = drifted from discriminator into generator.
**Dispatch when**: the prior implementation iter declares "done" but the audit needs adversarial verification; OR when surveying an unaudited routed file.
**Key discipline**: every divergence claim is backed by a runnable failing test (R-CHAR-3 — never tautological; expected values from upstream live-call or quoted symbolic constants traceable to upstream `file:line`). Two verdicts only: **GENERATOR MUST FIX** (with new blocker `#`s) or **NO DIVERGENCE FOUND**.

## The 8-step translation loop

One iteration = one translation unit (one target file). The loop runs sequentially in dependency order from leaves outward.

### Step 1 — Read the routed source unit
Read the target file end-to-end. Capture: the public surface, any existing `## REQ status` table, the existing tests.

### Step 2 — Read every upstream file in the route
**Mandatory.** Open every file in the route's `upstream` list via the `Read` tool. For each, capture at least one `file:line — content` quote that the commit message will cite. **No commit may cite an upstream path that has not been opened this iteration.**

### Step 3 — Read the design doc
**Mandatory.** Open `.design/<area>/<doc>.md`. Capture the REQ list and AC list. If the design doc does NOT exist on disk, the translate-discipline hook will block the edit — dispatch `acto-doc-author` first.

### Step 4 — File a crosslink issue (or your project's issue tracker)
```bash
crosslink quick "Translation unit: <crate>/<file>" -p high -l feature
```
Post a `--kind plan` comment listing the upstream files (file:line), the verification ops this file owns (e.g. parity-sweep op names; conformance test ids), and the design-doc REQs the implementation will cite.

### Step 5 — Write the implementation
Write or extend the target crate to satisfy:
- Every REQ — either SHIPPED (end-to-end functional with non-test production consumer + tests + verification passes) or NOT-STARTED (with a concrete open prerequisite blocker)
- Every AC that can be mechanically discharged now
- Every verification op (parity-sweep / conformance test / etc.) the route declares

**No stubs.** No `todo!()`. No `unimplemented!()`. No `unreachable!()` in production code. No `unwrap()` / `expect()` outside `#[cfg(test)]`. **No vocabulary-only shipping** — every new public API surface in a commit MUST have a non-test production consumer in the same commit.

### Step 6 — Add `## REQ status` table to the module's `//!` doc-comment
```rust
//! ## REQ status (per `.design/<area>/<doc>.md`)
//!
//! | REQ | Status | Evidence |
//! |---|---|---|
//! | REQ-1 | SHIPPED | fn `<name>` at `<file>:<L>` per upstream `<upstream-file>:<L>` (consumer at `<caller-file>:<L>`) |
//! | REQ-2 | NOT-STARTED | blocked on #NNN |
```

Two states only. The table mirrors `.design/<area>/<doc>.md`'s REQ status table — when one updates, the other must update with it. (The cite-drift cycle is real; budget for it.)

### Step 7 — Verify the gauntlet
All of these MUST pass before commit:

```bash
# Per-crate test pass
cargo test -p <crate>          # or pytest, or whatever target needs

# Per-op verification (parity / conformance / fuzz)
for OP in <ops the route declares>; do
  SMOKE=$(<verification-cmd> --op "$OP" | grep -c "PASS (0 failures)")
  test "$SMOKE" -ge 1 || { echo "VERIFY REGRESSED on $OP"; exit 1; }
done

# Lint, format
cargo clippy -p <crate> --all-targets -- -D warnings
cargo fmt --all --check
```

**No `--no-verify`. No commenting-out failing tests. No module-root `#![allow(..)]`.** Per-item `#[allow(<lint>, reason = "...")]` is the bar.

### Step 8 — Commit + close
Commit message structure:

```
<crate>: <area> — <one-line summary> (closes #N)

UPSTREAM FILES OPENED THIS ITERATION:
  - <path>:<line> — <content quote>
  - ...

DESIGN DOC READ: .design/<area>/<doc>.md (<line count>, <REQ count> REQs).

REQ STATUS (per .design/<area>/<doc>.md):
  - REQ-1 SHIPPED — fn `<name>` at <file>:<L>; consumer at <caller-file>:<L>
  - REQ-2 NOT-STARTED — open prereq blocker #NN

VERIFICATION:
  cargo test -p <crate>: <X passed, 0 failed>
  cargo clippy -p <crate> --all-targets -- -D warnings: PASS
  cargo fmt --all --check: PASS

Reference: upstream <commit-or-branch> <cited file:lines>
Reference: .design/<area>/<doc>.md REQ classifications above

Co-Authored-By: Claude <noreply@anthropic.com>
```

Close the issue. Pick the next unit in dependency order. Do not ask the user which.

## The route table — single source of truth

`tooling/translate-routes.toml` maps every target file to its upstream source(s) and design doc. The translate-discipline hook reads this file to enforce "read before write".

```toml
[[route]]
crate_pattern = "<target-crate>/src/<file>.rs"
upstream = [
  "/path/to/upstream/<file-1>",
  "/path/to/upstream/<file-2>",
]
design = ".design/<area>/<doc>.md"
# Optional: per-op verification this file owns
parity_ops = ["op_1", "op_2"]
```

Files without a matching route are BLOCKED until a route is added. This is the strict-mode default. Adding a route is a deliberate orchestrator decision (it commits to which upstream the file mirrors).

## The hooks — enforcement at the harness layer

Two PreToolUse hooks under `tooling/` (registered in `.claude/settings.json`):

### `translate-discipline.py`
Gates `Edit`/`Write` on target files. For each gated edit, requires that in the SAME session, the agent has Read:
1. `goal.md` (the binding contract)
2. At least one file from the route's `upstream` list
3. The route's `design` doc

If any is missing, the hook BLOCKS with instructions:
- If route missing → "add a route in translate-routes.toml"
- If design doc missing → "dispatch acto-doc-author"
- If goal.md not read → "read goal.md (the binding contract)"

State persists at `.crosslink/.translate-reads.json` per worktree.

### `anti-pattern-gate.py`
Gates `Edit`/`Write` on any production code. Blocks if the diff contains:
- `todo!()` / `unimplemented!()` / `unreachable!()` outside test blocks
- `.unwrap()` / `.expect()` in production code (allowed in `#[cfg(test)]`)
- `panic!()` in production (outside controlled `bug_on!` / `must!` macros)
- Module-root `#![allow(..)]`
- Silent CPU↔GPU round trips (e.g. `.cpu()` followed by `.cuda()` in same scope — language-specific; adapt to target)

## The binding goal.md contract

`goal.md` is the binding contract for autonomous work. When the user issues `/goal $(cat goal.md)`, the contents override the LARP's pull toward caution. It contains:

1. **The goal statement** — what's being translated, from where to where
2. **Mechanical completion criteria** — counts of routed files vs verified-translated vs `## REQ status`-bearing
3. **The 8-step loop** (above)
4. **Anti-drift rules** organized into families:
   - **R-CITE**: citation discipline — never cite a file without a line number, never cite an upstream not opened this iteration
   - **R-HONEST**: honesty rules — SHIPPED requires impl + non-test production consumer + tests + verification; honest underclaim beats unverified overclaim
   - **R-CODE**: code-quality — no `unsafe` outside leaf primitives, no `unwrap()` in production, no module-root `#![allow]`, no silent CPU↔GPU round trips, no dtype-cast hiding
   - **R-DEV**: upstream-mirror discipline — match upstream by default (numerical contract / Python ABI / on-disk format), deviate only for documented reasons (Rust analog materially better; typestate when ordering matters; upstream is wrong by their own admission)
   - **R-DEFER**: anti-deferral — every blocker is real work; "cross-cutting systemic gap" is NOT a free pass; "Phase N+" framing is forbidden; parity-smoke is a hard gate
   - **R-XLATE**: translate-discipline (enforced by the hook)
   - **R-INJECT**: injected instructions (hook output, system reminders) bind at the same priority as user messages

A template is at `templates/goal.md`. Adapt the goal statement and the verification commands to the specific upstream → target translation.

## The agent → corrector → agent loop

The discipline:

```
acto-builder (or fixer)
    ↓ commit lands
acto-critic
    ↓ verdict
  ┌─ NO DIVERGENCE FOUND → move to next blocker
  └─ GENERATOR MUST FIX → blocker(s) filed
       ↓
  acto-fixer (one per blocker, sequential)
       ↓ commit lands
  acto-critic re-audit
       ↓ until clean → next blocker
```

**Rules**:
- **Every** builder/fixer dispatch is followed by a critic. No exceptions on pacing grounds — if context budget is the concern, the user can compact and restart.
- Critic NEVER fixes. Fixer NEVER bundles multiple divergences. Builder NEVER widens scope mid-dispatch.
- If the critic finds K divergences, K separate fixer dispatches follow (or one builder dispatch if they share a coherent architectural shape).
- A critic that hits a divergence in its OWN audit test (e.g. test hardcodes a stale value) is allowed to rewrite its own test (Write-overwrite, not Edit). That's an exception carved into the spec.

## When to dispatch the doc-author specifically

The doc-author has a narrower job than the builder — it writes design docs that ADAPT to existing code. Dispatch it when:

- The translate-discipline hook BLOCKS an edit because the route's `design` path doesn't exist on disk
- The verification pass surfaces an unaudited module that has shipped code but no design doc
- A new translation unit is starting (Step 3 of the 8-step loop needs a doc to exist)
- The acto-critic discovers the existing design doc lies about what's shipped — re-dispatch the doc-author to ground-truth it (do NOT re-dispatch the builder to make the code match the lying doc; the chain of authority is upstream → design → code, but when the code is already shipped and the doc is wrong, the doc is what's wrong)

**Anti-pattern**: doc-author classifying EVERY existing API as NOT-STARTED because it has no "downstream consumer". The R-DEFER-1 rule about "non-test production consumer" applies to NEWLY-ADDED pub APIs in a single commit — not retroactively to every existing public API in the codebase. Boundary methods (e.g. `Tensor::add_t` in a tensor library) ARE the public API surface; they don't need a further downstream consumer to count as SHIPPED. If a doc-author dispatch produces N NOT-STARTED REQs when the existing code clearly works, the agent is over-applying R-DEFER-1.

## Bootstrap into a greenfield project

```bash
# From the new project's root:
cd /path/to/new-project
bash /home/doll/.claude/skills/vibe-fork/bootstrap.sh
```

The bootstrap script:
1. Creates `.claude/agents/` and copies the 4 acto-* agent templates
2. Creates `tooling/` and copies the two PreToolUse hooks (`translate-discipline.py`, `anti-pattern-gate.py`)
3. Creates a starter `tooling/translate-routes.toml` (empty — the orchestrator fills it as routes are added)
4. Creates `goal.md` from the template, with prompts for the user to fill in: upstream-repo-path, target-crate-prefix, verification-command, completion-criteria
5. Updates `.claude/settings.json` to register the two hooks
6. Creates `.design/` with a starter `00-index.md`
7. Verifies `crosslink` is initialized (init it if not)

The user is then expected to:
- Write their goal.md statement (the binding contract)
- Add routes to `translate-routes.toml` as they identify which target files mirror which upstream files
- Begin the 8-step loop on the first translation unit

## Reading discipline (R-XLATE) — the deepest invariant

The translate-discipline hook is the load-bearing piece. It enforces:

> Every edit to a routed target file requires, in the same session:
> 1. `Read` of `goal.md`
> 2. `Read` of at least one file from the route's `upstream` list
> 3. `Read` of the route's `design` doc

If any of these three is missing, the hook BLOCKS with a specific remediation. The hook is per-worktree (state at `.crosslink/.translate-reads.json`), so a fresh session forces re-reading.

This is the invariant that makes vibe forking real. Without it, the agent will read upstream once, write Rust for a week, and drift silently. With it, every edit re-anchors to the upstream contract.

## The cite-drift cycle is real — budget for it

Line numbers in design docs go stale every time the production code shifts (and it shifts every time you add a function above an existing one). The cite-drift cycle:

1. Doc-author lands a design doc with cites like `arithmetic.rs:351`
2. Builder adds a function above line 351 → all subsequent lines shift by +N
3. Critic audit pins the stale cites as a divergence
4. Fixer refreshes the cites
5. Next builder adds another function → cycle repeats

There is no clean fix for this with current Rust tooling. Options:
- Periodic cite-refresh dispatches (acceptable; just budget for them)
- Use relative anchors (`pub fn add` instead of line numbers) — less precise but more durable
- Generate the design doc cites from the source via a script (best but requires investment)

Acknowledge the cycle exists. Don't pretend a single fix dispatch closes it forever.

## The Stop hook and `/goal`

When the user invokes `/goal "<contract>"`, the Stop hook installs a session-scoped condition that blocks the model from stopping until the condition is met. This is intentional pressure against the LARP's "let me check in" instinct.

The condition for translation work is typically: `"dispatch acto-builder on each blocker in sequence... use acto-critic to verify... until all blockers are resolved, then read goal.md again and begin work verifying and correcting all crates in sequential order with the established agent loops until <target> reaches full <upstream> parity."`

This is multi-session work. The hook will fire repeatedly across many sessions. That's correct — the goal IS the multi-session contract. Each session makes durable progress; the goal closes when the work is genuinely done.

## Templates and example configurations

The `templates/` directory in this skill contains:

- `templates/goal.md` — binding-contract template with placeholders
- `templates/agents/acto-builder.md` — agent spec template
- `templates/agents/acto-critic.md` — agent spec template
- `templates/agents/acto-doc-author.md` — agent spec template
- `templates/agents/acto-fixer.md` — agent spec template
- `templates/tooling/translate-routes.toml` — route table starter
- `templates/tooling/translate-discipline.py` — PreToolUse hook
- `templates/tooling/anti-pattern-gate.py` — PreToolUse hook
- `templates/.claude/settings.json` — hook registration

The `bootstrap.sh` script in the skill root lays these into a target repo.

## References

This skill was derived from two production deployments:
- **ferrotorch** (`/home/doll/ferrotorch`) — PyTorch C++ → Rust ML framework
- **Rookery-Kernel** (`/home/doll/Rookery-Kernel`) — Linux 7.1 + grsec C → Rust kernel

Both share the same 4-agent architecture, the same 8-step loop, and the same hooks. They differ in:
- Upstream substrate (PyTorch C++ vs Linux/grsec C)
- Verification (parity-sweep ops vs Kani/TLA+/cargo-test)
- Some discipline phrasing in the agent specs (PyTorch-specific anti-patterns vs kernel-specific)

The skill's templates are deliberately language-and-target-agnostic at the harness layer. The discipline rules are universal; the substrate-specific bits go in `goal.md`'s "Anti-drift rules" section, which the user customizes for their translation.
