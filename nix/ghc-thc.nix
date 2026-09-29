# GHC 9.14.1 as THC wants it: every Haskell library interface carries complete
# Core (-fwrite-if-simplified-core), and a pruned copy of the configured Hadrian
# build tree is kept in the `tree` output for `thc run --ghc-source`.
{ lib, haskell, removeReferencesTo }:

let
  base = haskell.compiler.ghc9141;
  ghcSrc = base.src;

  # THC's driver reads Hadrian's setup-config files with its own Cabal (3.16.*),
  # and Cabal refuses a setup-config written by any other Cabal version. GHC
  # 9.14.1 ships Cabal 3.16.0.0, so build Hadrian against that in-tree copy
  # instead of the boot package set's Cabal.
  # nixpkgs pins Hadrian >= 9.11 to the boot set's Cabal 3.14, so override
  # Hadrian directly.
  fromTree = dir: drv: haskell.lib.compose.overrideCabal (_: {
    version = "3.16.0.0";
    src = "${ghcSrc}/libraries/Cabal/${dir}";
    revision = null;
    editedCabalFile = null;
  }) drv;
  cabalSyntax = fromTree "Cabal-syntax" base.bootPkgs.Cabal-syntax_3_16_1_0;
  cabal = fromTree "Cabal" (base.bootPkgs.Cabal_3_16_1_0.override { Cabal-syntax = cabalSyntax; });
  hadrian = base.passthru.hadrian.override { Cabal = cabal; };

  bootGhc = base.bootPkgs.ghc;
in
(base.override {
  inherit hadrian;
  # THC only loads vanilla/dynamic interfaces; skip the profiled way and Sphinx.
  enableProfiledLibs = false;
  enableDocs = false;
  # THC's runtime reimplements the RTS's unavailable-DWARF profile and rejects
  # a GHC configured with USE_LIBDW=1 (nixpkgs' default on x86_64).
  enableDwarf = false;
  # THC's recipe builds `perf`. nixpkgs' `release` is perf plus
  # -fno-write-if-self-recomp, but --ghc-source validation needs the retained
  # source hashes and CPP usage files.
  ghcFlavour = "perf+no_profiled_libs+split_sections";
}).overrideAttrs (old: {
  pname = "ghc-thc";
  outputs = old.outputs ++ [ "tree" ];

  # Like upstream's recipe: unhashed unit ids (THC expects e.g.
  # ghc-9.14.1-inplace for the compiler unit).
  hadrianFlags = lib.remove "--hash-unit-ids" old.hadrianFlags
    ++ [
      "*.*.ghc.hs.opts += -fwrite-if-simplified-core"
      # THC links the C objects of installed libraries (e.g. ghc-internal's
      # gmp_wrappers.o) out of their static archives into shared objects for
      # Sulong. GHC compiles static-way C with -fno-PIC (#15847), so ask for PIC.
      "*.*.ghc.c.opts += -fPIC"
      "*.*.ghc.cpp.opts += -fPIC"
    ];

  # THC checks that ghc-internal's configured include-dirs are exactly
  # ["include"]; the cc-wrapper already finds gmp.h without the extra path.
  configureFlags = lib.filter (f: !lib.hasPrefix "--with-gmp-includes=" f) old.configureFlags;

  nativeBuildInputs = old.nativeBuildInputs ++ [ removeReferencesTo ];

  # Build inside the `tree` output so the paths recorded in each setup-config
  # are the paths THC later canonicalizes and compares against.
  postUnpack = (old.postUnpack or "") + ''
    cp -a "$sourceRoot" "$tree"
    chmod -R u+w "$tree"
    sourceRoot="$tree"
  '';

  postInstall = old.postInstall + ''
    # Keep configuration, sources and interfaces; drop objects and tools.
    pushd "$tree" >/dev/null
    rm -rf _build/stage0 _build/stageBoot _build/bindist _build/docs _build/doc \
      _build/stage1/bin _build/.shake.database _build/.shake.lock
    find _build -type f \( -name '*.o' -o -name '*.dyn_o' -o -name '*.p_o' -o -name '*.o-boot' \
      -o -name '*.dyn_o-boot' -o -name '*.a' -o -name '*.so' -o -name '*.so.*' \) -delete
    # The stage1 lib dir symlinks the RTS libraries just deleted.
    find . -xtype l -delete
    find . -type l -lname '${bootGhc}*' -delete
    # Installed interfaces name CPP usage files in this tree (THC validates
    # them), so out -> tree is real; keep tree -> out/doc from closing a cycle.
    find . -type f -print0 | xargs -0 -r remove-references-to -t ${bootGhc} -t "$out" -t "$doc"
    popd >/dev/null
  '';

  passthru = old.passthru // { thcCompleteCore = true; };
})
