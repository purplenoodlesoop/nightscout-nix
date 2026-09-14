{
  pkgs,
  ...
}:
{
  tasks = {
    update = {
      description = "Re-pin Nightscout to a tag and refresh the node_modules hash";
      body = ''
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
        ${pkgs.gnused}/bin/sed -i \
          "s|^  version = \".*\";|  version = \"''${tag#v}\";|" nix/package.nix

        # A stale hash would silently build the previous dependency set, so it is
        # invalidated before the discovery build rather than after.
        echo "==> invalidating the node_modules hash"
        ${pkgs.gnused}/bin/sed -i \
          "s|outputHash = \"sha256-.*\";|outputHash = \"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\";|" \
          nix/package.nix

        echo "==> building once to discover the hash"
        got=$(${pkgs.nix}/bin/nix build .#nightscout --no-link 2>&1 \
          | ${pkgs.gnugrep}/bin/grep -oE 'got: *sha256-[A-Za-z0-9+/=]+' \
          | ${pkgs.gnused}/bin/sed 's/got: *//' | head -1)

        if [ -z "$got" ]; then
          echo "could not determine the hash from the build output" >&2
          exit 1
        fi

        echo "==> node_modules hash: $got"
        ${pkgs.gnused}/bin/sed -i "s|outputHash = \"sha256-.*\";|outputHash = \"$got\";|" nix/package.nix

        echo "==> verifying the build"
        ${pkgs.nix}/bin/nix build .#nightscout --no-link
        echo "done - review the diff and commit"
      '';
    };

    fmt = {
      description = "Format every Nix file in the tree";
      body = ''
        set -euo pipefail
        cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
        ${pkgs.nixfmt}/bin/nixfmt flake.nix nix/*.nix nixos/*.nix
      '';
    };

    fmt-check = {
      description = "Fail if any Nix file is unformatted";
      body = ''
        set -euo pipefail
        cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
        ${pkgs.nixfmt}/bin/nixfmt --check flake.nix nix/*.nix nixos/*.nix
      '';
    };
  };
}
