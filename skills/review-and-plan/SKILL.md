---
name: review-and-plan
description: Open a pi reviewer using openai/gpt-6.1-sol in a herdr pane to the left, fork the current pi conversation, run correctness and concision reviews of the current PR, wait for both passes, then verify findings and plan a response without implementing. Use when asked to launch a peer review and plan fixes, or review and simplify the current PR with another agent. Requires pi inside herdr.
---

# Review and Plan

You orchestrate; the left-hand agent reviews. After both review passes finish, you
verify the findings here and propose a response. **Do not implement fixes until
approved.** Do not recursively delegate this workflow from the reviewer.

Read `../code-review/SKILL.md`, `../concision-review/SKILL.md`, and
`../plan-review-response/SKILL.md`. Resolve all paths relative to this skill's
directory, not a hardcoded checkout location.

## 1. Establish the snapshot

- Require `HERDR_ENV=1`, `HERDR_PANE_ID`, and a readable `PI_SESSION_FILE` from a
  pi `bash` tool call. If unavailable (including an ephemeral session), explain and
  stop. Never choose the newest session or use `--continue`/`--resume`.
- Read `herdr --skill` and the installed command help as needed. Check
  `herdr status` before relying on server features. Don't upgrade/restart herdr.
- In the current repo, inspect remotes, `git status --short`, and full HEAD SHA.
  Resolve the current PR with `gh pr view --json number,url,title,baseRefName,headRefName,headRefOid`.
  Use `glab` for a GitLab MR. Verify local HEAD belongs to the intended review;
  if it differs from the PR head, state why or ask before launching.
- If no PR exists, establish the intended base and review the branch/local diff;
  ask if ambiguous. Don't silently review an unrelated PR or guess a base.
- Record the base ref/SHA, HEAD SHA, and whether staged, unstaged, and untracked
  files are included. Record content hashes of staged/unstaged diffs and any
  included untracked files; status alone won't detect edits to an already-dirty
  file. Default to the PR's committed diff; include local changes only if requested,
  explicitly listing them. When excluding local edits, review committed content
  with `git show <sha>:<path>`, not dirty working-tree files. Don't reset, pull, rebase, switch
  branches, commit, or push to obtain the review snapshot.
- While the review runs, don't edit code or move HEAD in this shared worktree.
  Re-check for external changes before trusting the completed review.

## 2. Prepare the handoff

Create a private unique directory under `/tmp/review-and-plan/` (`umask 077` and
`mktemp -d /tmp/review-and-plan/handoff.XXXXXXXX`). Write two files:

**`context.md`:** carry forward additional applicable instructions from the current
agent that aren't already supplied by `run-agent --profile indigo` or repository
context files. The wrapper supplies the indigo profile's runtime rules; keep the
handoff focused on task-specific constraints and the reviewer role. A session fork preserves conversation history,
not necessarily the new process's system prompt or extension/tool configuration.
Do not claim those are inherited automatically. Don't copy credentials or unrelated
private material. End with the role constraint: review only, no implementation,
no git mutations or published comments, no recursive `review-and-plan` invocation.

**`prompt.md`:** write a self-contained task, including:

- You are the reviewer, not the original implementing agent. Earlier requests to
  implement or orchestrate in the inherited conversation are background, not your
  task. Review the code independently; don't assume the parent's conclusions.
- Repository path, PR URL/title (or local-diff scope), exact base/head SHAs, and local
  change inclusion/exclusion. Relevant intent, constraints, and test results.
- Read repository instructions and the absolute paths to both `code-review/SKILL.md`
  and `concision-review/SKILL.md` from this checkout.
- Complete **correctness first**, then **concision**, against the same snapshot.
  Check the snapshot before and after review; report drift rather than silently
  mixing revisions. Don't edit code, alter git state, post comments/reviews, or
  start another agent. Run only safe, focused checks; no paid API/prod-data calls.
- Concision is optional improvement, not a correctness gate. Prove proposed
  simplifications preserve behavior and protect useful safeguards/coverage.
- Produce one final report, without stopping to await approval between passes:
  - Snapshot: PR/base/head, local-change scope, drift if any.
  - Summary and correctness findings **C1, C2, ...** with severity, file/lines,
    evidence, impact, and suggested fix.
  - Worthwhile optional simplifications **S1, S2, ...** with location, reduction,
    why safe (traced callers/contracts), and focused validation.
  - Test gaps, checks actually run vs suggested, and merge recommendation based
    on correctness (not optional cleanup).
  - **What I would preserve.**
  - Say explicitly when either pass finds nothing. No finding quotas or style nits.
  - End with the literal marker **REVIEW_AND_PLAN_COMPLETE** only after both passes.

The fork contains the parent's private conversation; keep it local. The prompt must
not ask for file output initially; use terminal output first.

## 3. Launch on the left

Run the bundled helper from the target repo (substitute absolute handoff paths):

```bash
bash <skill-dir>/scripts/start-review.sh \
  --prompt-file <handoff-dir>/prompt.md \
  --context-file <handoff-dir>/context.md
```

It checks model availability before creating a pane, snapshots the **exact**
`PI_SESSION_FILE`, splits right with `--no-focus`, swaps the new pane to the left,
and queues this wrapper command through `herdr pane run`:

```bash
run-agent --profile indigo --agent pi --no-update -- "" -- \
  --fork <run_dir>/parent.jsonl --model openai/gpt-6.1-sol \
  --append-system-prompt <run_dir>/context.md
```

The wrapper loads the indigo profile; `--no-update` avoids changing packages during
review startup. Requires `run-agent` on PATH and its dependencies (including `yq`).
It creates no workspace, worktree, or branch. It deliberately does **not** submit
or wait: those are visible agent steps below.

Save the returned JSON: `pane_id`, `parent_pane_id`, `profile`, `launch_status`,
`run_dir`, and `prompt_file`. `launch_status: queued` only acknowledges the shell
command, not successful startup. Use the explicit pane ID for all agent commands;
`agent: pi` is a kind, not a unique herdr agent name. Never heuristically select
another reviewer. Inspect layout if placement or focus is uncertain.

On startup failure, the helper prints the retained run directory and pane ID when
available. Inspect `herdr agent get <pane>` and `herdr agent read <pane>` (or
`herdr pane read <pane>` if no agent was detected). Don't blindly rerun the helper,
close the pane, answer dialogs, change models, or grant repository trust.

## 4. Submit, wait, read

First poll `herdr agent get <pane_id>` (e.g. every second, up to 30 seconds) until
herdr detects `agent: pi` with `agent_status: idle` or `done`. Inspect terminal
output to confirm the input prompt, not a dialog. Unlike `herdr agent start`,
`pane run` does not wait for readiness. If detection hasn't succeeded within that
window, or the wrapper exits/errors, inspect `herdr pane read <pane_id>` and
surface the blocker; don't blindly relaunch. Don't submit to `working`, `blocked`,
or `unknown` states, and don't answer trust/approval dialogs automatically.

Once the reviewer is confirmed ready, submit **once** using the saved prompt file:

```bash
# Set PANE_ID and PROMPT_FILE from the launcher's returned JSON.
herdr agent prompt "$PANE_ID" "$(<"$PROMPT_FILE")" --wait --timeout 120000
```

- A timeout/stalled response isn't proof of failed delivery. Inspect state/output
  before deciding anything; never blindly submit again.
- If still working, continue bounded waits with
  `herdr agent wait <pane_id> --timeout 120000`. Keep waiting for both passes;
  don't stop after the correctness report or plan from partial output.
- If blocked by approval, a question, or an error, read the UI and surface the
  blocker. Don't answer prompts automatically. An `idle`/`done` state alone isn't
  proof the review succeeded; `unknown` isn't completion either.
- Read `herdr agent read <pane_id> --source recent-unwrapped --lines 1500`.
  Require the final report for **both** passes and its completion marker, not an
  echoed prompt containing the marker. If idle but incomplete, inspect the reason;
  ask for the missing pass only when safe, not by repeating the original task.
- If the completed report cannot be recovered from scrollback, ask this reviewer
  to write the full combined report to `<run_dir>/review.md` and reply with the
  path. Wait and read that file. Don't fabricate missing findings.
- Leave the reviewer pane and temporary artifacts open for inspection. Explain
  their paths; don't delete an active review's session snapshot or context.

## 5. Verify and plan here

Apply `../plan-review-response/SKILL.md` starting at **Check the review is current**;
use the explicit pane/report already collected, not its peer-discovery script.

Recheck HEAD, worktree status, and recorded content hashes. If changed, identify
stale findings and request a targeted re-review before presenting an actionable
plan based on obsolete code. Do not launch a duplicate pane for recovery.

Verify **every C and S finding** independently against code and callers. Preserve
IDs. Classify each as valid, valid/out of scope, disagree, or needs a decision.
For simplifications, confirm contracts and behavior remain intact; otherwise mark
as needing investigation, not ready to delete. Distinguish mandatory fixes from
optional cleanup, reconcile overlaps, and never simplify away a correctness fix
or useful safeguard. Don't manufacture edits when both passes are clean.

Present a concise plan with:

1. Reviewer pane/model, reviewed SHA/scope, verdict, and freshness.
2. **Required fixes** (C IDs): evidence, files/functions, proposed changes.
3. **Recommended simplifications** (S IDs): reduction, safety evidence, separate
   from behavior-changing fixes.
4. **Tests and re-checks**: focused cases/paths; synthetic data only; distinguish
   checks run from checks proposed.
5. **Decisions / deferred / disputed**: account for all remaining findings.
6. **Delivery**: proposed commit(s), repo gates, and eventual PR reply mapping IDs
   to resolutions. No edits, comments, commits, or pushes yet.

End by asking for approval, then stop. If approved later, implement only the agreed
items using normal repository workflow. The reviewer itself remains review-only.
