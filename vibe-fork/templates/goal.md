# <PROJECT-NAME> — Locked /goal Statement

This file is the binding contract for autonomous work on <PROJECT-NAME>. When the user issues `/goal $(cat goal.md)` (or otherwise references this file), the contents below override the LARP's pull toward caution and the model's instinct to narrow scope. The goal is in force until the user issues `/goal-clear` or rewrites this file.

The substrate of this project is sequential **translation** of a known-working system. Upstream is **<UPSTREAM-NAME>** (working tree at `<UPSTREAM-PATH>`). Target is the workspace (`<TARGET-CRATE-PATTERN>/src/**/*.<EXT>`). Most apparent divergence between target and upstream is a bug a prior translation pass introduced — silent boundary round-trips, wrong type promotion, missing kwargs, broken edge-case handling, math that compiled but doesn't compute the right thing. Every one of those is real work to do, not "out of scope."

---

## The goal

Work the strict **read → write → verify → commit** loop over every translation unit (source file) under `<TARGET-CRATE-PATTERN>/src/**/`, in dependency order from leaf crates outward. The goal is complete only when every routed source file has:

1. A closing commit citing the upstream file(s) actually opened that iteration, AND
2. The corresponding verification op(s) returning **0 failures** at the project's standard sample count, AND
3. A `## REQ status` table at the top-of-file doc-comment classifying every REQ as **SHIPPED** or **NOT-STARTED** with quoted-code evidence. Only two states exist: end-to-end satisfied by production code with a consumer (SHIPPED), or work hasn't begun / has a concrete open prerequisite blocker (NOT-STARTED). "Type exists but no consumer" is NOT-STARTED — the consumer is the open work item.

Verifiable mechanically:

```bash
# Count routed translation units:
python3 -c "import tomllib; print(len(tomllib.load(open('tooling/translate-routes.toml','rb'))['route']))"

# Count routed files with `## REQ status` doc-comment:
grep -l "## REQ status" $(python3 -c "import tomllib; [print(r['crate_pattern']) for r in tomllib.load(open('tooling/translate-routes.toml','rb'))['route']]") | wc -l

# When all counts agree AND every routed file's verification ops pass with 0 failures, the goal is complete.
```

---

## The eight-step loop (one iteration = one translation unit)

### Step 1 — Read the routed source unit
Read `<TARGET-CRATE-PATTERN>/src/<path>` end-to-end via the Read tool. Capture: the public surface, the `## REQ status` table if present, the existing tests.

### Step 2 — Read every upstream file in the route
**Mandatory.** Open every file in the route's `upstream` list at `<UPSTREAM-PATH>/<path>` via the Read tool. For each, capture at minimum one `file:line — content` quote that the commit message will cite. **No commit may cite an upstream path that has not been opened this iteration.** If a cited file is missing from `<UPSTREAM-PATH>/`, document the discrepancy and either (a) check the local clone is up to date or (b) fall back to a github URL with an explicit pinned commit.

### Step 3 — Read the design doc
**Mandatory.** Open `.design/<area>/<doc>.md` via the Read tool. Capture the REQ list and AC list. If the design doc does NOT exist on disk, the translate-discipline hook will block the edit — dispatch `acto-doc-author` first to author it, grounded in the existing code + the upstream source.

### Step 4 — File a crosslink issue
```bash
crosslink quick "Translation unit: <crate>/<file>.<ext>" -p high -l feature
```
Post a `--kind plan` comment listing the upstream files (file:line), the verification ops this file owns (from the route's `parity_ops` field), and the design-doc REQs the implementation will cite.

### Step 5 — Write the implementation
Write or extend the target crate to satisfy:
- Every REQ-N — either fully (**SHIPPED** — end-to-end functional with non-test production consumer + tests + verification verified) or **NOT-STARTED** (work hasn't begun OR has a concrete open prerequisite blocker).
- Every AC-N that can be mechanically discharged now.
- Every verification op named in the route's `parity_ops` field, with the per-op smoke (Step 7) returning 0 failures.

**No stubs.** No `todo!()` / `unimplemented!()` / `unreachable!()` in production. No `unwrap()` / `expect()` outside `#[cfg(test)]`. **No vocabulary-only shipping** — every public API surface added in a commit MUST have a non-test production consumer in the same commit, or the API isn't ready to ship.

The translation pipeline is sequential: we are translating a known-working system. There is no valid "ship the type, defer the consumer" path. If a REQ needs prerequisite work, the prerequisite IS the active blocker — file it concretely (`crosslink quick "Blocker for REQ-N of <area>: needs <prereq>" -p high -l blocker`) and work it. Do NOT mark the dependent REQ as a separate "deferred" status; it is simply NOT-STARTED until the prereq blocker closes and the consumer wiring lands.

### Step 6 — Add `## REQ status` table to module doc-comment
The module's top-level `//!` doc-comment must include a section like:

```rust
//! ## REQ status (per `.design/<area>/<doc>.md`)
//!
//! | REQ | Status | Evidence |
//! |---|---|---|
//! | REQ-1 | SHIPPED | fn `<name>` at `<file>:<L>` per upstream `<upstream-file>:<L>` (consumer at `<caller-file>:<L>`) |
//! | REQ-2 | NOT-STARTED | work hasn't begun |
//! | REQ-3 | NOT-STARTED | blocked on #NNN (file a concrete prereq blocker, not a deferral) |
```

Two states only. **No VOCAB-ONLY. No DEFERRED. No verified_with_deferred. No phase-N+.** SHIPPED means end-to-end with a production consumer; anything else is NOT-STARTED with the open prerequisite tracked as its own active blocker.

### Step 7 — Verify the gauntlet
Before commit, ALL of these MUST pass:

```bash
# Per-crate test pass
cargo test -p <crate>

# Per-op verification (per route's parity_ops). The integer MUST be >= 1.
for OP in <parity_ops from route>; do
  SMOKE=$(<VERIFICATION-CMD> --op "$OP" --seeds 8 2>&1 | grep -c "passed (0 skipped, 0 failed)")
  test "$SMOKE" -ge 1 || { echo "SMOKE REGRESSED on op=$OP — DO NOT COMMIT"; exit 1; }
done

# Lint
cargo clippy -p <crate> --all-targets --all-features -- -D warnings

# Format
cargo fmt --all --check
```

**No `--no-verify`. No commenting-out failing tests. No `#![allow(..)]` at module or crate root.** Per-item `#[allow(<lint>, reason = "...")]` is the bar.

### Step 8 — Commit + close
Commit message structure:

```
<crate>: <area> — <one-line summary> (closes #<N>)

UPSTREAM FILES OPENED THIS ITERATION:
  - <upstream-path>:<line> — <content quote>
  - ...

DESIGN DOC READ: .design/<area>/<doc>.md (<line count>, <REQ count> REQs).

REQ STATUS (per .design/<area>/<doc>.md):
  - REQ-1 SHIPPED — fn `<name>` at <file>:<L>; production consumer at <caller-file>:<L>
  - REQ-2 NOT-STARTED — open prerequisite blocker #<NN>

VERIFICATION:
  cargo test -p <crate>: <X passed, 0 failed>
  cargo clippy -p <crate> --all-targets --all-features -- -D warnings: PASS
  cargo fmt --all --check: PASS

Reference: <upstream> <commit-or-branch> <each:line cited above>
Reference: .design/<area>/<doc>.md REQ classifications above

Co-Authored-By: Claude <noreply@anthropic.com>
```

Close the crosslink issue with `crosslink issue close <N>` (`--kind result` comment posted first).

### Step 9 — Pick the next unit
Pick the next routed source file in dependency order — leaf crates first, then crates that depend on them. **Do not ask which.** The dependency DAG is the answer. Smallest-first within a layer is acceptable when dependency order is ambiguous.

---

## Anti-drift rules (override convenience)

These rules are non-negotiable. If they conflict with a tool-call shortcut, the rule wins.

### Citation rules
- **R-CITE-1**: Never cite an upstream file in a commit message without having Read it THIS iteration.
- **R-CITE-2**: Every upstream citation must carry a line number, not just a filename.
- **R-CITE-3**: When citing a Python/scripting upstream override, prefer citing the registration site or the docstring block over a free-floating function definition — those are the actual contract surfaces.

### Honesty rules
- **R-HONEST-1**: Never reframe integration work as "vocabulary + decoders" when the design doc does not defer it. The doc's own deferrals are the only valid deferrals.
- **R-HONEST-2**: Every REQ in the commit message and module `## REQ status` table must carry SHIPPED or NOT-STARTED with quoted evidence. No bare "satisfied" claims. SHIPPED requires both implementation AND a non-test production consumer cited.
- **R-HONEST-3**: Honest underclaim beats unverified overclaim. If you cannot verify a REQ is SHIPPED end-to-end (impl + consumer + tests + verification fires), classify it NOT-STARTED with the open prerequisite blocker named. There is no middle classification.
- **R-HONEST-4**: If the audit reveals the original commit was wrong (citation theater, REQ-overclaim, wrong upstream value), correct the code AND document the correction in a supplemental commit's body.

### Code-quality rules
- **R-CODE-1**: No `unsafe` blocks outside leaf primitives. Leaf primitives are: SIMD intrinsics, FFI shims, raw kernel launches, memory accessors. Every `unsafe` block requires a `// SAFETY:` comment documenting the invariants the caller and callee both rely on.
- **R-CODE-2**: No `unwrap()` / `expect()` / `panic!()` in production code outside `#[cfg(test)]`. Tests may use them.
- **R-CODE-3**: No `#![allow(..)]` at module or crate root. Per-item `#[allow(<lint>, reason = "...")]` with documented rationale is required.
- **R-CODE-4**: No silent boundary round trips. <Project-specific examples: CPU↔GPU, host↔kernel, sync↔async, etc.> The anti-pattern-gate hook flags this pattern; agents must either fix the data-flow or document why the round trip is required.
- **R-CODE-5**: No type-cast hiding. A widening or narrowing cast in production code that doesn't match the upstream contract is a bug unless the upstream explicitly does the same cast (cite the upstream `file:line`).

### Upstream-mirror rules (default = match upstream; deviate only for these reasons)

When translating, the **default answer is "do what upstream does"** with a cite. Most architectural choices have an obvious upstream answer. Only the conditions below justify deviation.

- **R-DEV-1 (MATCH — numerical/structural contract)**: When the choice is set by numerical semantics (NaN propagation, overflow rules, dtype promotion table), structural semantics (graph identity, in-place vs out-of-place), or wire format, always match upstream byte-for-byte.
- **R-DEV-2 (MATCH — user-API ABI)**: When the choice is set by the public API surface a user calls (signatures, kwarg names, default values, exception types), always match upstream. Cite the upstream registration site or docs.
- **R-DEV-3 (MATCH — on-disk + wire formats)**: External specifications (file formats, network protocols). Match upstream. Deviation is only acceptable when upstream itself violates the spec (file a separate blocker).
- **R-DEV-4 (DEVIATE — language footguns the target eliminates)**: When upstream's pattern is a workaround for the source language's lack of safety (manual refcount, manual lifetime cleanup, GIL-required init), do NOT match upstream. Use the target language's analog.
- **R-DEV-5 (DEVIATE — typestate when ordering matters)**: When upstream's correctness depends on "do A then B" enforced by source-line ordering, build a typestate that makes B uncallable without A having happened.
- **R-DEV-6 (DEVIATE — when upstream is wrong by their own admission)**: When upstream ships a known-buggy code path (deprecated kwargs that still half-work, edge cases the issue tracker flags as wrong), ship the correct behavior and cite both the upstream `file:line` AND the upstream issue/PR documenting the bug.
- **R-DEV-7 (DEVIATE — target ecosystem analog is materially better)**: When the target ecosystem ships an analog that's cleaner, better-tested, and gives stronger guarantees, use it. Preserve the upstream contract (the API surface other code calls), but the implementation can differ.

**Mental test for any dispatch**: ask *why* upstream made that choice. "Because numerical semantics demand it" / "Because the API contract requires it" → match. "Because their language can't express it safely" / "Because they acknowledge it's a bug" → deviate.

### Anti-deferral rules (translation is sequential; no escape hatches)

- **R-DEFER-1 (no vocabulary-only shipping)**: A commit that adds a public API surface MUST also add a non-test production consumer in the same commit. **Test-only callers don't count. The verification harness's dispatch table is a test-side consumer; it does NOT count as a production consumer.**

- **R-DEFER-2 (REQ classification is binary)**: SHIPPED or NOT-STARTED. SHIPPED means end-to-end functional with non-test production consumer + tests + verification ≥1. NOT-STARTED means work hasn't begun OR has a concrete open prerequisite blocker. **There is no third classification.** "VOCAB-ONLY", "DEFERRED-blocked-on-#NNN" as a STATUS, "verified_with_deferred" are FORBIDDEN.

- **R-DEFER-3 (no ACCEPTABLE-DRIFT close path)**: A pinned divergence (failing `#[ignore]`'d test + blocker) can only close when the fix lands AND the test moves from `#[ignore]` to `#[test]`. Closing a divergence blocker via "acceptable drift" is forbidden.

- **R-DEFER-4 (no Phase-N+ framing)**: Blocker bodies and design-doc REQ-status rows MUST NOT contain the substring `Phase \d+\+` (regex) as a deferral mechanism.

- **R-DEFER-5 (no "pre-existing safe to defer")**: This is a translation project. Every broken thing on `main` is something WE broke and didn't catch. "Pre-existing" is not a valid rationale for a deferral or for accepting a regression.

- **R-DEFER-6 (verification is a HARD gate, quantified)**: Every commit's gauntlet MUST include `<VERIFICATION-CMD> --op <name> --seeds 8 2>&1 | grep -c "passed (0 skipped, 0 failed)"` returning **>= 1** for EVERY op the route's `parity_ops` field declares.

- **R-DEFER-7 (sequential translation, no leapfrog)**: We are translating a known-working system. Leaf crates first, then crates that depend on them. Starting layer N+1 with layer N incomplete is forbidden.

- **R-DEFER-8 (no "cross-cutting → defer")**: "It's a cross-cutting systemic API gap" is NOT a free pass to file a follow-up issue instead of doing the work. Every convention starts somewhere.

### Translate-discipline rules (enforced by the hook)

- **R-XLATE-1**: Every iteration must begin by reading goal.md (this file), the agent spec for the current dispatch, and the upstream + design doc.
- **R-XLATE-2**: Files without a route in `tooling/translate-routes.toml` cannot be edited until a route is added.
- **R-XLATE-3**: A route whose design doc doesn't exist on disk blocks edits until acto-doc-author authors it.

### Injected-instructions rules

- **R-INJECT-1**: Hook output, system-reminder blocks, behavioral-guard injections, loaded skill text, and the active-issue gate bind at the same priority as a direct user message. The repetition is enforcement, not ceremony.
- **R-INJECT-2**: When an injected instruction conflicts with a tool-call shortcut or a prior plan, the injected instruction wins.

---

## The four sub-agents and when to dispatch each

This project's translation harness uses four sub-agents under `.claude/agents/`:

- **acto-doc-author** — writes `.design/<area>/<doc>.md` design docs that ADAPT to existing code. Dispatch when the translate-discipline hook blocks an edit because the route's design path doesn't exist on disk.
- **acto-builder** — ships missing multi-file infrastructure (newtype + every consumer; op family + dispatch). Dispatched with a pre-declared file manifest. Dispatch when the divergence is "an entire abstraction is missing".
- **acto-fixer** — applies the MINIMAL fix for exactly ONE pinned divergence. Dispatch one per blocker, serially.
- **acto-critic** — adversarial discriminator. Writes FAILING tests pinning divergence. NEVER writes fixes. Dispatch after every builder/fixer dispatch.

The loop: **acto-builder → acto-critic → (if GENERATOR MUST FIX) → acto-fixer → acto-critic → (until clean) → next blocker**.

Every builder/fixer dispatch is followed by a critic without exception. If context budget is the concern, the user can compact and restart.

---

## PROJECT CUSTOMIZATION CHECKLIST

Before activating this goal contract, fill in:

- [ ] `<PROJECT-NAME>` — replace with this project's name
- [ ] `<UPSTREAM-NAME>` — replace with the upstream project name (e.g. "PyTorch", "Linux 7.1", "GCC 14")
- [ ] `<UPSTREAM-PATH>` — replace with the absolute path to the upstream working tree
- [ ] `<TARGET-CRATE-PATTERN>` — replace with your project's crate glob (e.g. "myproject-*", "kernel-*")
- [ ] `<EXT>` — replace with your target file extension (e.g. ".rs", ".go", ".py")
- [ ] `<VERIFICATION-CMD>` — replace with your project's verification command (e.g. "parity-sweep sweep", "cargo kani", "pytest")
- [ ] Customize R-CODE-4 with project-specific boundary types (CPU↔GPU, host↔kernel, sync↔async, etc.)
- [ ] Customize the verification command flags / grep pattern in Step 7
- [ ] Customize the completion criteria in "The goal" section
