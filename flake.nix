{
  description = "Meshstellar - A Meshtastic MQTT client and web interface";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let
          protobufs = pkgs.fetchgit {
            url = "https://github.com/meshtastic/protobufs.git";
            rev = "4c4427c4a73c86fed7dc8632188bb8be95349d81";
            hash = "sha256-t4LmJI4+sPD6t4gfNy0gqVnehpvim0rbqVARcMCpgAQ=";
          };
        in {
        default = pkgs.rustPlatform.buildRustPackage {
          pname = "meshstellar";
          version = "0.1.0";
          src = pkgs.lib.cleanSource ./.;
          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = [ pkgs.protobuf pkgs.git pkgs.sqlx-cli ];

          postUnpack = ''
            rm -rf $sourceRoot/protobufs
            cp -r ${protobufs} $sourceRoot/protobufs
          '';

          preBuild = ''
            export DATABASE_URL="sqlite:$TMPDIR/meshstellar.db?mode=rwc"
            sqlx database create
            sqlx migrate run
            cargo sqlx prepare
          '';

          env = {
            PROTOC = "${pkgs.protobuf}/bin/protoc";
            SQLX_OFFLINE = "true";
          };
        };
      });

      devShells = forAllSystems (pkgs:
          let
            protobufs = pkgs.fetchgit {
              url = "https://github.com/meshtastic/protobufs.git";
              rev = "4c4427c4a73c86fed7dc8632188bb8be95349d81";
              hash = "sha256-t4LmJI4+sPD6t4gfNy0gqVnehpvim0rbqVARcMCpgAQ=";
            };
          in {
            default = pkgs.mkShell {
              buildInputs = [
                pkgs.cargo
                pkgs.rustc
                pkgs.protobuf
                pkgs.sqlx-cli
              ];

              PROTOC = "${pkgs.protobuf}/bin/protoc";
              SQLX_OFFLINE = "true";

              shellHook = ''
                # ensure expected path exists for build.rs
                if [ ! -d ./protobufs ] || [ -L ./protobufs ]; then
                  rm -rf ./protobufs
                  cp -r ${protobufs} ./protobufs
                  chmod -R u+w ./protobufs
                fi
                export DATABASE_URL="sqlite:$TMPDIR/meshstellar.db?mode=rwc"
                sqlx database create
                sqlx migrate run
                cargo sqlx prepare
              '';
            };
          });
    } // {
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.meshstellar;
          settingsFormat = pkgs.formats.toml {};
          configFile = settingsFormat.generate "meshstellar.toml" cfg.settings;
        in {
          options.services.meshstellar = {
            enable = lib.mkEnableOption "Meshstellar Meshtastic web interface";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.default;
              description = "The meshstellar package to use";
            };

            settings = lib.mkOption {
              type = lib.types.submodule {
                freeformType = settingsFormat.type;

                options = {
                  http_addr = lib.mkOption {
                    type = lib.types.str;
                    default = "127.0.0.1:3000";
                    description = "HTTP server address and port";
                  };

                  mqtt_auth = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Enable MQTT authentication";
                  };

                  mqtt_username = lib.mkOption {
                    type = lib.types.str;
                    default = "username";
                    description = "MQTT username";
                  };

                  mqtt_password = lib.mkOption {
                    type = lib.types.str;
                    default = "password";
                    description = "MQTT password. Warning: visible in nix store. Prefer using a secrets manager.";
                  };

                  mqtt_host = lib.mkOption {
                    type = lib.types.str;
                    default = "127.0.0.1";
                    description = "MQTT broker host";
                  };

                  mqtt_port = lib.mkOption {
                    type = lib.types.port;
                    default = 1883;
                    description = "MQTT broker port";
                  };

                  mqtt_keep_alive = lib.mkOption {
                    type = lib.types.int;
                    default = 15;
                    description = "MQTT keep-alive interval in seconds";
                  };

                  mqtt_client_id = lib.mkOption {
                    type = lib.types.str;
                    default = "meshstellar";
                    description = "MQTT client ID";
                  };

                  mqtt_topic = lib.mkOption {
                    type = lib.types.str;
                    default = "meshtastic/#";
                    description = "MQTT topic to subscribe to";
                  };

                  database_url = lib.mkOption {
                    type = lib.types.str;
                    default = "sqlite:///var/lib/meshstellar/meshstellar.db?mode=rwc";
                    description = "SQLite database URL";
                  };

                  map_glyphs_url = lib.mkOption {
                    type = lib.types.str;
                    default = "https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf";
                    description = "URL for map font glyphs";
                  };

                  open_browser = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Open browser on startup";
                  };

                  hide_private_messages = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Hide private messages from the interface";
                  };
                };
              };
              default = {};
              description = "Meshstellar configuration options. See meshstellar.toml.example for reference.";
            };

            dataDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/meshstellar";
              description = "Directory to store database and data files";
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "meshstellar";
              description = "User to run the service as";
            };

            group = lib.mkOption {
              type = lib.types.str;
              default = "meshstellar";
              description = "Group to run the service as";
            };

            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Environment file to pass secrets to the service.
                Variables with MESHSTELLAR_ prefix override config settings.
                Example: MESHSTELLAR_MQTT_PASSWORD=secret
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            users.users.${cfg.user} = {
              isSystemUser = true;
              group = cfg.group;
              home = cfg.dataDir;
              createHome = true;
            };

            users.groups.${cfg.group} = {};

            # Place config in /etc/meshstellar/meshstellar.toml
            environment.etc."meshstellar/meshstellar.toml".source = configFile;

            systemd.services.meshstellar = {
              description = "Meshstellar Meshtastic Web Interface";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              restartTriggers = [ configFile ] ++ lib.optional (cfg.environmentFile != null) cfg.environmentFile;

              serviceConfig = {
                Type = "simple";
                User = cfg.user;
                Group = cfg.group;
                WorkingDirectory = cfg.dataDir;
                ExecStart = "${cfg.package}/bin/meshstellar";
                Restart = "always";
                RestartSec = 5;

                # Hardening
                NoNewPrivileges = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                ReadWritePaths = [ cfg.dataDir ];
              } // lib.optionalAttrs (cfg.environmentFile != null) {
                EnvironmentFile = cfg.environmentFile;
              };
            };
          };
        };
    };
}
