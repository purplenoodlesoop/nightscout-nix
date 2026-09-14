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
