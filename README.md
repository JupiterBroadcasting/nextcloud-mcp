<p align="center">
  <img src="astrolabe.svg" alt="Nextcloud MCP Server" width="128" height="128">
</p>

# Nextcloud MCP Server

[![Docker Image](https://img.shields.io/badge/docker-ghcr.io/cbcoutinho/nextcloud--mcp--server-blue)](https://github.com/cbcoutinho/nextcloud-mcp-server/pkgs/container/nextcloud-mcp-server)
[![smithery badge](https://smithery.ai/badge/@cbcoutinho/nextcloud-mcp-server)](https://smithery.ai/server/@cbcoutinho/nextcloud-mcp-server)

Production-ready MCP server that connects AI assistants to your Nextcloud instance.

Use Claude, GPT, Gemini, and other MCP-compatible clients to create notes, manage calendars, work with contacts, and browse files through natural language workflows.

## Quick Start (NixOS First)

This repository now includes:

- `flake.nix` for a dev shell and runnable app
- `nixosModules.default` for service deployment on NixOS
- `tools/nextcloud-mcp-server.service` as a generic systemd template

### 1) Add this repository as an input in your system flake

```nix
{
  inputs.nextcloud-mcp-server.url = "github:YOUR_ORG/nextcloud-mcp-server";
}
```

### 2) Enable the module in your NixOS configuration

```nix
{
  imports = [ inputs.nextcloud-mcp-server.nixosModules.default ];

  services.nextcloud-mcp-server = {
    enable = true;
    workingDirectory = "/srv/nextcloud-mcp-server";
    environmentFile = "/etc/nextcloud-mcp-server.env";
    host = "127.0.0.1";
    port = 8000;
    transport = "streamable-http";
    metricsPort = 9090;
  };
}
```

### 3) Create the environment file with Nextcloud credentials

```bash
sudo install -m 0600 -o root -g root /dev/null /etc/nextcloud-mcp-server.env
sudo tee /etc/nextcloud-mcp-server.env >/dev/null <<'EOF'
NEXTCLOUD_HOST=https://cloud.example.com
NEXTCLOUD_USERNAME=your_nextcloud_username
NEXTCLOUD_PASSWORD=your_nextcloud_app_password
EOF
```

### 4) Deploy and verify

```bash
sudo nixos-rebuild switch
systemctl --no-pager --full status nextcloud-mcp-server
curl -fsS http://127.0.0.1:8000/health/ready
```

### 5) Connect your MCP client

- `http://127.0.0.1:8000/mcp` for `streamable-http`
- `http://127.0.0.1:8000/sse` for SSE transport (if configured)

## How Credentials Are Passed

The server reads credentials from environment variables:

- `NEXTCLOUD_HOST`
- `NEXTCLOUD_USERNAME`
- `NEXTCLOUD_PASSWORD`

On NixOS, the recommended method is `services.nextcloud-mcp-server.environmentFile`.

Security guidance:

- Use an app password from Nextcloud, not your interactive account password.
- Keep env files outside git (for example, `/etc/nextcloud-mcp-server.env`).
- Restrict file permissions to `0600`.
- Rotate app passwords if they are ever exposed.
- Do not hardcode credentials in `configuration.nix`, scripts, commit history, or screenshots.

Optional environment variables:

- `TOKEN_ENCRYPTION_KEY` (recommended for encrypted token persistence features)
- `TOKEN_STORAGE_DB` (default is `/tmp/tokens.db`, override for persistent storage)
- `METRICS_PORT` (default `9090`)

## LLM Agents: NixOS Install Runbook

Use this section when an agentic LLM session is asked to install and configure this MCP server on a NixOS host.

### Inputs the agent should request first

- Nextcloud URL
- Nextcloud username
- Nextcloud app password
- Desired MCP bind host and port
- Whether reverse proxy/TLS is required

### Agent workflow checklist

1. Confirm host is NixOS and flake-based.
2. Add this repo as a flake input.
3. Import `nixosModules.default`.
4. Configure `services.nextcloud-mcp-server`.
5. Create `/etc/nextcloud-mcp-server.env` with `0600` permissions.
6. Apply config with `nixos-rebuild switch`.
7. Validate service health endpoint.
8. Run an MCP smoke test (list a directory, read a file).

### Command sequence for an agent session

```bash
sudo install -d -m 0755 /srv/nextcloud-mcp-server
sudo install -m 0600 -o root -g root /dev/null /etc/nextcloud-mcp-server.env
sudoedit /etc/nextcloud-mcp-server.env
sudo nixos-rebuild switch
systemctl --no-pager --full status nextcloud-mcp-server
curl -fsS http://127.0.0.1:8000/health/ready
```

### Agent completion criteria

A successful agent run should return:

- Service state (`active (running)`)
- Health check payload from `/health/ready`
- MCP endpoint URL
- Any required follow-up (reverse proxy, firewall, OAuth mode, backups)

## Alternative Quick Starts

### Docker (Self-Hosted)

```bash
cat > .env << EOF
NEXTCLOUD_HOST=https://your.nextcloud.instance.com
NEXTCLOUD_USERNAME=your_username
NEXTCLOUD_PASSWORD=your_app_password
EOF

docker run -p 127.0.0.1:8000:8000 --env-file .env --rm \
  ghcr.io/cbcoutinho/nextcloud-mcp-server:latest

curl http://127.0.0.1:8000/health/ready
```

### Smithery (Managed)

Use [Smithery](https://smithery.ai/server/@cbcoutinho/nextcloud-mcp-server) for hosted setup.

> [!NOTE]
> Smithery runs in stateless mode without full semantic-search infrastructure by default.

## Key Features

- 90+ MCP tools across major Nextcloud apps
- MCP resources for structured URI-based data access
- Semantic search (experimental) with optional vector infrastructure
- Document processing (OCR/text extraction for supported files)
- Flexible deployment: NixOS, Docker, Kubernetes, VM, local
- Authentication modes: Basic Auth (recommended), OAuth/OIDC (experimental)
- Multiple transports: `streamable-http`, HTTP, SSE

## Supported Apps

| App | Tools | Capabilities |
|-----|-------|--------------|
| **Notes** | 7 | Full CRUD, keyword search, semantic search |
| **Calendar** | 20+ | Events, todos, recurrence, attendees |
| **Contacts** | 8 | CardDAV operations and address books |
| **Files (WebDAV)** | 12 | File/folder operations and document processing |
| **Deck** | 15 | Boards, stacks, cards, labels, assignments |
| **Cookbook** | 13 | Recipe management and URL import |
| **Tables** | 5 | Row operations on Nextcloud Tables |
| **Sharing** | 10+ | Share create/list/manage |

## Authentication

Basic Auth with app passwords is recommended for production single-user setups.

> [!IMPORTANT]
> OAuth2/OIDC support is experimental and depends on upstream `user_oidc` behavior.
> See [docs/oauth-upstream-status.md](docs/oauth-upstream-status.md) and [docs/authentication.md](docs/authentication.md).

## Semantic Search

Semantic search is experimental and opt-in:

- Disabled by default (`ENABLE_SEMANTIC_SEARCH=false`)
- Requires additional infrastructure (for example Qdrant plus embedding provider)
- Supports semantic retrieval workflows for supported apps

See [docs/semantic-search-architecture.md](docs/semantic-search-architecture.md) and [docs/configuration.md](docs/configuration.md).

## Documentation

### Getting Started

- **[Installation](docs/installation.md)** - Docker, Kubernetes, local, VM
- **[NixOS and systemd](docs/nixos-systemd.md)** - Flake/module usage and service templates
- **[Configuration](docs/configuration.md)** - Environment variables and advanced options
- **[Authentication](docs/authentication.md)** - Basic Auth vs OAuth2/OIDC setup
- **[Running the Server](docs/running.md)** - Start, manage, troubleshoot

### Features

- **[App Documentation](docs/)** - Notes, Calendar, Contacts, WebDAV, Deck, Cookbook, Tables
- **[Document Processing](docs/configuration.md#document-processing)** - OCR/text extraction setup
- **[Semantic Search Architecture](docs/semantic-search-architecture.md)** - Vector search architecture
- **[Vector Sync UI Guide](docs/user-guide/vector-sync-ui.md)** - Browser UI for semantic sync and test

### Advanced Topics

- **[OAuth Architecture](docs/oauth-architecture.md)** - OAuth design and flows
- **[OAuth Quick Start](docs/quickstart-oauth.md)** - Fast OAuth bootstrap
- **[OAuth Setup Guide](docs/oauth-setup.md)** - Full OAuth configuration
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and fixes
- **[Comparison with Context Agent](docs/comparison-context-agent.md)** - Use-case comparison

## Contributing

- Report bugs or request features: [GitHub Issues](https://github.com/cbcoutinho/nextcloud-mcp-server/issues)
- Submit improvements: [Pull Requests](https://github.com/cbcoutinho/nextcloud-mcp-server/pulls)
- Development workflow notes: [AGENTS.md](AGENTS.md)

## Security

[![MseeP.ai Security Assessment](https://mseep.net/pr/cbcoutinho-nextcloud-mcp-server-badge.png)](https://mseep.ai/app/cbcoutinho-nextcloud-mcp-server)

- Use app passwords for Basic Auth deployments.
- Keep credential files out of git.
- Prefer least privilege and scoped credentials.
- Report security issues privately to maintainers.

## License

AGPL-3.0. See [LICENSE](./LICENSE).

## References

- [Model Context Protocol](https://github.com/modelcontextprotocol)
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)
- [Nextcloud](https://nextcloud.com/)
