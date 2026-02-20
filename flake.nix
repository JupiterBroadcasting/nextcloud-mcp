{
  description = "Nix development and NixOS module for nextcloud-mcp-server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            python311
            uv
            ruff
            ty
            podman
          ];

          shellHook = ''
            echo "nextcloud-mcp-server dev shell ready"
            echo "Run: uv sync --group dev"
          '';
        };

        apps.default = {
          type = "app";
          program = toString (pkgs.writeShellScript "run-nextcloud-mcp-server" ''
            set -euo pipefail
            exec ${pkgs.uv}/bin/uv run nextcloud-mcp-server run "$@"
          '');
        };
      }))
    //
    {
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.nextcloud-mcp-server;
        in
        {
          options.services.nextcloud-mcp-server = {
            enable = lib.mkEnableOption "Nextcloud MCP server";

            workingDirectory = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/nextcloud-mcp-server";
              description = "Working directory containing the nextcloud-mcp-server source tree.";
            };

            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Path to env file with NEXTCLOUD_* settings.";
            };

            host = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Host interface for the MCP HTTP server.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 8000;
              description = "Port for MCP HTTP transport.";
            };

            transport = lib.mkOption {
              type = lib.types.enum [ "streamable-http" "http" ];
              default = "streamable-http";
              description = "Transport mode passed to the server.";
            };

            metricsPort = lib.mkOption {
              type = lib.types.port;
              default = 9090;
              description = "Prometheus metrics port.";
            };

            extraEnvironment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Additional environment variables for the service.";
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.services.nextcloud-mcp-server = {
              description = "Nextcloud MCP Server";
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];

              environment = cfg.extraEnvironment // {
                TOKEN_STORAGE_DB = "/var/lib/nextcloud-mcp-server/tokens.db";
                METRICS_PORT = toString cfg.metricsPort;
              };

              serviceConfig =
                {
                  Type = "simple";
                  Restart = "always";
                  RestartSec = 5;
                  DynamicUser = true;
                  StateDirectory = "nextcloud-mcp-server";
                  WorkingDirectory = toString cfg.workingDirectory;
                  ExecStart = ''
                    ${pkgs.uv}/bin/uv run nextcloud-mcp-server run \
                      --transport ${cfg.transport} \
                      --host ${cfg.host} \
                      --port ${toString cfg.port}
                  '';
                  NoNewPrivileges = true;
                  PrivateTmp = true;
                  ProtectSystem = "strict";
                  ProtectHome = true;
                  ReadWritePaths = [ "/var/lib/nextcloud-mcp-server" ];
                }
                // lib.optionalAttrs (cfg.environmentFile != null) {
                  EnvironmentFile = cfg.environmentFile;
                };
            };
          };
        };
    };
}
