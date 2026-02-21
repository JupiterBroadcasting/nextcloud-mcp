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

  outputs = { self, nixpkgs, flake-utils, pyproject-nix, uv2nix, pyproject-build-systems }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Load workspace
        workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

        # Create overlay
        overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };

        # Construct Python set
        pythonSet = (pkgs.callPackage pyproject-nix.build.packages {
          python = pkgs.python312;
        }).overrideScope (
          nixpkgs.lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            (final: prev: {
              # Add any necessary overrides for tricky packages here
              # For example, if a package needs specific system libraries:
              # some-package = prev.some-package.overridePythonAttrs (old: {
              #   buildInputs = (old.buildInputs or []) ++ [ pkgs.some-lib ];
              # });
            })
          ]
        );

        # Build the application
        nextcloud-mcp-server-pkg = pythonSet.mkVirtualEnv "nextcloud-mcp-server-env" workspace.deps.default;
      in
      {
        packages.default = nextcloud-mcp-server-pkg;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            python312
            uv
            ruff
            ty
            podman
            nextcloud-mcp-server-pkg
          ];

          shellHook = ''
            echo "nextcloud-mcp-server dev shell ready"
            export UV_PYTHON=${pkgs.python312}/bin/python3
          '';
        };

        apps.default = {
          type = "app";
          program = "${nextcloud-mcp-server-pkg}/bin/nextcloud-mcp-server";
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
                # Required for DynamicUser state/cache paths if app expects them
                HOME = "/var/lib/nextcloud-mcp-server";
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
                    ${self.packages.${pkgs.system}.default}/bin/nextcloud-mcp-server run \
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
