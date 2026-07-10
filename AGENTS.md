# Repository Guidelines

Before doing any work, read:

`/Users/mythic3014/.codex/AGENTS.md`

Then follow its skill routing, RTK command rule, and spore runtime skill registry.

Do not proceed using only this repository-local file.

## Project Structure & Module Organization

- Backend code lives in `src/main/java/com/freshchain/**` (module-first packages: `auth`, `admin`, `inventory`, `delivery`, `requests`, `reporting`, `shared`).
- Web resources and legacy JSP views are in `src/main/webapp/**` (still present during SPA migration).
- Frontend SPA is in `frontend/` (React + Vite + TypeScript). Shared client utilities are under `frontend/src/shared/**`.
- Backend tests are in `src/test/java/**`; legacy manual utilities are under `src/test/java/com/freshchain/legacy/manual/**`.
- Planning and design docs are under `docs/` and `docs/plans/`.

## Build, Test, and Development Commands

- `rtk npm run build` (from `frontend/`): type-check and build SPA assets.
- `rtk npm test` (from `frontend/`): run Vitest unit tests.
- `rtk mvn clean package -DskipTests` (repo root): build WAR (Java 21 + frontend integration via Maven plugin).
- `rtk docker compose up --build` (repo root): run app stack locally in containers.
- If `rtk` is unavailable in your shell, run the same commands without `rtk`.

## Coding Style & Naming Conventions

- TypeScript: strict mode; avoid `any` (prefer `unknown` + narrowing).
- Java: keep servlet/controllers thin (`web/api -> service -> repository`), business rules in services.
- Naming: React components `PascalCase.tsx`; hooks/utilities `camelCase.ts`; tests `*.test.ts(x)`.
- Keep edits small and module-scoped; prefer extending existing patterns over introducing parallel abstractions.

## Testing Guidelines

- Frontend testing uses Vitest + Testing Library (`frontend/src/test/setup.ts`).
- Add tests for new UI states (loading/empty/error) and API adapters.
- Backend changes should include focused JUnit tests in matching package paths under `src/test/java`.
- Run at minimum:
  - `rtk npm test && rtk npm run build` in `frontend/`
  - relevant Maven/test commands for backend slices.

## Commit & Pull Request Guidelines

- Use Conventional-style commits seen in history, e.g.:
  - `feat(frontend): add session-bootstrapped react shell`
  - `test(frontend): add unit test baseline`
- Keep commits reviewable (single concern per commit).
- PRs should include: scope summary, affected modules, verification commands/results, and screenshots/GIFs for UI changes.

## Security & Configuration Tips

- Do not hardcode secrets; use environment variables (`.env`, container env).
- Keep session-cookie + CSRF protections intact when changing auth flows.
- Prefer Dockerized local runs over ad-hoc runtime setup.
