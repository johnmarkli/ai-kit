# AGENTS Org Conventions (indigo)

Org defaults for the `IndigoIO/project-indigo` monorepo (`~/indigo/project-indigo`).
Repo `CLAUDE.md` + `docs/` are canonical; when they disagree with this file, the repo wins.

## Domain (one paragraph)

Internal ops web app ("the Portal") that runs CA workers'-comp medical-legal evaluations
(QME/AME/IME) for partner physicians. LLMs read medical records (MRR), draft the history
(HOI), suggest impairment ratings, and draft the final report. Lifecycle:
inquiry → pre-appointment (MRR + HOI) → appointment (exam) → post-appointment
(assessment → report → package) → billing. Glossary: `docs/domain/UBIQUITOUS_LANGUAGE.md`,
`docs/architecture/GLOSSARY.md`. Naming rule: MRR/entry in UI & prompts, briefing/segment in code.

## Stack + repo map

- `portal/` React + TS (Ant Design, Tailwind, Jotai, react-query, Amplify Gen 1, Biome).
- `services/` shared Python libs — business logic lives here; entry points stay thin.
- `lambdas/` sync compute; `batch_jobs/` Step Function–chained containers; `ecs/` FastAPI `api_server` + `webhook_ingestion`.
- `cdk/` TS infra (~60 stacks). Config = single source of truth: `lambda.config.ts`, `batch-jobs.config.ts`, `ecs.config.ts`, `dynamo-configs.ts`, `dlq-config.ts` — change the config, not the stack.
- `prompts/` YAML prompts → codegen into `services/llm/generated/` (never hand-edit).
- `docs/features/<key>/ARCHITECTURE.md` per registered feature; `specs/` design history; `oncall/` runbooks; `.claude/skills/` ~100 workflows.
- Two infra stacks: Amplify (Portal, AppSync, Cognito, 95 Dynamo tables from `portal/amplify/backend/api/portal/schema.graphql`) and CDK (everything else). Deploy independently.
- AWS `us-east-1`, envs `dev`/`stage`/`prod` (env-suffixed resources). `main`→dev, `stage`, `prod`.

## Hard rules

- Prod holds PHI. Never put real PII in code, prompts, tests, docs, commits, branch names, PR text. Opaque UUIDs ok. Prod data access = `phi-prod-warning` skill + break-glass.
- Never edit `schema.graphql` or run `amplify push` unless explicitly asked.
- Never push to `main`; never merge without approval.
- Task names a registered feature → read `docs/features/<key>/ARCHITECTURE.md` before code.
- Temp files under `/tmp/<branch>/`, never flat `/tmp/foo`.
- Adding a FastAPI route silently 404s until `cdk/lib/ecs.config.ts` knows the path (`add-api-server-endpoint` skill).

## Git / PR workflow

- Remotes: `origin` = personal fork, `fork` = `IndigoIO/project-indigo`. Branch **before** editing: `git fetch fork main && git checkout -b <branch> fork/main`.
- Push `git push fork <branch>`. PR: `gh pr create --repo IndigoIO/project-indigo --head <branch> --title "[Surface] Action: description"` — tag by product surface (`[MRR]`, `[Assessment]`); eng layer only for cross-cutting (`[CDK]`, `[Docs]`); `[Schema]` for schema-only.
- Iterate with new commits — no `--amend`/force-push on open PRs. Squash-merge after approval. Hotfix sync-backs (`prod`→`main`) use a merge commit, never squash.
- Changing a prompt of a registered feature requires a `PROMPT_CHANGELOG.md` entry in the same PR (CI gate).
- `pr-cycle` skill automates the loop.

## Gate + testing

- `./prefly.sh` (add `--portal` for frontend) after every change: lint, format, typecheck, tests, doc regen. `--full-tests` for everything.
- Python: `uv` workspace, py 3.12. `uv run pytest -m "not manual and not integration"` (don't exclude asyncio).
- Favor E2E anchors over mocks: run the colocated `manual_test.py` (`uv run python -m <path>.manual_test`) against dev; integration tests in `*/tests/integration/` (`--local` runs in-process). Unit suite stays lean.
- Portal: `cd portal && npm test`; Playwright for browser flows. Zero `tsc` errors; Biome, not ESLint/Prettier.

## Code conventions

- Thin entry points (`handler.py`/`main.py`/router): parse input (Pydantic) → build deps → `service.process()` → map errors. Template: `lambdas/hoi/hoi_gen/handler.py`.
- Services take fully-built collaborators via constructor; never read env/secrets or build own deps.
- Typing: `str | None`, built-in generics, Pydantic everywhere, `StrValueEnum`; avoid `Any`/`getattr` — use generated GraphQL models.
- Imports: top-of-file, absolute, no re-exports (each container installs only its own deps). New pyproject workspace edge = design signal.
- Async: `asyncio.gather()` for independent work, never sequential awaits.
- Explicit over config-driven; terse code/comments/PR bodies; follow the closest existing pattern and cite it.
- Prompts: YAML with `{{ input.field }}` + `include_prompts` partials, no conditionals; variants = separate files. Typed Pydantic I/O in `services/models/`. Examples must be synthetic.
- Persistence: generated `services/graphql_client/` (typed, triggers subscriptions) or `services/dynamo/`; new storage per `specs/dynamo-repository-pattern.md`.
- Portal UI under `pages/` → `portal-ui` skill; avoid `as` casts.

## Tools

- Linear (tickets like `GET-1234`), GitHub (`gh`), Slack `#eng_ops` / `#eng_prod`, Notion, AWS CLI (dev-permissions IAM group).
- Skills to reach for: `pr-cycle`, `build-lambda`/`build-batch-job`/`build-ecs`/`deploy-cdk`, `investigate-appointment`, `debug-briefing`, `manage-prompts`, `tune-prompt`, `find-batch-logs`, `write-a-spec`.
