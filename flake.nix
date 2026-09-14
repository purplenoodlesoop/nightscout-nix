{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    core-flake = {
      url = "git+ssh://git@github.com/purplenoodlesoop/core-flake";
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

      perSystem.imports = with nixosModules; [
        tasks
        ./nix/checks.nix
        ./nix/nightscout.nix
        ./nix/tasks.nix
      ];

      topLevel.nixosModules = rec {
        nightscout = import ./nixos/module.nix;
        default = nightscout;
      };
    };
}
