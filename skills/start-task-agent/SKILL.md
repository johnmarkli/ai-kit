---
name: start-task-agent
description: Hand a task off to a fresh agent in its own git worktree + herdr workspace, launched via `run-agent --profile <p>` and seeded with a written context/plan prompt. Use when the user says "spin up an agent for this", "start an agent on GET-1234", "new worktree and workspace for this ticket", "hand this off to another agent", or asks to kick off a ticket in parallel. Requires running inside herdr (HERDR_ENV=1).
---

# Start Task Agent

This skill turns a task into an isolated, running agent session:

- a new branch and git worktree based on the latest remote default branch
- a herdr workspace for that worktree
- `run-agent --profile <p>` launched in the workspace's pane with a prompt file you write

The mechanical part is `scripts/start-task-agent.sh`, next to this file. Your job is the **prompt**: the new agent starts cold, so good context decides the outcome.

## 0. Preconditions
- `test "${HERDR_ENV:-}" = 1`. If you aren't in herdr, say so and stop.
- The user explicitly asked for a separate worktree, workspace, or agent. Don't use this skill for ordinary in-place work.

## 1. Pin down the task
- **Repo:** usually the cwd. Resolve it with `git rev-parse --show-toplevel`.
- **Profile:** use the user's choice, or pick from `run-agent --list-profiles` by matching the repo (e.g. `~/indigo/*` → `indigo`). If it's unclear, ask.
- **Source material:** fetch the ticket in full (Linear `linear_get_issue`, `gh issue view`, Slack thread, etc.). Include the comments, not just the title.
- **Branch name:** follow the repo convention. For a Linear ticket, use its `branchName`, or a shorter `<user>/<ticket-lower>-<slug>`. Check that it doesn't already exist.

## 2. Write the prompt file
Write it to `/tmp/<branch-with-slashes-as-dashes>/prompt.md`. Use this template and keep it tight:

```markdown
<TICKET-ID>: <title>
Branch `<branch>` is already checked out in this worktree, based on latest <remote>/<base>.
<Any repo/remote quirk you discovered, e.g. "origin = upstream; there is no fork remote">

Start by pulling the full ticket (<how: linear tools / gh issue view ...>). Summary:

## Problem
<what's wrong, with evidence and impact>

## Cause / pointers
<files, functions, hypotheses: anything you already know that saves the agent exploration>

## Proposed approach
<preferred fix, alternatives, explicit out-of-scope items>

## Plan
1. Read <files> and confirm the root cause.
2. Share a short plan with me before editing.   ← keep this checkpoint unless the user says go straight through
3. Implement (<repo conventions/skills to follow>).
4. Validate (<exact test/lint commands>).
5. Open a PR (<skill/title convention>). Don't merge.
```

Don't put secrets or PHI in the file. Refer to IDs, not patient data.

## 3. Launch
```bash
~/dev/ai-kit/skills/start-task-agent/scripts/start-task-agent.sh \
  --repo "$REPO" --branch "$BRANCH" --label "<short-label e.g. get-4050>" \
  --profile "$PROFILE" --prompt-file "$PROMPT_FILE"
```
Options:
- `--agent pi|claude|omp` (default `pi`)
- `--remote` (default: `fork` if that remote exists, else `origin`)
- `--base <ref>` (default: `<remote>/<default-branch>`)
- `--focus` (switch to the new workspace)
- `--dry-run` (print what would run)

The script prints JSON with `workspace_id`, `pane_id`, `worktree`, `branch`, and `base_sha`.

## 4. Check startup
```bash
sleep 10; herdr pane read <pane_id> | tail -c 1500
```
- **Trust prompt** (pi's "Trust project folder?" on a new worktree path): **don't answer it yourself.** Tell the user the options and let them choose:
  - Trust this folder
  - Trust parent `~/.herdr/worktrees/<repo>`, which covers future worktrees
  - Trust for this session only

  If they pick one, send it with `herdr pane send-keys <pane_id> ...`, using arrow keys + Enter.
- **Agent working** (status line visible, tool calls running): done.
- **Error / shell prompt back:** read the output, fix it, and relaunch with `herdr pane run <pane_id> '<cmd>'`.

## 5. Report
Briefly give the user:
- the workspace ID and label, the pane, the worktree path, and the branch @ base SHA
- a one-line summary of what the agent was told, including the checkpoint where it stops for approval

## Cleanup (when the user asks)
`herdr workspace close <ws>`, then `git -C <repo> worktree remove <path>` and, if the work isn't merged, keep the branch unless the user says to delete it.
