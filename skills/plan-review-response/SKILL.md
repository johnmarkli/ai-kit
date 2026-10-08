---
name: plan-review-response
description: Read the code review that another agent in the same herdr workspace wrote for the current PR, verify each finding against the code, and present a plan for addressing it — without editing anything. Use when the user says "look at the code review in the other agent", "plan how to address the review", "respond to the review from the other pane", or "what did the reviewer find and how do we fix it". Requires running inside herdr (HERDR_ENV=1).
---

# Plan Review Response

The usual setup: you built a PR in one pane, and a second agent in the same herdr
workspace reviewed it. This skill pulls that review into your context, checks every
finding against the code, and turns it into a plan for the user to approve.

**Plan only.** Don't edit files, commit, push, or post to GitHub until the user
approves the plan.

## 0. Preconditions
- `test "${HERDR_ENV:-}" = 1`. If you aren't in herdr, say so and stop.
- Know which PR you're on: run `gh pr view --json number,url,headRefOid,title` in the
  repo. If there isn't one, use the current branch against its base.

## 1. Find and read the review
```bash
~/dev/ai-kit/skills/plan-review-response/scripts/read-peer-review.sh
```
- This reads every *other* agent pane in `$HERDR_WORKSPACE_ID` and writes each pane's
  recent output to `/tmp/plan-review-response/<ws>/<pane>.txt`.
- It prints JSON per pane: `agent_status`, `cwd`, `file`, and `looks_like_review`.
- Pick the pane that has `looks_like_review: true` and the same `cwd` / worktree as
  you.
  - **Several candidates:** ask the user which pane holds the review.
  - **None:** tell the user and stop.
- The user named a pane? Pass `--pane <id>`.
- Review cut off at the top? Re-run with `--lines 1500`.
- The reviewer is still running (`agent_status: working`)? Say so, and ask whether to
  wait or plan from the partial review.

Read the file. The review is usually the **last** block of prose: a summary, findings
with severities and file:line references, and a recommendation. Everything above it is
the reviewer's tool calls. Use those only to see how it confirmed each finding.

## 2. Check the review is current
- Compare the commit the review names (e.g. "Reviewed commit 422927ee") with
  `git rev-parse --short HEAD`.
- If HEAD has moved, run `git log <reviewed>..HEAD --oneline` and note which findings
  later commits may already address.
- Run `git status --short`, so the plan doesn't trample uncommitted work.

## 3. Verify every finding yourself
For each finding:
- Open the cited lines and read the surrounding code. Don't trust a summary.
- **Confirm or refute it:**
  - Did the reviewer reproduce it? Quote how.
  - If it didn't, decide whether you can reproduce it cheaply: a synthetic input or a
    unit-level call, with no prod data and no paid API calls. If so, do it now. Running
    a reproduction is not editing.
- **Classify it:**
  - **valid**: fix it;
  - **valid, out of scope**: propose a follow-up ticket;
  - **disagree**: give a short reason to put in the PR reply;
  - **needs a decision**: product or owner call, not code.
- Note the blast radius: does the fix change behaviour, generated files, fixtures, or
  eval results already quoted in the PR? If so, say what must be re-run.

Questions to the author, and non-code asks (e.g. "get product sign-off"), are findings
too. Put them under **Decisions needed**.

## 4. Present the plan
Keep it short. Use this shape:

```markdown
The review by <pane> (<agent>, reviewing <sha>) <one-line verdict as stated>. <Is the review still current?>

## 1. <Severity> — <finding title>  (<file>:<lines>)
<one or two sentences: the problem, and whether you confirmed it and how>
**Fix:** <concrete change: function, rule, error path>

## 2. ...

## Tests
<new or updated tests, their location (inside the repo's collected test paths), the cases covered, and that they use synthetic inputs only>

## Re-checks
<anything already in the PR that must be re-validated: dry-runs, evals, generated code>

## Decisions needed
<items that need the user's or an owner's call, each with your recommendation>

## Not addressing
<findings you disagree with or would defer, with a reason>   ← omit if empty

## Delivery
<commit message (repo convention), gate command (e.g. ./prefly.sh), push, and a PR reply mapping each finding to its fix. Never amend or force-push an open PR.>

Shall I go ahead?
```

Then stop and wait. Once the user approves, implement the plan with the repo's normal
PR workflow. Keep the finding numbers in the commit body and the PR reply, so the
reviewer can match each fix to its finding.

## Rules
- Never answer prompts in the reviewer's pane, and never send it keys or text. This
  skill only reads it.
- Don't copy PHI or secrets from the review output into the plan, commits, or PR text.
- Don't inflate severities, and don't drop a finding silently: every finding ends up
  in a fix, a decision, or "not addressing" with a reason.
