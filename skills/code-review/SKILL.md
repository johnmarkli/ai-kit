---
name: code-review
description: Structured code review workflow for pull requests and local changes. Use to find correctness bugs, security risks, performance regressions, maintainability issues, and missing tests before merge.
---

# Code Review

## When to use
Use this skill when asked to:
- review a PR/diff before merge
- identify bugs, edge cases, and regressions
- assess code quality and maintainability
- provide actionable review comments and priorities

## Inputs to gather
- diff or changed files in scope
- feature intent / acceptance criteria
- related issue or ticket context
- test results (unit/integration/e2e) and CI status
- constraints (backward compatibility, performance, security)

If context is missing, ask concise clarifying questions.

## Review workflow

1. Understand intent
- Summarize what the change is supposed to do.
- Confirm assumptions and non-goals.

2. Scan for high-risk areas first
- auth/authz, input validation, data writes, migrations
- concurrency/state management, caching, retries/timeouts
- external API boundaries and error handling

3. Check correctness
- Look for logical errors, edge cases, null/empty handling, off-by-one issues.
- Verify invariants and failure paths, not only happy path.

4. Check security and privacy
- Injection risks, unsafe deserialization, broken access control.
- Secret leakage in logs/config.
- Data exposure in responses/errors.

5. Check performance and reliability
- N+1 queries, unnecessary loops, expensive allocations.
- Blocking I/O in hot paths.
- Retry storms, missing circuit breakers/timeouts.

6. Check tests and observability
- Ensure tests cover changed behavior and edge cases.
- Ensure errors are surfaced with actionable logs/metrics.
- Call out missing tests explicitly.

7. Evaluate maintainability
- Naming clarity, complexity, cohesion, duplication.
- API consistency and backward compatibility.
- Adherence to existing project conventions.

8. Produce prioritized feedback
- Tag each finding by severity: `high`, `medium`, `low`, `nit`.
- Include file path, approximate location, why it matters, and concrete fix suggestion.
- Separate blocking issues from follow-up improvements.

## Output format
Use this structure:

1. **Summary** (2-5 bullets)
2. **Blocking issues** (if any)
   - Severity, path, issue, suggested fix
3. **Non-blocking improvements**
4. **Test gaps**
5. **Risk assessment**
6. **Merge recommendation** (`approve`, `approve-with-follow-ups`, `request-changes`)

## Guardrails
- Do not invent behavior not present in the diff.
- Do not over-index on style nits when correctness/security issues exist.
- Be specific and actionable; avoid vague comments.
- If uncertain, state uncertainty and what evidence is needed.
- Do not expose secrets from code, logs, or environment.
