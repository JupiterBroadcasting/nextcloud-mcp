# Fix Spec: nextcloud-mcp-server

## Overview

This document lists all issues found in the deep code review and provides
step-by-step instructions for fixing them. Issues are grouped by severity.
The primary use case is **file operations via WebDAV** — prioritize accordingly.

Verify every fix by running:
```bash
uv run pytest tests/unit/ -v
```

---

## Issue 1 (HIGH): 4 failing tests in `test_instrument_tool.py`

### Root cause

`mock_tracer` patches `nextcloud_mcp_server.observability.tracing.trace_operation`
but `instrument_tool` (in `metrics.py`) already imported `trace_operation` into its
own namespace at module load time. Patching the source module does not affect the
already-bound name in `metrics.py`.

**The rule**: always patch where the name is *used*, not where it is *defined*.

### Fix

In `tests/unit/test_instrument_tool.py`, change the `mock_tracer` fixture:

```python
# BEFORE (wrong — patches the source module)
with patch(
    "nextcloud_mcp_server.observability.tracing.trace_operation"
) as mock_trace:

# AFTER (correct — patches the bound name in the using module)
with patch(
    "nextcloud_mcp_server.observability.metrics.trace_operation"
) as mock_trace:
```

### Affected tests (4)
- `test_decorator_creates_trace_span`
- `test_decorator_sanitizes_sensitive_arguments`
- `test_decorator_limits_argument_string_length`
- `test_decorator_with_no_arguments`

---

## Issue 2 (HIGH): 10 failing tests in `test_management_status_endpoint.py`

### Root cause

The tests patch `nextcloud_mcp_server.config_validators.detect_auth_mode` but
`management.py` imports with `from nextcloud_mcp_server.config_validators import detect_auth_mode`,
so the local name is bound at import time. Patching the source module does not change
the already-bound name in `management.py`.

There are two wrong patch targets in these tests:

| Patched (wrong) | Correct target |
|---|---|
| `nextcloud_mcp_server.config_validators.detect_auth_mode` | `nextcloud_mcp_server.api.management.detect_auth_mode` |

`get_settings` is patched as `nextcloud_mcp_server.config.get_settings` — this is
**correct** because `management.py` calls `get_settings()` at runtime (function call,
not rebinding at import), but only if `get_settings` is not cached. Check by
inspecting — if still failing after the `detect_auth_mode` fix, also change
`get_settings` patch target to `nextcloud_mcp_server.api.management.get_settings`.

### Fix

In **every** `with patch(...)` block in `test_management_status_endpoint.py`,
change the `detect_auth_mode` patch target:

```python
# BEFORE (wrong)
patch(
    "nextcloud_mcp_server.config_validators.detect_auth_mode",
    return_value=AuthMode.MULTI_USER_BASIC,
),

# AFTER (correct)
patch(
    "nextcloud_mcp_server.api.management.detect_auth_mode",
    return_value=AuthMode.MULTI_USER_BASIC,
),
```

Apply this same change to every occurrence (there are ~7 test methods, each with
one patch context manager).

### Affected tests (10, but OIDC-related ones are 7 + 3 basic ones)
All 10 tests in `TestStatusEndpointOidcConfig` and `TestStatusEndpointBasicResponse`.

---

## Issue 3 (HIGH): 4 failing tests in `test_management_app_password_endpoints.py`

### Root cause

Tests patch `nextcloud_mcp_server.config.get_settings` but
`nextcloud_mcp_server/api/passwords.py` imports with
`from nextcloud_mcp_server.config import get_settings` and calls `get_settings()`
directly. Same "patch where used" rule applies.

### Fix

In every test that patches `get_settings`, change:

```python
# BEFORE (wrong)
mocker.patch(
    "nextcloud_mcp_server.config.get_settings",
    return_value=MagicMock(...),
)

# AFTER (correct)
mocker.patch(
    "nextcloud_mcp_server.api.passwords.get_settings",
    return_value=MagicMock(...),
)
```

Tests that need this fix:
- `test_provision_app_password_success`
- `test_provision_app_password_nextcloud_validation_fails`
- `test_provision_app_password_rate_limiting`
- `test_rate_limiting_is_per_user`

---

## Issue 4 (MEDIUM): Correctness bug — empty-string inputs silently dropped in `client/notes.py`

### Location
`nextcloud_mcp_server/client/notes.py`, lines ~92 and ~128

### Root cause

```python
# Bug: falsy check treats empty string as "not provided"
if title:
    payload["title"] = title
```

An empty string `""` is falsy in Python, so `title=""` silently discards the
update and the note keeps its old title. This affects `create_note` and
`update_note`.

### Fix

Change all falsy checks on optional string parameters to explicit `None` checks:

```python
# Before (wrong for empty strings)
if title:
    payload["title"] = title

# After (correct — only skips when caller passed None)
if title is not None:
    payload["title"] = title
```

Apply to all optional string parameters in `create_note` and `update_note`:
`title`, `content`, `category`.

---

## Issue 5 (MEDIUM): Security — auth token prefix logged at INFO level

### Location
`nextcloud_mcp_server/app.py`, search for `token[:50]` or similar near the `/mcp`
request handler.

### Root cause

The first 50 characters of the bearer token are logged at INFO level on every
MCP request. This leaks authentication material into logs.

### Fix

Remove or redact the token from the log message:

```python
# Before
logger.info(f"MCP request received, token: {token[:50]}...")

# After — log only that a token is present, not its value
logger.debug("MCP request received with bearer token")
```

If the token preview is intentional for debugging, change log level to DEBUG and
truncate to ≤8 characters (enough to identify a token without being useful to an
attacker):

```python
logger.debug(f"MCP request received, token prefix: {token[:8]}...")
```

---

## Issue 6 (LOW-MEDIUM): 3 debug `print()` statements in production code

### Location
`nextcloud_mcp_server/app.py`, lines ~1215, ~1227, ~1232

### Fix

Remove all three `print("DEBUG: ...")` statements. They write to stdout in
production, interfering with logging infrastructure and potentially leaking
internal state.

---

## Issue 7 (LOW): Resource leak — `UnifiedTokenVerifier.http_client` never closed

### Location
`nextcloud_mcp_server/auth/unified_verifier.py`

### Root cause

`UnifiedTokenVerifier` creates an `httpx.AsyncClient` in `__init__` (or lazily)
but never calls `.aclose()` on it. In OAuth mode the server runs for a long time,
and the underlying connection pool leaks.

### Fix

Add a `close()` or `aclose()` method and call it in the application lifespan
teardown in `app.py`:

```python
# In unified_verifier.py
async def aclose(self) -> None:
    """Release the underlying HTTP client connections."""
    if self.http_client:
        await self.http_client.aclose()
```

```python
# In app.py starlette_lifespan (teardown section)
if token_verifier:
    await token_verifier.aclose()
```

---

## Verification checklist

After applying all fixes:

```bash
# Must pass with 0 failures
uv run pytest tests/unit/ -v

# Confirm 0 ruff issues
uv run ruff check nextcloud_mcp_server/

# Optional — type check
uv run ty check -- nextcloud_mcp_server
```

Expected: **344 passed, 0 failed** (all 329 previously passing + 15 newly fixed).
