# `thc` command. THC's driver expects --thc-root to be a writable, built
# checkout: it rebuilds its GHC plugin and interface helper there with Cabal
# (--offline) before each project run. So materialize one per source revision
# under $THC_NIX_HOME, point build/install/thc at the Nix-built runtime, and
# build the Haskell side with the complete-Core GHC on first use (this first
# build fetches Hackage dependencies).
{ lib, stdenv, writeShellApplication, cabal-install, python3, git, gmp, pkg-config, zlib_1_2_11,
  thc-src, thc-runtime, ghc-thc }:

let
  llvm = thc-runtime.llvm;
  # The versioned names are what bin/toolchain.sh resolves `ghc` to; using the
  # same paths keeps Cabal from reconfiguring lib:thc on the first project run.
  ghc = "${ghc-thc}/bin/ghc-${ghc-thc.version}";
  ghcPkg = "${ghc-thc}/bin/ghc-pkg-${ghc-thc.version}";

  # Native package dependencies (pandoc's zlib, GMP). Outside stdenv, Nix's
  # cc/ld/pkg-config wrappers only read the target-salted variable names.
  nativeLibraries = [ gmp zlib_1_2_11 ];
  # One writable root per (THC source, compiler): dist-newstyle holds builds
  # made with that compiler.
  rootName = "${builtins.baseNameOf thc-src}-${builtins.substring 0 12 (builtins.baseNameOf ghc-thc)}";

  salt = lib.replaceStrings [ "-" ] [ "_" ] stdenv.hostPlatform.config;
  nativeLibraryEnv = {
    "NIX_LDFLAGS_${salt}" = lib.concatMapStringsSep " " (p: "-L${lib.getLib p}/lib") nativeLibraries;
    "NIX_CFLAGS_COMPILE_${salt}" = lib.concatMapStringsSep " " (p: "-isystem ${lib.getDev p}/include") nativeLibraries;
    "PKG_CONFIG_PATH_${salt}" = lib.makeSearchPathOutput "dev" "lib/pkgconfig" nativeLibraries;
    # GHC's loader (Template Haskell) and Sulong dlopen package libraries by name.
    LD_LIBRARY_PATH = lib.makeLibraryPath nativeLibraries;
  };
in
writeShellApplication {
  name = "thc";
  runtimeInputs = [ ghc-thc cabal-install python3 git llvm.clang llvm.llvm pkg-config thc-runtime.jdk ];
  runtimeEnv = {
    JAVA_HOME = "${thc-runtime.jdk}";
    THC_CLANG = "${llvm.clang}/bin/clang";
    # The driver otherwise looks for llvm-objcopy beside clang, but nixpkgs'
    # clang-wrapper and LLVM tools are separate packages.
    THC_LLVM_OBJCOPY = "${llvm.llvm}/bin/llvm-objcopy";
    THC_LLVM_LINK = "${llvm.llvm}/bin/llvm-link";
    THC_LLVM_NM = "${llvm.llvm}/bin/llvm-nm";
    THC_LLVM_OPT = "${llvm.llvm}/bin/opt";
    THC_LLVM_DIS = "${llvm.llvm}/bin/llvm-dis";
    GHC = ghc;
    GHC_PKG = ghcPkg;
    THC_GHC_SOURCE = "${ghc-thc.tree}";
  } // nativeLibraryEnv;
  text = ''
    home=''${THC_NIX_HOME:-''${XDG_CACHE_HOME:-$HOME/.cache}/thc-nix}
    root=$home/${rootName}
    if [ ! -e "$root/.thc-nix-ready" ]; then
      rm -rf "$root"
      mkdir -p "$home"
      cp -r ${thc-src} "$root"
      chmod -R u+w "$root"
      mkdir -p "$root/build/install"
      ln -s ${thc-runtime} "$root/build/install/thc"
      (
        cd "$root"
        cabal update >&2
        cabal build exe:thc exe:thc-interface lib:thc \
          --with-compiler=${ghc} --with-hc-pkg=${ghcPkg} >&2
      )
      touch "$root/.thc-nix-ready"
    fi
    # The runtime can change without the source or compiler changing.
    ln -sfn ${thc-runtime} "$root/build/install/thc"
    driver=$(cd "$root" && cabal list-bin exe:thc --offline --with-compiler=${ghc} --with-hc-pkg=${ghcPkg})

    if [ "$#" -gt 0 ] && { [ "$1" = run ] || [ "$1" = acquire ]; }; then
      command=$1; shift
      extra=(--thc-root "$root")
      want_source=0; has_source=0; previous=
      for arg in "$@"; do
        [ "$arg" = -- ] && break
        [ "$previous" = --installed-core ] && [ "$arg" = required ] && want_source=1
        [ "$arg" = --installed-core=required ] && want_source=1
        case $arg in --ghc-source|--ghc-source=*) has_source=1 ;; esac
        previous=$arg
      done
      if [ "$want_source" = 1 ] && [ "$has_source" = 0 ]; then
        extra+=(--ghc-source "$THC_GHC_SOURCE")
      fi
      exec "$driver" "$command" "''${extra[@]}" "$@"
    fi
    exec "$driver" "$@"
  '';
  meta = {
    description = "THC driver: run Cabal components on Truffle/Graal";
    platforms = [ "x86_64-linux" ];
  };
}
