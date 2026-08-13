#!/usr/bin/env python3
"""mr-review — automate GitLab MR review triage using herdr worktrees + the pi agent.

Workflow:
  * discover your review-requested MRs (drops drafts + ones you already approved)
  * rank them by cost-to-review (size + risk heuristic) into buckets
  * spin up an isolated herdr workspace + git worktree + pi agent per MR
  * check status / read results / tear everything down cleanly

Subcommands:
  list                       ranked table of pending reviews
  start <selector...>        fan out reviews (buckets: high|substantial|low|trivial|all, or repo!iid)
  status                     show agent status for active reviews
  read <repo!iid>            dump the agent output for a review
  close <selector...|--all|--idle>   tear down workspace + worktree + branch

Relies on: glab, herdr, git, and ~/dev/ai-kit/scripts/run-agent.sh
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
PH_ROOT = Path(os.environ.get("MR_REVIEW_PH_ROOT", Path.home() / "ph"))
RUN_AGENT = Path(os.environ.get(
    "MR_REVIEW_RUN_AGENT",
    Path.home() / "dev/ai-kit/scripts/run-agent.sh",
))
PROFILE = os.environ.get("MR_REVIEW_PROFILE", "ph-all")
CACHE_DIR = Path(os.environ.get("MR_REVIEW_CACHE", Path.home() / ".cache/mr-review"))
STATE_FILE = CACHE_DIR / "state.json"
CTX_FILE = CACHE_DIR / "context.md"
RANK_CACHE = CACHE_DIR / "ranked.json"
DEFAULT_MAX = int(os.environ.get("MR_REVIEW_MAX", "4"))

BUCKETS = ["high", "substantial", "low", "trivial"]
BUCKET_EMOJI = {"high": "🔴", "substantial": "🟠", "low": "🟡", "trivial": "🟢"}

# risk keywords bump a MR up a bucket
RISK_KEYWORDS = (
    "auth", "security", "secret", "token", "migrat", "outbox", "dicom",
    "schema", "migration", "encrypt", "permission", "audit", "payment",
)


# ---------------------------------------------------------------------------
# Shell helpers
# ---------------------------------------------------------------------------
def run(cmd: list[str], check: bool = True, quiet: bool = False) -> str:
    """Run a command, return stdout. Raises on failure unless check=False."""
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 and check:
        if not quiet:
            sys.stderr.write(f"$ {' '.join(cmd)}\n{res.stderr}\n")
        raise SystemExit(f"command failed: {' '.join(cmd)}")
    return res.stdout


def run_json(cmd: list[str], check: bool = True):
    out = run(cmd, check=check)
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        if check:
            raise SystemExit(f"expected JSON from: {' '.join(cmd)}\n{out[:400]}")
        return None


def glab_api(path: str, check: bool = True):
    return run_json(["glab", "api", path], check=check)


# ---------------------------------------------------------------------------
# State (mr key -> {workspace_id, tab_id, path, branch, agent, repo, iid, url})
# ---------------------------------------------------------------------------
def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def save_state(state: dict) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


# ---------------------------------------------------------------------------
# Discovery + ranking
# ---------------------------------------------------------------------------
def my_id() -> int:
    return glab_api("user")["id"]


def repo_dir(repo: str) -> Path:
    return PH_ROOT / repo


def default_branch(repo: str) -> str:
    d = repo_dir(repo)
    out = run(["git", "-C", str(d), "symbolic-ref", "refs/remotes/origin/HEAD"],
              check=False).strip()
    if out.startswith("refs/remotes/origin/"):
        return out.split("/")[-1]
    return "main"


def encoded(project_path: str) -> str:
    return urllib.parse.quote(project_path, safe="")


def fetch_pending(uid: int) -> list[dict]:
    """Open, review-requested MRs, excluding drafts and ones I've approved."""
    mrs = glab_api(
        f"merge_requests?reviewer_id={uid}&state=opened&scope=all&per_page=100"
    )
    pending = []
    for m in mrs:
        if m.get("draft"):
            continue
        project_path = m["references"]["full"].split("!")[0]
        iid = m["iid"]
        approvals = glab_api(
            f"projects/{encoded(project_path)}/merge_requests/{iid}/approvals",
            check=False,
        )
        approved_by = approvals.get("approved_by", []) if approvals else []
        if any(a["user"]["id"] == uid for a in approved_by):
            continue
        pending.append({
            "project_path": project_path,
            "repo": project_path.split("/")[-1],
            "iid": iid,
            "title": m["title"],
            "url": m["web_url"],
        })
    return pending


def diff_stats(mr: dict) -> dict:
    d = glab_api(
        f"projects/{encoded(mr['project_path'])}/merge_requests/{mr['iid']}/changes",
        check=False,
    ) or {}
    changes = d.get("changes", [])
    add = dele = new = deleted = 0
    for c in changes:
        for line in c.get("diff", "").splitlines():
            if line.startswith("+") and not line.startswith("+++"):
                add += 1
            elif line.startswith("-") and not line.startswith("---"):
                dele += 1
        if c.get("new_file"):
            new += 1
        if c.get("deleted_file"):
            deleted += 1
    return {"files": len(changes), "add": add, "del": dele,
            "new": new, "deleted": deleted}


def bucket_for(mr: dict, stats: dict) -> str:
    churn = stats["add"] + stats["del"]
    files = stats["files"]
    # base bucket by size
    if files >= 60 or churn >= 2000:
        base = "high"
    elif files >= 15 or churn >= 400:
        base = "substantial"
    elif files >= 5 or churn >= 60:
        base = "low"
    else:
        base = "trivial"
    # risk bump: move up one bucket (but never below substantial cap for size)
    text = (mr["title"] + " " + mr["project_path"]).lower()
    if any(k in text for k in RISK_KEYWORDS):
        idx = BUCKETS.index(base)
        base = BUCKETS[max(0, idx - 1)]
    return base


def rank(pending: list[dict]) -> list[dict]:
    ranked = []
    for mr in pending:
        stats = diff_stats(mr)
        mr = {**mr, "stats": stats, "bucket": bucket_for(mr, stats)}
        ranked.append(mr)
    ranked.sort(key=lambda m: (BUCKETS.index(m["bucket"]),
                               -(m["stats"]["add"] + m["stats"]["del"])))
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    RANK_CACHE.write_text(json.dumps(ranked, indent=2))
    return ranked


def load_ranked(refresh: bool = False) -> list[dict]:
    if not refresh and RANK_CACHE.exists():
        return json.loads(RANK_CACHE.read_text())
    return rank(fetch_pending(my_id()))


def key(mr: dict) -> str:
    return f"{mr['repo']}!{mr['iid']}"


def mr_from_url(url: str) -> dict:
    """Parse a GitLab MR URL into an mr dict (repo, iid, url, project_path)."""
    url = url.strip().rstrip("/")
    if "/-/merge_requests/" not in url:
        raise SystemExit(f"not an MR url: {url}")
    left, iid = url.split("/-/merge_requests/", 1)
    iid = int(iid.split("/")[0].split("?")[0])
    project_path = left.split("gitlab.com/", 1)[-1]
    repo = project_path.split("/")[-1]
    return {"project_path": project_path, "repo": repo, "iid": iid, "url": url}


def resolve_key(state: dict, selector: str) -> str | None:
    """Accept a repo!iid key or a full MR url, return the state key."""
    if selector in state:
        return selector
    if "/-/merge_requests/" in selector:
        k = key(mr_from_url(selector))
        return k if k in state else None
    return None


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
def select(ranked: list[dict], selectors: list[str]) -> list[dict]:
    if not selectors or selectors == ["all"]:
        return ranked
    chosen, want_buckets, want_keys = [], set(), set()
    for s in selectors:
        (want_buckets if s in BUCKETS else want_keys).add(s)
    for mr in ranked:
        if mr["bucket"] in want_buckets or key(mr) in want_keys:
            chosen.append(mr)
    return chosen


# ---------------------------------------------------------------------------
# herdr orchestration
# ---------------------------------------------------------------------------
def emit_context() -> Path:
    """Compose the run-agent.sh profile context to a stable file for `pi
    --append-system-prompt <path>` (herdr 0.8.0 can only launch canonical agent
    executables, so we can't exec the wrapper directly)."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    run([str(RUN_AGENT), "--agent", "pi", "--profile", PROFILE,
         "--emit-context", str(CTX_FILE)])
    return CTX_FILE


def workspace_pane(workspace_id: str) -> str | None:
    data = run_json(["herdr", "pane", "list"], check=False) or {}
    for p in data.get("result", {}).get("panes", []):
        if p.get("workspace_id") == workspace_id:
            return p.get("pane_id")
    return None


def spin_up(mr: dict, state: dict) -> None:
    k = key(mr)
    if k in state:
        print(f"  skip {k}: already active (workspace {state[k]['workspace_id']})")
        return
    repo, iid, url = mr["repo"], mr["iid"], mr["url"]
    d = repo_dir(repo)
    if not d.exists():
        print(f"  skip {k}: no local clone at {d}")
        return
    branch = f"review/mr-{iid}"
    existing = run(["git", "-C", str(d), "worktree", "list"], check=False)
    wt_path = Path.home() / ".herdr/worktrees" / repo / f"review-mr-{iid}"
    if branch in existing or wt_path.exists():
        print(f"  skip {k}: worktree/branch already exists at {wt_path} "
              f"(untracked — `git -C {d} worktree remove {wt_path} --force`)")
        return
    ctx = emit_context()
    base = default_branch(repo)
    run(["git", "-C", str(d), "fetch", "origin", base, "--quiet"], check=False)
    wt = run_json([
        "herdr", "worktree", "create",
        "--cwd", str(d),
        "--branch", branch,
        "--base", f"origin/{base}",
        "--label", f"review-{repo}-{iid}",
        "--no-focus", "--json",
    ])["result"]
    ws = wt["workspace"]
    tab_id = ws["active_tab_id"]
    path = wt["worktree"]["path"]
    entry = {
        "repo": repo, "iid": iid, "url": url,
        "workspace_id": ws["workspace_id"], "tab_id": tab_id,
        "path": path, "branch": branch,
    }

    # freshly created panes need a moment to reach an interactive shell prompt,
    # otherwise `herdr agent start` fails readiness detection
    pane = None
    for _ in range(10):
        pane = workspace_pane(ws["workspace_id"])
        if pane:
            break
        time.sleep(1)
    if not pane:
        print(f"  ERROR no pane found for {k} workspace {ws['workspace_id']}")
        tear_down(k, entry, state)
        return

    agent = f"pi-{repo}-{iid}"
    prompt = f"Code review {url} and show me the results here"
    res = None
    for attempt in range(3):
        time.sleep(2 if attempt == 0 else 5)
        res = run_json([
            "herdr", "agent", "start", agent,
            "--kind", "pi",
            "--pane", pane,
            "--timeout", "120000",
            "--",
            "--append-system-prompt", str(ctx),
            prompt,
        ], check=False)
        if res and "result" in res:
            break
        print(f"  retry {k}: agent start attempt {attempt + 1} failed ({res})")
    if not res or "result" not in res:
        print(f"  ERROR starting agent for {k}: {res}")
        tear_down(k, entry, state)
        return

    state[k] = {**entry, "pane_id": pane, "agent": agent}
    save_state(state)
    print(f"  ✅ {k}: workspace {ws['workspace_id']} pane {pane} agent {agent}")


def tear_down(k: str, entry: dict, state: dict) -> None:
    repo = entry["repo"]
    d = repo_dir(repo)
    run(["herdr", "workspace", "close", entry["workspace_id"]], check=False)
    run(["git", "-C", str(d), "worktree", "remove", entry["path"], "--force"],
        check=False)
    run(["git", "-C", str(d), "branch", "-D", entry["branch"]], check=False)
    state.pop(k, None)
    save_state(state)
    print(f"  🧹 closed {k}")


def agent_statuses() -> dict:
    """pane_id -> agent_status (herdr 0.8.0 agent list has no name field)."""
    data = run_json(["herdr", "agent", "list"], check=False) or {}
    out = {}
    for a in data.get("result", {}).get("agents", []):
        out[a.get("pane_id", "")] = a.get("agent_status", "unknown")
    return out


def target(entry: dict) -> str:
    return entry.get("pane_id") or entry.get("agent", "")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
def cmd_list(args):
    ranked = load_ranked(refresh=args.refresh)
    state = load_state()
    cur = None
    for mr in ranked:
        if mr["bucket"] != cur:
            cur = mr["bucket"]
            print(f"\n{BUCKET_EMOJI[cur]} {cur.upper()}")
        s = mr["stats"]
        active = " [active]" if key(mr) in state else ""
        print(f"  {key(mr):32} {s['files']:>3}f +{s['add']}/-{s['del']}"
              f"  {mr['title'][:60]}{active}")
    print()


def cmd_start(args):
    ranked = load_ranked(refresh=args.refresh)
    chosen = select(ranked, args.selectors)
    if not chosen:
        print("nothing selected")
        return
    print("Will start reviews for:")
    for mr in chosen:
        print(f"  {BUCKET_EMOJI[mr['bucket']]} {key(mr)}  {mr['title'][:60]}")
    if len(chosen) > args.max:
        print(f"\nlimiting to --max {args.max} (of {len(chosen)})")
        chosen = chosen[:args.max]
    if not args.yes:
        if input(f"\nStart {len(chosen)} review(s)? [y/N] ").strip().lower() != "y":
            print("aborted")
            return
    state = load_state()
    for mr in chosen:
        spin_up(mr, state)


def cmd_open(args):
    state = load_state()
    for url in args.urls:
        mr = mr_from_url(url)
        print(f"opening {key(mr)}  ({mr['url']})")
        spin_up(mr, state)


def cmd_status(args):
    state = load_state()
    if not state:
        print("no active reviews")
        return
    statuses = agent_statuses()
    for k, e in state.items():
        st = statuses.get(target(e), "gone")
        print(f"  {st:10} {k:32} {e.get('agent', '?')} ({target(e)})")


def cmd_read(args):
    state = load_state()
    k = resolve_key(state, args.mr)
    e = state.get(k) if k else None
    if not e:
        raise SystemExit(f"no active review for {args.mr}")
    res = run_json(["herdr", "agent", "read", target(e),
                    "--source", "recent", "--lines", str(args.lines)], check=False)
    text = (res or {}).get("result", {}).get("read", {}).get("text", "")
    print(text if text else json.dumps(res))


def cmd_close(args):
    state = load_state()
    if not state:
        print("no active reviews")
        return
    if args.all:
        targets = list(state.keys())
    elif args.idle:
        statuses = agent_statuses()
        targets = [k for k, e in state.items()
                   if statuses.get(target(e), "gone") in ("idle", "gone")]
    else:
        targets, missing = [], []
        for sel in args.selectors:
            k = resolve_key(state, sel)
            (targets.append(k) if k else missing.append(sel))
        for m in missing:
            print(f"  no active review: {m}")
    if not targets:
        print("nothing to close")
        return
    for k in targets:
        tear_down(k, state[k], state)


def main():
    p = argparse.ArgumentParser(prog="mr-review", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    pl = sub.add_parser("list", help="ranked table of pending reviews")
    pl.add_argument("--refresh", action="store_true", help="re-query GitLab")
    pl.set_defaults(func=cmd_list)

    ps = sub.add_parser("start", help="fan out reviews")
    ps.add_argument("selectors", nargs="*",
                    help="buckets (high|substantial|low|trivial|all) or repo!iid")
    ps.add_argument("--refresh", action="store_true")
    ps.add_argument("--max", type=int, default=DEFAULT_MAX)
    ps.add_argument("--yes", "-y", action="store_true", help="skip confirmation")
    ps.set_defaults(func=cmd_start)

    po = sub.add_parser("open", help="set up review(s) from MR url(s)")
    po.add_argument("urls", nargs="+", help="one or more GitLab MR urls")
    po.set_defaults(func=cmd_open)

    pst = sub.add_parser("status", help="agent status for active reviews")
    pst.set_defaults(func=cmd_status)

    pr = sub.add_parser("read", help="dump agent output")
    pr.add_argument("mr", help="repo!iid or MR url")
    pr.add_argument("--lines", type=int, default=200)
    pr.set_defaults(func=cmd_read)

    pc = sub.add_parser("close", help="tear down workspace + worktree + branch")
    pc.add_argument("selectors", nargs="*", help="repo!iid keys or MR urls")
    pc.add_argument("--all", action="store_true")
    pc.add_argument("--idle", action="store_true", help="close only finished reviews")
    pc.set_defaults(func=cmd_close)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
