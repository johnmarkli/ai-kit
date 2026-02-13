---
name: investigate-bug
description: Systematic debugging workflow for runtime errors, failing tests, flaky behavior, broken builds, and regressions. Use when the goal is to identify root cause and deliver a minimal verified fix.
---

# Investigate Bug

## When to use
Use this skill when the user asks to:
- fix a failing test or CI check
- diagnose an exception, crash, or incorrect output
- investigate a regression or intermittent/flaky behavior
- explain why something that previously worked now fails

## Inputs to gather first
- exact failing command (and full error text)
- expected behavior vs actual behavior
- scope and impact (single function, module, app-wide)
- environment details (OS, runtime version, dependencies, flags)
- recent changes likely related to the failure

If key inputs are missing, ask concise targeted questions before changing code.

## Workflow

1. Reproduce reliably
- Run the smallest command that reproduces the issue.
- Capture exact output and stack trace.
- If not reproducible, document what was tried and why.

2. Contain the blast radius
- Identify the narrowest failing layer (input, function, module, integration boundary).
- Prefer local repro over full-suite runs while investigating.

3. Form hypotheses
- Create 2-4 plausible root-cause hypotheses.
- Rank by likelihood and test cost.
- Test one hypothesis at a time.

4. Instrument and verify
- Add temporary logs/assertions or focused tests to validate assumptions.
- Remove temporary instrumentation before finalizing, unless user requests it kept.

5. Apply minimal fix
- Implement the smallest change that resolves root cause.
- Avoid unrelated refactors unless explicitly requested.

6. Validate broadly enough
- Re-run the original failing command.
- Run nearby tests/checks likely affected by the change.
- If broader validation is skipped, state it explicitly.

7. Report clearly
Provide:
- root cause (plain language)
- what changed (files + rationale)
- verification run and outcome
- residual risk / follow-up recommendations

## Output checklist
- [ ] Reproduction command documented
- [ ] Root cause identified (or clear uncertainty stated)
- [ ] Minimal fix applied
- [ ] Relevant checks re-run
- [ ] Risks and follow-ups listed

## Guardrails
- Do not fabricate reproduction or test results.
- Do not claim certainty when evidence is incomplete.
- Do not introduce broad cleanup/refactors during debugging unless requested.
- Do not expose secrets from env vars, configs, logs, or command output.

## Escalation guidance
Escalate to user when:
- issue is non-deterministic and needs production telemetry
- fix requires architectural change or schema migration
- behavior depends on external systems/credentials you cannot access
