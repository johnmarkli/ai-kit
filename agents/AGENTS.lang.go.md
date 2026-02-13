# AGENTS Go Conventions

Default guidance for working with Go (`.go`) code in this repository.

## Language + toolchain defaults

- Target modern stable Go (prefer Go 1.22+ conventions unless repo specifies otherwise).
- Use Go modules (`go.mod`) as source of truth for dependencies and Go version.
- Do not introduce new third-party dependencies unless needed and justified.

## Style and formatting

- Always format with `gofmt` (or `go fmt ./...` for broader changes).
- Keep imports grouped/ordered by standard Go tooling.
- Prefer small functions, clear names, and explicit error handling.
- Avoid unnecessary abstraction; favor simple, idiomatic Go.

## Error handling

- Return errors instead of panicking for expected/runtime failure paths.
- Wrap errors with context using `%w` when propagating (`fmt.Errorf("...: %w", err)`).
- Avoid swallowing errors; handle, wrap, or explicitly document why ignored.

## Context and concurrency

- Accept `context.Context` as first parameter for request-scoped work.
- Do not store `context.Context` in structs.
- Ensure goroutines have clear lifecycle/exit behavior (cancellation, channel close, or waitgroup).
- Be explicit about channel ownership (who sends, who closes).
- Protect shared mutable state (`sync.Mutex`, channels, atomics) and keep locking scopes tight.

## Testing defaults

- Add/update table-driven tests for behavior changes.
- Prefer deterministic tests; avoid time/network flakes unless explicitly integration tests.
- Run targeted tests first, then broader package/module tests.
- For bugfixes, include a regression test when practical.

## Project hygiene

- Keep packages cohesive; avoid cyclic dependencies.
- Prefer internal packages for non-public APIs when appropriate.
- Keep exported identifiers documented when part of public package surface.
- Maintain backwards compatibility unless a breaking change is requested.

## Validation checklist (Go)

Run what is relevant to the change size:

1. `gofmt` on changed files (or `go fmt ./...`)
2. `go test ./...` (or targeted `go test ./path/to/pkg -run TestName` first)
3. `go vet ./...` for non-trivial changes
4. Optional if available: `staticcheck ./...`

## Change discipline

- Make minimal, reversible edits.
- Update docs/examples when API or behavior changes.
- If requirements are ambiguous, ask a focused clarifying question before broad refactors.
