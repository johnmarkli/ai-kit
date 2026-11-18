# AGENTS Tools Guide

Use the right tool for the job. Prefer safe, inspectable, and minimal-change workflows.

## General defaults

- Use `read` to inspect file contents before editing.
- Use `bash` for discovery and shell operations (`ls`, `find`, `rg`, test/lint commands).
- Use `edit` for precise, surgical changes to existing files.
- Use `write` only for new files or full-file rewrites.
- Prefer one small verified change over broad refactors.

## File and code operations

### Explore and locate
- Before exploring, always make sure code is up to date with the latest on the remote
- Use `bash` with fast search tools:
  - `rg` for text search
  - `find` for paths
  - `ls` for directory structure

### Read and understand
- Use `read` to open relevant files.
- Read nearby context (imports, callers, tests) before changing behavior.

### Modify
- Use `edit` when changing specific blocks/lines.
- Use `write` when:
  - creating a new file
  - replacing an entire file intentionally

### Validate
- Use `bash` to run targeted checks first, then broader checks:
  - focused test(s) for changed code
  - lint/typecheck if relevant

## Git workflows

### Local git actions
- Use `bash` for local git commands:
  - `git status`, `git diff`, `git add -p`, `git commit`
- Do not rewrite commit history unless user asks explicitly.

### GitHub repositories
- Use `gh` for GitHub-specific operations when available:
  - PR create/view/review
  - issue view/comment
  - workflow run/status checks
- Prefer `gh` over raw API calls for GitHub tasks.
- To include screenshots/videos in PRs, issues, or comments, use `gh ... --attach '<file>#<alt text>'`
  (supported by `pr create|edit|comment`, `issue create|comment`). Reference the file as
  `![alt](./shot.png)` in the body and it's rewritten to the uploaded URL. Repeat `--attach`
  for several files (max 50). Don't commit screenshots or upload them some other way.
  Uploads get shareable public URLs: screenshots must not show secrets, PII, or PHI — use synthetic/dev data.

### GitLab repositories
- Use `glab` for GitLab-specific operations when available:
  - MR create/view/review
  - issue view/comment
  - pipeline status/actions
- Prefer `glab` over raw API calls for GitLab tasks.

### Create a Pull Request (PR) or Merge Request (MR)
- Ensure the working branch is updated with the latest main branch
- Ensure the branch was not already merged - if it is, then create a new branch off of the latest main

### Git Commit messages
- Use the Conventional Commits 1.0.0 format for all commits:
```text
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```
Reference: https://www.conventionalcommits.org/en/v1.0.0/


## Decision rules

- If task is file content inspection: `read`.
- If task is file/path/search discovery or command execution: `bash`.
- If task is precise code patch: `edit`.
- If task is new file/full rewrite: `write`.
- If remote repo task is GitHub: `gh`.
- If remote repo task is GitLab: `glab`.

## Other tools

- `slackcli` for slack

### Linear
- Don't add subscribers to Linear issues (e.g. `subscriberIds` on tool calls) unless the user names who to subscribe.
- Don't @-mention people in issue or comment bodies unless asked (mentions auto-subscribe them).

## Safety and reliability

- Always inspect before editing.
- Keep changes minimal and reversible.
- Surface uncertainty; ask focused clarifying questions when needed.
- Never expose secrets from env vars, credentials files, or command output.
