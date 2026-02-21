{
  description = "Nix development and NixOS module for nextcloud-mcp-server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            python312
            uv
            ruff
            ty
            podman
          ];

          shellHook = ''
            echo "nextcloud-mcp-server dev shell ready"
            export UV_PYTHON=${pkgs.python312}/bin/python3
          '';
        };

        apps.default = {
          type = "app";
          program = toString (pkgs.writeShellScript "run-nextcloud-mcp-server" ''
            set -euo pipefail
            exec ${pkgs.uv}/bin/uv run nextcloud-mcp-server run "$@"
          '');
        };

        packages.default = pkgs.writeShellScriptBin "nextcloud-mcp-server" ''
          exec ${pkgs.uv}/bin/uv run nextcloud-mcp-server run "$@"
        '';
      }))
    //
    {
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.nextcloud-mcp-server;
        in
        {
            options.services.nextcloud-mcp-server = {
              enable = lib.mkEnableOption "Nextcloud MCP Server";
              user = lib.mkOption {
                type = lib.types.str;
                default = "nextcloud-mcp-server";
                description = "User account under which the service runs.";
              };
              group = lib.mkOption {
                type = lib.types.str;
                default = "nextcloud-mcp-server";
                description = "Group under which the service runs.";
              };
              workingDirectory = lib.mkOption {
                type = lib.types.path;
                default = "/var/lib/nextcloud-mcp-server";
                description = "Path to the cloned repository or source directory.";
              };
              environmentFile = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "File containing environment variables for the service.";
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
            users.users = lib.optionalAttrs (cfg.user == "nextcloud-mcp-server") {
              nextcloud-mcp-server = {
                group = cfg.group;
                isSystemUser = true;
              };
            };
            users.groups = lib.optionalAttrs (cfg.group == "nextcloud-mcp-server") {
              nextcloud-mcp-server = { };
            };

            systemd.services.nextcloud-mcp-server = {
              description = "Nextcloud MCP Server";
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];

              preStart = ''
                # Ensure the state directory exists and is owned by the service user
                ${pkgs.coreutils}/bin/mkdir -p /var/lib/nextcloud-mcp-server
                ${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} /var/lib/nextcloud-mcp-server
              '';

              serviceConfig =
                {
                  Type = "simple";
                  Restart = "always";
                  RestartSec = 5;
                  User = cfg.user;
                  Group = cfg.group;
                  PermissionsStartOnly = true; # Allow preStart to run as root for chown
                  StateDirectory = "nextcloud-mcp-server";
                  WorkingDirectory = toString cfg.workingDirectory;

                  ExecStart = ''
                    ${pkgs.uv}/bin/uv run \
                      --project ${cfg.workingDirectory} \
                      --python ${pkgs.python312}/bin/python3 \
                      python -m nextcloud_mcp_server.cli run \
                      --transport ${cfg.transport} \
                      --host ${cfg.host} \
                      --port ${toString cfg.port}
                  '';
                }
                // lib.optionalAttrs (cfg.environmentFile != null) {
                  EnvironmentFile = cfg.environmentFile;
                };

              path = with pkgs; [
                git
                gcc
                gnumake
                binutils
                stdenv.cc.libc
              ];
            };
          };
        };
    };
}
