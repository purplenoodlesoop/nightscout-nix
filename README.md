# nightscout-nix

Nightscout packaged as a Nix package and a NixOS module. Upstream source is a
pinned flake input, so this repository carries no vendored application code.

## Use

```nix
{
  inputs.nightscout-nix.url = "github:purplenoodlesoop/nightscout-nix";

  # in the host configuration
  imports = [ inputs.nightscout-nix.nixosModules.default ];

  services.nightscout = {
    enable = true;
    package = inputs.nightscout-nix.packages.${system}.nightscout;
    environmentFile = "/run/secrets/nightscout.env";
    settings = {
      DISPLAY_UNITS = "mmol";
      AUTH_DEFAULT_ROLES = "denied";
    };
  };
}
```

To let this flake run the database too:

```nix
services.nightscout.database = {
  enable = true;
  package = inputs.nightscout-nix.packages.${system}.mongodb;
};
```

`API_SECRET` and `MONGO_CONNECTION` belong in `environmentFile`, never in
`settings`: everything in `settings` is world-readable in the Nix store. The
module asserts on this rather than trusting the reader to remember.

The service listens on loopback. Exposing it is the host configuration's job.

## Updating

```sh
nix run .#update -- v15.0.9
```

This re-pins the source, moves the version string and refreshes the
`node_modules` output hash together. Doing those by hand invites a silent
mismatch between the pin and the hash.

## Why this is not buildNpmPackage

It cannot be. Nightscout cannot be installed offline from its lockfile, and no
combination of flags changes that:

- Upstream declares **targeted npm `overrides`** — keys like `ajv@^6.0.0`, which
  mean "override this differently depending on which range the dependent asked
  for". npm can only apply those by walking the dependency graph, so `npm ci`
  always calls `buildIdealTree` and fetches *packuments* (version metadata).
  Packuments are never prefetched, so the install fails offline however complete
  the tarball cache is.
- Deleting the overrides does not help. The lockfile then pins versions that
  violate the declared ranges — `@parse/node-apn` wants `node-forge@1.3.1` where
  the override forced `1.4.0` — so npm re-resolves for the opposite reason.
- Upstream's lockfile is separately unusable: it carries `resolved` URLs on 14 of
  its 1029 entries, and the Nix prefetcher can only cache entries that have one.
  (`v15.0.6` was the last release with a healthy lockfile; it regressed in
  `v15.0.7`.)

So dependency resolution happens once, in a fixed-output derivation with network
access, pinned by hash exactly like a source tarball. npm behaves normally, which
means upstream's overrides apply as intended and their lockfile is used
unmodified — no vendored lockfile, no version drift from what upstream tested.

The trade: that derivation is pinned by output hash rather than by a lockfile the
sandbox can verify. A changed dependency surfaces as a hash mismatch rather than
being prevented outright. The hash is reproducible — deleting the output and
rebuilding yields the same one.

## Two traps in the derivation

- The `node_modules` derivation sets `dontFixup`. stdenv's `patchShebangs` would
  rewrite `#!/usr/bin/env node` into an absolute store path, and a fixed-output
  derivation may not reference the store at all.
- Because of that, the consumer must run `patchShebangs node_modules` itself
  *before* invoking anything from `.bin`. stdenv's own pass happens in
  `fixupPhase`, long after the build phase that needs it.

## Why the database is packaged here

Nightscout pins the node driver at `^5.9.2`, and MongoDB supports that driver
only against servers **7.0 or older**. That constraint belongs to Nightscout, not
to whatever host happens to run it, so the matching server is exposed here as
`packages.<system>.mongodb`.

nixpkgs ships `mongodb-ce` 8.2, which is an unsupported pairing with that driver.
`pkgs.mongodb` is 7.0 but unfree, so Hydra does not cache it and it builds from
source — hours of `scons` on a small host, for a package upstream already ships
as a binary.

So `nix/mongodb.nix` keeps `mongodb-ce`'s packaging — official tarball, unpacked
and relinked by `autoPatchelfHook`, nothing compiled — and swaps the tarball for
7.0.40. If a future version needed a library the packaging does not list,
`autoPatchelfHook` fails the build by name rather than producing a `mongod` that
dies at runtime.

Verified end to end rather than by `--version`: Nightscout's own driver connects
to this server, inserts, reads back, and builds an index.

Bumping MongoDB means editing the version and the hash together in
`nix/mongodb.nix`.

## License

MIT — see [LICENSE](LICENSE). This covers the packaging in this repository only.

Nightscout itself is **AGPL-3.0** and is not vendored here: it is a pinned
flake input, fetched from upstream at build time. `nix/package.nix` records
`agpl3Only` as the licence of the package it builds, which is Nightscout's,
not this repository's.

