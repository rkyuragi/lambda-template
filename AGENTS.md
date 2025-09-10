# Repository Guidelines

## Project Structure & Module Organization
- `src/` – Lambda handlers and shared modules (one folder per function).
- `tests/` – Unit/integration tests mirroring `src/` paths.
- `infra/` – IaC (e.g., SAM/CloudFormation/Terraform) and deployment templates.
- `scripts/` – Dev/CI helper scripts (idempotent, shell-safe).
- `.github/workflows/` – CI definitions.

Example: `src/hello/handler.py` or `src/hello/handler.ts`; tests in `tests/hello/`.

## Build, Test, and Development Commands
- `make setup` – Install dependencies for all submodules.
- `make lint` – Run formatters and linters.
- `make test` – Execute test suite with coverage.
- `make build` – Produce deployment artifacts (e.g., SAM/Terraform packages).
- `make local` – Run locally (e.g., `sam local start-api`).

If no Makefile: Node – `npm ci && npm test`; Python – `pip install -r requirements.txt && pytest`.

## Coding Style & Naming Conventions
- Python: 4-space indent; tools: `black`, `ruff`, `mypy` when applicable; files `snake_case.py`.
- Node/TS: 2-space indent; tools: `eslint`, `prettier`, `tsc`; files `kebab-case.ts` for modules.
- Handlers: name entrypoint `handler` (e.g., `handler.py` or `handler.ts`).
- Keep functions small; prefer pure utilities in `src/lib/`.

## Testing Guidelines
- Frameworks: Python `pytest`; Node `jest` or `vitest`.
- Location: `tests/` mirrors `src/` (e.g., `tests/hello/test_handler.py`, `tests/hello/handler.test.ts`).
- Coverage: target ≥80%; fail CI if below when feasible.
- Include edge cases (timeouts, bad input, IAM errors).

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.
- Keep commits focused; prefer small, reviewable diffs.
- PRs must include: purpose, summary of changes, how to test, linked issues; add screenshots/logs when relevant.

## Security & Configuration Tips
- Never commit secrets; use `env.example` and parameter stores (SSM/Secrets Manager).
- Apply least-privilege IAM; restrict resource ARNs per function.
- Validate inputs at handler boundary; log PII-safe messages only.

## Agent-Specific Instructions
- Follow this AGENTS.md across the repo scope; keep changes minimal and localized.
- Do not add licenses/headers; avoid broad refactors unless requested.
- When adding files, use the structure above and include/update tests.
