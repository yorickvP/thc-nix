# THC's Truffle runtime (`./gradlew installDist`), i.e. what a checkout has in
# build/install/thc after `make runtime`.
{ lib, stdenv, makeWrapper, gradle_9, graalvmPackages, python3, git, llvmPackages_19, gmp, thc-src, ghc-thc }:

let
  jdk = graalvmPackages.graalvm-ce;
  gradle = gradle_9.override { java = jdk; };
  # Upstream CI installs LLVM 18, but the driver's package-native step runs
  # `opt -passes=pre-isel-intrinsic-lowering,...`, which LLVM 18's new pass
  # manager doesn't register (19+ does). Sulong 25.3.4.1 itself is built with
  # clang 22, so 19's bitcode is well within what it reads.
  llvm = llvmPackages_19;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "thc-runtime";
  version = "0-unstable-2026-09-29";
  src = thc-src;

  nativeBuildInputs = [
    gradle
    makeWrapper
    python3
    git
    llvm.clang
    llvm.llvm
    # build-cbits.py reads HsFFI.h/HsBaseConfig.h and the RTS configuration
    # (which must be USE_LIBDW=0) from the selected 9.14.1 libdir.
    ghc-thc
  ];
  buildInputs = [ gmp ];

  mitmCache = gradle.fetchDeps {
    pkg = finalAttrs.finalPackage;
    data = ./thc-runtime-deps.json;
  };

  env = {
    JAVA_HOME = jdk;
    THC_CLANG = "${llvm.clang}/bin/clang";
  };

  # The build reads `git rev-parse HEAD` for documentation metadata only.
  postPatch = ''
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    git init -q && git -c user.name=nix -c user.email=nix@localhost commit -q --allow-empty -m ${thc-src.rev}
  '';

  gradleFlags = [
    "-Dorg.gradle.java.installations.auto-download=false"
    "-Dorg.gradle.java.installations.paths=${jdk}"
  ];
  gradleBuildTask = "installDist";
  gradleUpdateTask = "installDist";

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r build/install/thc/. $out/
    rm $out/bin/thc.bat
    wrapProgram $out/bin/thc --set-default JAVA_HOME ${jdk}
    runHook postInstall
  '';

  passthru = { inherit jdk llvm; };

  meta = {
    description = "THC runtime: GHC Core on Truffle/Graal";
    homepage = "https://github.com/ekmett/thc";
    license = with lib.licenses; [ upl bsd3 ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ fromSource binaryBytecode ];
  };
})
