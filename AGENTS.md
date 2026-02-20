# AGENTS.md

This file is for fresh LLM coding sessions working in this repository.

It explains how to understand the project, contribute safely, and stand up the MCP server when requested by a user.

## Project Snapshot

- Project: Nextcloud MCP server (Python, FastMCP, async/httpx).
- Main package: `nextcloud_mcp_server`.
- Primary deployment targets: local dev, Podman container, NixOS service.
- Current repo additions in this branch include:
  - `flake.nix` with `devShell`, runnable app, and NixOS module
  - `docs/nixos-systemd.md`
  - `tools/nextcloud-mcp-server.service`
- Authentication default for practical deployments: Basic Auth with Nextcloud app password.

## Golden Rules for Agents

1. Never commit or print real credentials.
2. Prefer app passwords over account passwords.
3. Assume Docker may be unavailable; prefer Podman commands.
4. Validate with health endpoint and one real MCP tool call.
5. Keep changes minimal, typed, and tested.

## First 5 Minutes in a New Session

1. Read `README.md` and `docs/nixos-systemd.md`.
2. Read `pyproject.toml` for toolchain and test commands.
3. Check run mode needed by user:
   - local (`uv run ...`)
   - Podman
   - NixOS module/service
4. Confirm required environment variables are available:
   - `NEXTCLOUD_HOST`
   - `NEXTCLOUD_USERNAME`
   - `NEXTCLOUD_PASSWORD`
5. Run quick readiness test after startup:
   - `curl -fsS http://127.0.0.1:<port>/health/ready`

## Architecture Map

- Entry point: `nextcloud_mcp_server/app.py`
- CLI: `nextcloud_mcp_server/cli.py`
- Clients: `nextcloud_mcp_server/client/`
- MCP tools/resources: `nextcloud_mcp_server/server/`
- Auth/token flows: `nextcloud_mcp_server/auth/`
- Models: `nextcloud_mcp_server/models/`
- Tests: `tests/` (unit, integration, oauth, smoke)

## Coding and Contribution Standards

### Async and typing

- Use `anyio` patterns for structured concurrency.
- Type all signatures.
- Use modern Python union syntax (`str | None`).

### Tool annotations (required)

All MCP tools must use `ToolAnnotations` with correct hints:

- read/list/search/get: `readOnlyHint=True`
- delete: `destructiveHint=True`
- idempotent operations: set `idempotentHint` correctly
- all Nextcloud-facing tools: `openWorldHint=True`

Reference: `docs/ADR-017-mcp-tool-annotations.md`.

### Response shape

- Do not return raw `list[dict]` from MCP tools.
- Convert to Pydantic models and return response wrappers in `models/`.

### Quality checks before finishing

```bash
uv run ruff check
uv run ruff format
uv run ty check -- nextcloud_mcp_server
uv run pytest tests/unit/ -v
```

Use wider test scope when touching auth, MCP wiring, or integration boundaries.

## Podman-First Runbook

Use this when user asks to run server in a container and Docker is not installed.

### Pull and run

```bash
podman pull ghcr.io/cbcoutinho/nextcloud-mcp-server:latest
podman run -d --name nextcloud-mcp \
  --env-file .env \
  -p 127.0.0.1:8000:8000 \
  ghcr.io/cbcoutinho/nextcloud-mcp-server:latest \
  --transport streamable-http
```

### Validate

```bash
curl -fsS http://127.0.0.1:8000/health/ready
podman logs --tail 80 nextcloud-mcp
```

### If startup fails

- Check host port conflicts (`8000`, `9090` are common).
- Rebind host port if needed (for example `18000:8000`).
- If metrics port conflicts occur, set `METRICS_PORT` in env.

## Local Runbook (No Container)

```bash
uv sync --group dev
set -a && source .env && set +a
uv run nextcloud-mcp-server run --transport streamable-http --host 127.0.0.1 --port 8000
```

Then:

```bash
curl -fsS http://127.0.0.1:8000/health/ready
```

## NixOS Runbook

Use module from `flake.nix`:

1. Add flake input.
2. Import `nixosModules.default`.
3. Set `services.nextcloud-mcp-server.*` options.
4. Create `/etc/nextcloud-mcp-server.env` with `0600`.
5. `nixos-rebuild switch`.
6. Verify service + health endpoint.

Reference: `docs/nixos-systemd.md`.

## How to Fulfill "Stand Up MCP Server" Requests

When a user asks to stand up the server, do this in order:

1. Confirm deployment target (Podman/local/NixOS).
2. Confirm credentials are provided via env file, not inline.
3. Start service.
4. Verify `/health/ready`.
5. Execute one MCP tool call (for example `nc_webdav_list_directory`).
6. Report endpoint and test result.

Minimum acceptance criteria:

- Server process is running.
- Health check returns `status=ready`.
- At least one authenticated tool call succeeds.

## Credential and Secret Hygiene

- Never place real secrets in tracked files.
- `.env` files should stay untracked and local.
- Redact sensitive values in logs, examples, and PR text.
- Before finalizing, scan for leaks:

```bash
rg -n "NEXTCLOUD_PASSWORD=|NEXTCLOUD_USERNAME=|api[_-]?key|token|secret" .
```

Then manually verify matches are examples/tests only.

## Troubleshooting Notes

- `OSError: Read-only file system: '/app'` in local runs means container-only paths leaked into host config.
  - Set `TOKEN_STORAGE_DB` to a writable host path (for example `/tmp/tokens.db` or `/var/lib/nextcloud-mcp-server/tokens.db`).
- `Address already in use`:
  - choose alternate host port and retry.
- OAuth issues:
  - prefer Basic Auth unless user explicitly needs OAuth and upstream requirements are met.

## Useful Files

- `README.md`
- `docs/nixos-systemd.md`
- `docs/configuration.md`
- `docs/authentication.md`
- `docs/running.md`
- Use this `AGENTS.md` as the source of truth for agent guidance in this branch.
