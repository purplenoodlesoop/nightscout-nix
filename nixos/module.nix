{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;

  cfg = config.services.nightscout;
in
{
  options.services.nightscout = {
    enable = mkEnableOption "Nightscout CGM remote monitor";

    package = mkOption {
      type = types.package;
      description = "Nightscout package to run.";
    };

    port = mkOption {
      type = types.port;
      default = 1337;
      description = ''
        Port Nightscout listens on. Bound to the loopback interface only; put a
        reverse proxy in front of it. Opening this port to the network is the
        host configuration's decision, not this module's.
      '';
    };

    environmentFile = mkOption {
      type = types.path;
      description = ''
        Path to an EnvironmentFile holding the values that must not reach the Nix
        store, delivered out of band: at minimum `API_SECRET` and
        `MONGO_CONNECTION`. Anything set through `settings` instead is
        world-readable in the store.
      '';
    };

    settings = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Non-secret Nightscout environment variables. These end up in the Nix
        store, so never put credentials here — use `environmentFile`.
      '';
      example = {
        DISPLAY_UNITS = "mmol";
        AUTH_DEFAULT_ROLES = "denied";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.nightscout = {
      description = "Nightscout CGM remote monitor";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        PORT = toString cfg.port;
        # Nightscout sits behind a TLS-terminating proxy, so it serves plain HTTP
        # itself and must not redirect to HTTPS on its own.
        INSECURE_USE_HTTP = "true";
      }
      // cfg.settings;

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        RestartSec = 5;

        EnvironmentFile = cfg.environmentFile;

        DynamicUser = true;
        StateDirectory = "nightscout";

        # Hardening. Nightscout is a network service handling personal health
        # data; it needs no access to the host beyond its own state.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        NoNewPrivileges = true;
        MemoryDenyWriteExecute = false; # V8 JITs, so W^X cannot be enforced.
        SystemCallArchitectures = "native";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };

    assertions = [
      {
        assertion = !(cfg.settings ? API_SECRET) && !(cfg.settings ? MONGO_CONNECTION);
        message = ''
          services.nightscout.settings must not contain API_SECRET or
          MONGO_CONNECTION: everything in `settings` is world-readable in the Nix
          store. Put them in `environmentFile` instead.
        '';
      }
    ];
  };
}
