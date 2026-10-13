---
name: concision-review
description: Review a PR or local diff for behavior-preserving simplifications. Use when the user says "make this PR more concise", "simplify this diff", "reduce unnecessary changes", or asks for a concision pass. Review only unless implementation is explicitly requested; use code-review for correctness and regression hunting.
---

# Concision Review

Find changes that make the diff easier to understand and maintain, not merely shorter.
This is an optional simplification pass, not a correctness gate.

## Scope and safety

- Read repository instructions and relevant feature documentation first.
- Identify the PR/base/head or local diff. Inspect remotes before fetching;
  use `gh` for GitHub and `glab` for GitLab.
- Record the reviewed SHA. Distinguish committed, staged, and unstaged changes;
  say explicitly whether local revisions are included.
- Preserve local work. Do not pull, reset, rebase, or switch a dirty checkout
  to obtain review code; use a separate worktree if needed.
- Review only: do not edit files, post comments/reviews, commit, push, or merge
  unless requested. A suggestion is not permission to implement it.

## Review workflow

### 1. Understand what must remain

Read the full scoped diff and its closest existing implementation. Identify the
behavior, contracts, operational safeguards, and repository conventions the change
must preserve. Separate generated output from hand-written code.

### 2. Look for meaningful reductions

Prioritize these opportunities:

- **Repeated explanations:** module docs duplicating a maintained architecture or
  judge document; comments narrating obvious code. Keep a short overview and link
  to the authoritative detail.
- **Redundant state or plumbing:** storing a value already returned by a collaborator,
  forwarding dependencies through unnecessary wrappers, repeated conversions.
- **Speculative generality:** generic dispatch, attribute forwarding, configuration
  tables, or extension points with no current need. Prefer the existing explicit path.
- **Removable machinery:** helpers or tests that exist solely to support an
  unnecessary abstraction. Remove its scaffolding only if the abstraction can go.
- **Scope expansion:** unrelated cleanup that increases review burden without
  helping the requested behavior. Recommend deferring it rather than redesigning it.

### 3. Prove each suggestion is safe

Trace callers, return values, consumers, and tests before recommending removal.
For each candidate, establish:

1. The responsibility it currently serves.
2. The smaller implementation and where that responsibility remains.
3. Why behavior and relevant contracts stay unchanged.
4. The focused validation needed if implemented.

Absence of an obvious caller is not proof of dead code: check registration,
reflection, external contracts, and generated call sites where applicable. Mark
uncertain candidates as requiring investigation, not ready-to-delete findings.

### 4. Protect useful complexity

- Preserve error handling, security checks, observability, and regression coverage.
- Keep comments explaining non-obvious invariants, tradeoffs, or failure modes.
- Keep required architecture docs, case records, changelogs, and other repo-mandated
  artifacts; reduce duplication within them rather than deleting obligations.
- Do not hand-edit generated files or remove them just to reduce the diff size.
- Respect established repository patterns. Boilerplate alone does not justify a
  cross-cutting refactor.
- Do not replace readable statements with dense expressions or add a shared
  framework solely to save lines. Fewer responsibilities matter more than fewer lines.
- Keep behavior changes separate. If a correctness bug emerges, identify it as such;
  use `../code-review/SKILL.md` for that review rather than disguising a fix as cleanup.

## Report

State the snapshot and whether local revisions were included. List only worthwhile
suggestions, ordered by impact and confidence:

- **Location:** file and function or line range.
- **Reduction:** what to remove, shorten, or simplify.
- **Why safe:** the traced evidence that behavior remains intact.
- **Validation:** focused checks needed after implementation; distinguish them from
  checks actually run.

End with **What I would preserve**, naming the useful complexity that should stay.
Keep the report short; do not pad it with style nits, invented line-saving estimates,
or suggestions made only to meet a quota. If the diff is already concise, say so.

## If implementation is requested

Apply only the agreed simplifications, following the repository's branch and testing
rules. Preserve unrelated local changes, run focused checks, and inspect the final
diff for accidental behavior changes. Commit, push, or publish only when authorized.
