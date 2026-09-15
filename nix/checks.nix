{
  pkgs,
  config,
  ...
}:
{
  flake.output.checks = {
    # Building the package is itself the test: it compiles the client bundle and
    # fails if the pinned dependency set no longer produces a working tree.
    inherit (config.flake.packages) nightscout mongodb;

    # Written out rather than globbed: a glob over a store path would silently
    # stop covering files that were added but not copied into the derivation.
    fmt = pkgs.runCommandLocal "nightscout-nix-fmt-check" { } ''
      ${pkgs.nixfmt}/bin/nixfmt --check \
        ${../flake.nix} \
        ${../nix/checks.nix} \
        ${../nix/mongodb.nix} \
        ${../nix/nightscout.nix} \
        ${../nix/package.nix} \
        ${../nix/tasks.nix} \
        ${../nixos/module.nix}
      touch $out
    '';
  };
}
