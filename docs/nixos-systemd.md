# NixOS and systemd

This repository includes:

- `flake.nix` with:
  - a `devShell` (`nix develop`)
  - a runnable app (`nix run`)
  - a NixOS module (`nixosModules.default`)
- `tools/nextcloud-mcp-server.service` as a generic systemd template

## NixOS module example

In your system flake:

```nix
{
  inputs.nextcloud-mcp-server.url = "github:YOUR_ORG/nextcloud-mcp-server";

  outputs = { self, nixpkgs, nextcloud-mcp-server, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nextcloud-mcp-server.nixosModules.default
        ({ ... }: {
          services.nextcloud-mcp-server = {
            enable = true;
            workingDirectory = "/srv/nextcloud-mcp-server";
            environmentFile = "/etc/nextcloud-mcp-server.env";
            host = "127.0.0.1";
            port = 8000;
            transport = "streamable-http";
            metricsPort = 9090;
          };
        })
      ];
    };
  };
}
```

## Environment file

Create `/etc/nextcloud-mcp-server.env`:

```bash
NEXTCLOUD_HOST=https://cloud.example.com
NEXTCLOUD_USERNAME=your_username
NEXTCLOUD_PASSWORD=your_app_password
```

Optional:

```bash
TOKEN_ENCRYPTION_KEY=your_fernet_key
METRICS_PORT=9090
```

## Generic systemd template (non-NixOS)

Use `tools/nextcloud-mcp-server.service` as a starting point for Debian/Ubuntu/Fedora style systemd deployments.
