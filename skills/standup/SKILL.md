---
name: standup
description: Draft a paste-ready daily standup (previous workday / today / blockers) from GitHub, git commits, Linear, and Slack activity. Use when the user asks for their standup, "what did I do yesterday", or a daily update. Accepts an optional since-date (YYYY-MM-DD).
---

# Standup

Draft the user's standup. Follow the steps in order. Do not skip step 1.

## 1. Establish dates (never assume)
Run this first and use its output as the only source of truth for dates. Set `SINCE` to the date the user gave (YYYY-MM-DD), or leave it empty. The snippet works with both BSD (macOS) and GNU `date`; the shell may have either.

```bash
SINCE=""   # optional override, e.g. 2026-09-25
if date -v-1d +%F >/dev/null 2>&1; then   # BSD date
  ago()  { date -v-"$1"d +%F; }
  dname() { date -j -f %F "$1" +%A; }
else                                      # GNU date
  ago()  { date -d "$1 days ago" +%F; }
  dname() { date -d "$1" +%A; }
fi
today=$(date +%F); dow=$(date +%u)   # 1=Mon … 7=Sun
case $dow in 1) back=3;; 7) back=2;; *) back=1;; esac
prev="${SINCE:-$(ago "$back")}"
echo "today=$today ($(date +%A)) prev=$prev ($(dname "$prev"))"
```

- `prev` is the previous **workday** (Monday → Friday), unless the user passed a date.
- Label the section with the real day name: "Friday (Sep 25)", not "Yesterday", unless `prev` is literally yesterday.
- The reporting window is `prev 00:00` up to now.

## 2. Gather activity in the window only
Identities: GitHub `johnmarkli` (commits as `jli@getindigo.io` in IndigoIO repos, `johnmarkli@gmail.com` elsewhere); Linear user id `71d446ee-9cc4-4867-b797-4fc87a9ddb43`; Slack via `slackcli` (not `slack-cli`).

- **GitHub:**
  - `gh search prs --author=@me --updated=">=$prev"`
  - `gh search prs --author=@me --merged-at=">=$prev"`
  - `gh search prs --reviewed-by=@me --updated=">=$prev"`
- **Commits:** `git log --all --since="$prev 00:00" --author=jli@getindigo.io --author=johnmarkli@gmail.com` in `~/indigo/project-indigo` and any other active repos (e.g. `~/dev/ai-kit`). Run `git fetch` first so remote branches are current.
- **Linear:** issues assigned to the user where `updatedAt`, `startedAt`, or `completedAt` ≥ `$prev` (`linear_list_issues`). Also list all open In Progress/Todo issues for the "Today" section.
- **Slack:** `slackcli search messages "from:me on:$prev"` (and `after:$prev` for later days). Best-effort context only.

## 3. Rules for the "previous workday" section
- Include an item only if it has a timestamp inside the window (commit date, PR created/merged/reviewed, Linear state change). Cite the date for anything non-obvious.
- Leave out older work, even if it's still open. Open work goes under "Today".
- If nothing falls in the window, say "No tracked activity since <day>". Do not pad it with older work.
- Describe work by ticket ID and short title. Never include patient names or other PHI/PII, even if a Linear ticket or Slack message contains them (e.g. Zendesk feedback tickets).

## 4. Output (short, paste-ready)
**<Day name> (<date>)**: bullets
**Today**: bullets, drawn from open assigned Linear issues and the user's open PRs
**Blockers**: bullets or "None"

After the standup, add one line listing the date window used and anything the user should double-check.
