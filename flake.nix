{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    core-flake = {
      url = "github:purplenoodlesoop/core-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Upstream source, pinned. Bump with `nix run .#update -- <tag>`, which moves
    # this, the version string and the node_modules hash together.
    nightscout-src = {
      url = "github:nightscout/cgm-remote-monitor/v15.0.8";
      flake = false;
    };
  };

  outputs =
    { core-flake, nightscout-src, ... }:
    with core-flake;
    lib.evalFlake {
      specialArgs = { inherit nightscout-src; };

      # mongodb-ce is SSPL, which nixpkgs treats as unfree. Allowed by name for
      # this flake's package set only — never a blanket allowUnfree.
      config.allowUnfreePredicate = pkg: builtins.elem (pkg.pname or "") [ "mongodb-ce" ];

      perSystem.imports = with nixosModules; [
        tasks
        ./nix/checks.nix
        ./nix/mongodb.nix
        ./nix/nightscout.nix
        ./nix/tasks.nix
      ];

      topLevel.nixosModules = rec {
        nightscout = import ./nixos/module.nix;
        default = nightscout;
      };
    };
}
