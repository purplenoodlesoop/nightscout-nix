{
  lib,
  stdenv,
  nodejs_22,
  cacert,
  makeWrapper,
  src,
}:

let
  version = "15.0.8";

  # Nightscout cannot be installed offline from its lockfile. Upstream declares
  # targeted npm `overrides` (keys like "ajv@^6.0.0"), which npm can only apply by
  # walking the dependency graph, so `npm ci` always builds an ideal tree and
  # fetches packuments -- version metadata that is never prefetched. Removing the
  # overrides does not help either: the lockfile then pins versions that violate
  # the declared ranges (@parse/node-apn wants node-forge 1.3.1 where the override
  # forced 1.4.0), so npm re-resolves for the opposite reason.
  #
  # So dependency resolution happens once, here, in a fixed-output derivation with
  # network access, pinned by hash exactly like a source tarball. npm behaves
  # normally, which means upstream's overrides apply as intended and their own
  # lockfile is used unmodified.
  #
  # Refresh the hash with `nix run .#update` whenever the source pin moves.
  nodeModules = stdenv.mkDerivation {
    pname = "nightscout-node-modules";
    inherit version src;

    nativeBuildInputs = [
      nodejs_22
      cacert
    ];

    dontConfigure = true;

    # stdenv's fixupPhase runs patchShebangs, which rewrites `#!/usr/bin/env node`
    # into an absolute /nix/store path. A fixed-output derivation may not
    # reference the store at all, so fixup has to stay off here. The consumer
    # patches the shebangs itself, before running anything from .bin.
    dontFixup = true;

    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      # Scripts are skipped here: the client bundle is built in the main
      # derivation, and postinstall generates a random string that would make
      # this output unreproducible.
      npm ci --ignore-scripts --no-audit --no-fund --loglevel=error
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r node_modules "$out/"
      runHook postInstall
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-nTGQWO37MOEaI3fQMvZuDynFjh37BZcGT7QX1IFVNXA=";
  };
in

stdenv.mkDerivation {
  pname = "nightscout";
  inherit version src;

  nativeBuildInputs = [
    nodejs_22
    makeWrapper
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    cp -r ${nodeModules}/node_modules .
    chmod -R u+w node_modules

    # The node_modules FOD could not have its shebangs patched (a fixed-output
    # derivation may not reference the store), so the .bin entries still say
    # `#!/usr/bin/env node` and /usr/bin/env does not exist in the sandbox. Patch
    # them here, before anything tries to run webpack -- stdenv's own
    # patchShebangs only runs in fixupPhase, which is far too late.
    patchShebangs node_modules

    # What upstream's postinstall would have run: webpack, then the cache key.
    npm run bundle
    runHook postBuild
  '';

  # The server resolves views, static assets and the generated bundle relative to
  # the working directory, so the whole tree ships and the wrapper chdirs into it.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/nightscout"
    cp -r . "$out/lib/nightscout"

    makeWrapper ${nodejs_22}/bin/node "$out/bin/nightscout" \
      --add-flags "$out/lib/nightscout/lib/server/server.js" \
      --chdir "$out/lib/nightscout"

    runHook postInstall
  '';

  meta = {
    description = "Web-based CGM remote monitor";
    homepage = "https://github.com/nightscout/cgm-remote-monitor";
    license = lib.licenses.agpl3Only;
    mainProgram = "nightscout";
    # Pure Node with no native dependencies, so nothing here is Linux-specific.
    platforms = lib.platforms.unix;
  };
}
