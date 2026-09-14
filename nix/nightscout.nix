{
  pkgs,
  nightscout-src,
  ...
}:
let
  nightscout = pkgs.callPackage ./package.nix { src = nightscout-src; };
in
{
  flake.packages = {
    inherit nightscout;
    default = nightscout;
  };
}
