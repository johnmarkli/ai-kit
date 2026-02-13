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

### GitLab repositories
- Use `glab` for GitLab-specific operations when available:
  - MR create/view/review
  - issue view/comment
  - pipeline status/actions
- Prefer `glab` over raw API calls for GitLab tasks.

### Create a Pull Request (PR) or Merge Request (MR)
- Ensure the working branch is updated with the latest main branch
- Ensure the branch was not already merged - if it is, then create a new branch off of the latest main

## Decision rules

- If task is file content inspection: `read`.
- If task is file/path/search discovery or command execution: `bash`.
- If task is precise code patch: `edit`.
- If task is new file/full rewrite: `write`.
- If remote repo task is GitHub: `gh`.
- If remote repo task is GitLab: `glab`.

## Safety and reliability

- Always inspect before editing.
- Keep changes minimal and reversible.
- Surface uncertainty; ask focused clarifying questions when needed.
- Never expose secrets from env vars, credentials files, or command output.
