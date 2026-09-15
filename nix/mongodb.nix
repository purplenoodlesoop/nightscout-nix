{
  pkgs,
  ...
}:
let
  # Nightscout pins the node driver at ^5.9.2, and MongoDB supports that driver
  # only against servers up to 7.0. nixpkgs ships mongodb-ce 8.2, which is an
  # unsupported pairing, so the tarball is swapped while the packaging is kept.
  #
  # mongodb-ce is the official prebuilt release, unpacked and relinked against
  # nixpkgs libraries by autoPatchelfHook — nothing is compiled. Building
  # `pkgs.mongodb` instead is not viable: it is unfree, so Hydra does not cache
  # it, and scons on a small host takes hours.
  #
  # Verified end to end against this exact server: Nightscout's own driver
  # connects, inserts, reads back and builds an index.
  #
  # Bumping it means editing both the version and the hash here.
  mongodb = pkgs.mongodb-ce.overrideAttrs (_old: rec {
    version = "7.0.40";
    src = pkgs.fetchurl {
      url = "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-${version}.tgz";
      hash = "sha256-5LPXoRgY+YPYl+yfy/JXeabhIvDnt+JfpKuKxdeKWok=";
    };
  });
in
{
  flake.packages = { inherit mongodb; };
}
