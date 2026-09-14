{
  description = "Nightscout packaged as a Nix package and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Upstream source, pinned. Updating Nightscout is a bump of this input;
    # the version in nix/package.nix must be moved to match.
    nightscout-src = {
      url = "github:nightscout/cgm-remote-monitor/v15.0.8";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nightscout-src,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        nightscout = pkgs.callPackage ./nix/package.nix { src = nightscout-src; };
        default = nightscout;
      });

      overlays.default = _final: prev: {
        nightscout = prev.callPackage ./nix/package.nix { src = nightscout-src; };
      };

      nixosModules = rec {
        nightscout = import ./nix/module.nix;
        default = nightscout;
      };

      # Bumping Nightscout means moving the source pin, the version string and the
      # node_modules output hash together. Doing that by hand invites a silent
      # mismatch, so it is a declared operation instead.
      apps = forAllSystems (pkgs: {
        update = {
          type = "app";
          meta.description = "Re-pin Nightscout and refresh the node_modules hash";
          program = toString (
            pkgs.writeShellScript "update" ''
              set -euo pipefail
              cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"

              tag="''${1:-}"
              if [ -z "$tag" ]; then
                echo "usage: nix run .#update -- <tag>   (e.g. v15.0.9)" >&2
                exit 2
              fi

              echo "==> pinning nightscout-src to $tag"
              ${pkgs.nix}/bin/nix flake update nightscout-src \
                --override-input nightscout-src "github:nightscout/cgm-remote-monitor/$tag"

              echo "==> setting version to ''${tag#v}"
              ${pkgs.gnused}/bin/sed -i "s|^  version = \".*\";|  version = \"''${tag#v}\";|" nix/package.nix

              echo "==> invalidating the node_modules hash"
              ${pkgs.gnused}/bin/sed -i \
                "s|outputHash = \"sha256-.*\";|outputHash = \"${nixpkgs.lib.fakeHash}\";|" \
                nix/package.nix

              echo "==> building to discover the new hash"
              got=$(${pkgs.nix}/bin/nix build .#nightscout --no-link 2>&1 \
                | ${pkgs.gnugrep}/bin/grep -oE 'got: *sha256-[A-Za-z0-9+/=]+' \
                | ${pkgs.gnused}/bin/sed 's/got: *//' | head -1)

              if [ -z "$got" ]; then
                echo "could not determine the hash; build output above" >&2
                exit 1
              fi

              echo "==> node_modules hash: $got"
              ${pkgs.gnused}/bin/sed -i "s|outputHash = \"sha256-.*\";|outputHash = \"$got\";|" nix/package.nix

              echo "==> verifying"
              ${pkgs.nix}/bin/nix build .#nightscout --no-link
              echo "done - review the diff and commit"
            ''
          );
        };
      });
    };
}
