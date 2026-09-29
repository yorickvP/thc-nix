# THC at a pinned revision with its submodules filled in. The GHC submodule
# pins the ghc-9.14.1-release commit, so use nixpkgs' matching release source.
{ runCommand, fetchFromGitHub, haskell }:

let
  rev = "caf5c7792ca76ddcb84fcf2d18e8b05a4a83be9b";
  thc = fetchFromGitHub {
    owner = "ekmett";
    repo = "thc";
    inherit rev;
    hash = "sha256-BAqmsIFjNMCDe6kqhZKFml+w3xU0siobly4ppU+y6+k=";
  };
  bytestring = fetchFromGitHub {
    owner = "haskell";
    repo = "bytestring";
    rev = "d984ad00644c0157bad04900434b9d36f23633c5";
    hash = "sha256-iIrdnBdEImMN8rr2EkyjEemUND1wqHd92RAn8CrWY0o=";
  };
  text = fetchFromGitHub {
    owner = "haskell";
    repo = "text";
    rev = "5f343f668f421bfb30cead594e52d0ac6206ff67";
    hash = "sha256-IDLKPvWRzrO511z/d8XoLzicNw9NbjcnanAa4ae+7wY=";
  };
  zlib = fetchFromGitHub {
    owner = "madler";
    repo = "zlib";
    rev = "cacf7f1d4e3d44d871b605da3b647f07d718623f";
    hash = "sha256-j5b6aki1ztrzfCqu8y729sPar8GpyQWIrajdzpJC+ww=";
  };
in
runCommand "thc-source-${builtins.substring 0 9 rev}" {
  passthru = { inherit rev; };
} ''
  cp -r ${thc} $out
  chmod -R u+w $out
  pinned=$out/nih/pinned
  rmdir $pinned/ghc-9.14.1 $pinned/bytestring-0.12.2.0 $pinned/text-2.1.3 $pinned/zlib-1.2.11
  cp -r ${haskell.compiler.ghc9141.src} $pinned/ghc-9.14.1
  cp -r ${bytestring} $pinned/bytestring-0.12.2.0
  cp -r ${text} $pinned/text-2.1.3
  cp -r ${zlib} $pinned/zlib-1.2.11
  chmod -R u+w $pinned
''
