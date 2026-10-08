---
name: re-review
description: Re-review a PR or local change after revisions. Compare against the previously reviewed commit, verify earlier findings, probe fixes for regressions, and report results in chat. Use when the user says "review the latest changes again", "re-review", "check the fixes", or "did this address your review?".
---

# Re-review

Read `../code-review/SKILL.md` for the general review criteria. This skill adds the
revision-specific workflow. Resolve that path relative to this skill directory.

## Scope and safety

- Review only: do not fix code, post comments/reviews, resolve threads, commit,
  push, or merge unless the user explicitly requests those actions.
- Read the target repository's instructions and relevant feature docs first.
- Preserve local changes. Fetch remote refs, but do not pull, reset, rebase, or
  switch a dirty checkout to obtain review code. Use a separate worktree when needed.
- Keep reproductions synthetic and local; no production access or external writes.
  Put scratch files in a review/session-specific temporary directory.

## 1. Establish the two review snapshots

Recover from conversation history or a supplied review:
- PR/repository (or local change scope).
- Exact previously reviewed commit SHA.
- Prior findings, their reproductions, and any stated acceptance criteria.

Fetch current PR metadata, its head and base, and checks using `gh` for GitHub
(`glab` for GitLab). Inspect remotes rather than assuming `origin` is the right
repository. Record the latest head SHA before reading the diff.

For GitHub, a typical discovery command is:

```bash
gh pr view "$PR" --repo "$REPO" \
  --json headRefOid,headRefName,baseRefName,title,body,files,statusCheckRollup
```

Fetch the PR head into an explicit local review ref, not a working branch:

```bash
git fetch "$REMOTE" "+refs/pull/$PR/head:refs/reviews/$PR/head"
git rev-parse "refs/reviews/$PR/head"
```

The `+` only refreshes this disposable local review ref after a PR force-push;
it must never be used here to rewrite a working branch or push history.
Fetch the base separately if needed. Do not rely on `FETCH_HEAD` after a
multi-ref fetch. Verify the fetched SHA equals the PR's advertised head.

If the previous SHA or review cannot be recovered, ask for it when necessary,
or explicitly perform a fresh review of the full current PR. Never invent a
baseline or label an unknown prior finding fixed. For local changes, distinguish
committed, staged, and unstaged changes and state which snapshot is reviewed.

## 2. Review the delta, then trace its consequences

For known commit snapshots:

```bash
git diff --stat "$PREVIOUS_SHA" "$LATEST_SHA"
git diff "$PREVIOUS_SHA" "$LATEST_SHA" -- <relevant-paths>
```

Use a two-snapshot diff for the revision delta, including after rewritten
history. Also inspect the full current PR diff against its base to catch newly
added scope and understand changes obscured by rebases or upstream merges.

For each prior finding, classify it as:
- **Fixed:** the original failure is no longer reachable, supported by code or tests.
- **Partially fixed:** the direct case works but a relevant variant still fails.
- **Unresolved:** the original failure remains.
- **Not verified:** evidence, dependencies, or the baseline are unavailable.

Do not infer correctness from a commit message, PR description, or new test name.
Read the changed implementation, callers, persisted state, and downstream consumers.
A backend fix may require checking how the UI selects or filters its output.
Review additional changes outside the prior findings too.

## 3. Challenge the fix, not just the original example

Choose probes that follow from the actual contract; this is not a mandate to
invent more findings. Particularly for stateful or deduplicated flows, examine:

- Same input twice; genuinely changed input; formatting-equivalent input.
- Existing pending, resolved, rejected, or superseded state. These statuses need
  not mean the same thing: automatic supersession is not a human rejection.
- A → B → A across successive runs, and multiple historical records for one key.
- Partial success: write one succeeds, write two fails, then the operation retries.
- Early returns that bypass cleanup or reconciliation on retries.
- Ordering, pagination, stale reads, and concurrent human changes where relevant.
- Consumer behavior when two rows remain active or no active row remains.
- Failure isolation: preserving the primary operation without silently abandoning
  an invariant the consumer relies on.

Separate intended limitations and pre-existing issues from regressions or incomplete
fixes in this PR. A finding needs a reachable scenario, observable impact, and a
specific location in the current code. Withdraw earlier findings if new evidence
shows they were wrong; do not defend them for consistency.

## 4. Validate with bounded, reproducible checks

- Ensure the source being tested is the latest reviewed snapshot, not an unrelated
  checkout or dirty local version. Inspect files before choosing test commands.
- Run focused tests covering the changed code and neighboring guards/consumers.
- Re-run the original reproduction where feasible, then probe uncovered cases
  with synthetic fixtures or small scratch scripts. Do not alter tracked tests
  unless asked to implement a fix.
- Check that mocks reflect real types/contracts. A mock-only pass proves only the
  modeled behavior; distinguish it from integration or browser verification.
- Record exact commands/results, including blockers and checks not performed.
- Check CI for the reviewed SHA, not a previous commit. Green CI supports, but does
  not replace, behavioral review.
- Recheck the remote head before reporting. If it moved, review the additional
  delta or explicitly qualify the report as applying only to the recorded SHA.

## 5. Report in chat

Keep the report concise. Omit empty sections; do not repeat the entire first review.

```text
## Re-review: <PR>
Reviewed <previous SHA> → <latest SHA>.

Previous findings: <fixed / partially fixed / unresolved / not verified>.

### Remaining or new findings
[P2 / medium] <specific title> — <path:lines or SHA-pinned link>
<Trigger, observed failure, user impact, and concrete fix direction.>
<Evidence: reproduced locally, verified by code trace, or explicitly uncertain.>

### Validation
- <Focused test results and CI status for this SHA.>
- <Missing regression cases; integration/browser/full-suite limitations.>

Recommendation: approve / approve-with-follow-ups / request-changes.
<Risk or residual limitation, if relevant.>
```

Use P1/high for serious correctness, security, or data-loss risks; P2/medium for
concrete functional bugs; P3/low for non-blocking improvements. Follow repository
severity conventions if different. Consolidate manifestations of the same root
cause rather than inflating the finding count. Documentation drift belongs in
non-blocking follow-ups unless it materially breaks operation.

If nothing actionable remains, say **no new findings** and recommend approval
with the validation limits stated. Do not manufacture objections to keep a review
loop going. A recommendation is not authorization to submit approval or merge.
