# AGENTS TypeScript Conventions

Default guidance for working with TypeScript (`.ts` / `.tsx`) code in this repository.

## Language + project defaults

- Prefer strict TypeScript settings (`"strict": true`) unless the repo specifies otherwise.
- Target modern ECMAScript and module settings already used by the project.
- Avoid adding new runtime dependencies unless necessary and justified.
- Prefer ESM/CJS style already established in the repo; do not mix module styles casually.

## Style and code quality

- Follow existing formatter/linter config (Prettier/ESLint if present).
- Keep functions small and names descriptive.
- Prefer explicit types at public boundaries; allow inference for obvious local variables.
- Avoid `any`; use `unknown` + narrowing when type is uncertain.
- Prefer `readonly`/immutability for values not meant to change.

## Types and API design

- Model domain concepts with precise types/interfaces/type aliases.
- Prefer discriminated unions over boolean flags for multi-state logic.
- Keep exported types stable; avoid breaking public contracts without request.
- Use generics when they simplify reuse, but avoid over-abstracting.

## Error handling

- Throw or return errors consistently per project convention.
- Add contextual information to errors.
- Do not swallow errors silently; handle, rethrow, or document intentional ignore cases.
- For async code, always handle promise rejection paths.

## Async and concurrency

- Prefer `async/await` over raw `.then()` chains for readability.
- Use `Promise.all` for independent work; use `Promise.allSettled` when partial failure is acceptable.
- Avoid unbounded parallelism; add limits for large fan-out operations.
- Support cancellation (`AbortSignal`) for request-scoped operations when relevant.

## Testing defaults

- Add/update tests for behavior changes.
- Prefer deterministic tests and stable fixtures.
- Cover runtime behavior and important type-level guarantees where practical.
- For bugfixes, add a regression test when feasible.

## Validation checklist (TypeScript)

Run what exists in the repo, usually in this order:

1. Format changed files (`prettier --write` or project formatter command)
2. Lint (`eslint` or project lint command)
3. Typecheck (`tsc --noEmit` or project typecheck command)
4. Tests (targeted first, then full suite)

## Change discipline

- Keep changes minimal and reversible.
- Update docs/examples when API or behavior changes.
- If requirements are ambiguous, ask a focused clarifying question before broad refactors.
