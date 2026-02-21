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
    let
      lib = nixpkgs.lib;
    in
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
      nixosModules.default =
        let
          flakeSelf = self;
        in
        { config, lib, pkgs, ... }:
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
                default = flakeSelf.outPath;
                description = "Path to the source directory.";
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

              environment = cfg.extraEnvironment // {
                # Core: Use nixpkgs Python, allow caching in StateDirectory
                UV_SYSTEM_PYTHON = "1";
                UV_NO_MANAGED_PYTHON = "1";
                UV_PYTHON = "${pkgs.python312}/bin/python3";
                UV_CACHE_DIR = "/var/lib/nextcloud-mcp-server/uv-cache";
                UV_LINK_MODE = "copy"; # Avoid hardlink issues in sandbox

                # Required for module discovery and persistent venv
                PYTHONPATH = cfg.workingDirectory;
                UV_PROJECT_ENVIRONMENT = "/var/lib/nextcloud-mcp-server/venv";

                # Required when DynamicUser - HOME not set automatically
                HOME = "/var/lib/nextcloud-mcp-server";

                # XDG directories for uv data (inside StateDirectory)
                XDG_CACHE_HOME = "/var/lib/nextcloud-mcp-server/cache";
                XDG_DATA_HOME = "/var/lib/nextcloud-mcp-server/data";

                # App-specific settings
                TOKEN_STORAGE_DB = "/var/lib/nextcloud-mcp-server/tokens.db";
                METRICS_PORT = toString cfg.metricsPort;

                # Fix missing C++ standard library for grpcio/opentelemetry
                LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc pkgs.zlib ];
              };

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
                      --cache-dir /var/lib/nextcloud-mcp-server/uv-cache \
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
