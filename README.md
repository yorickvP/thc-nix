# thc-nix

Nix packaging for [THC](https://github.com/ekmett/thc) (Haskell on
Truffle/Graal), pinned to upstream `621b6c15a` (2026-09-29).

| Output | What it is |
| --- | --- |
| `ghc-thc` | GHC 9.14.1 from nixpkgs, rebuilt following THC's recipe: every Haskell interface carries complete Core (`-fwrite-if-simplified-core`), Hadrian's `perf` flavour, no libdw (`USE_LIBDW=0`), and no profiled libraries. Its `tree` output is the pruned, configured Hadrian build tree that `--ghc-source` needs. |
| `thc-runtime` | The Truffle runtime (`gradle installDist`); Maven dependencies are locked in `nix/thc-runtime-deps.json`. |
| `thc` (default) | The driver. See below. |
| `pandoc-demo` (app) | Upstream's pandoc 3.11 workload, run on THC. |

## Status

On x86_64-linux, `nix run .#pandoc-demo` runs upstream's unmodified
pandoc 3.11 workload (HTTP, Lua, server and REPL features enabled) on THC
using complete installed Core. It converts `smoke.md` to HTML, and the output
matches upstream's `expected.html` byte for byte. A cold run takes about an
hour on 32 cores: the native build and Core capture for roughly 200 packages.
Warm reruns take about 3 minutes. Caches use about 3 GB (Cabal store, THC
bundles, dist).

## Usage

```sh
nix run .#thc -- run my-pkg:exe:my-prog --installed-core required -- ARGS
nix run .#pandoc-demo -- /some/work/dir
```

THC's driver expects `--thc-root` to be a writable, built checkout: before each
project run it rebuilds its GHC plugin and interface helper there with
`cabal --offline`. So the `thc` wrapper keeps a copy of the pinned source under
`$THC_NIX_HOME` (default `~/.cache/thc-nix`) and links `build/install/thc` to
`thc-runtime`. On first use it builds the Haskell side there with `ghc-thc`,
which fetches Hackage dependencies. The wrapper adds `--thc-root` to
`run`/`acquire`, and adds `--ghc-source` whenever `--installed-core required` is
given.

## Non-obvious bits

- **Hadrian needs Cabal 3.16.0.0.** For `--ghc-source`, THC's driver reads
  Hadrian's `setup-config` files with its own Cabal library (3.16.0.0, GHC
  9.14.1's boot Cabal). Cabal rejects a `setup-config` written by another Cabal
  version, and nixpkgs builds Hadrian 9.14 against Cabal 3.14.2.0. `ghc-thc`
  therefore rebuilds Hadrian against the in-tree Cabal.
- **GHC builds inside its `tree` output.** THC compares the canonicalized build
  directory recorded in each `setup-config` against the directory you pass. It
  also requires the `.dyn_hi` files there to be byte-identical to the installed
  ones. After installation, object files and tools are removed from the tree.
- **`perf`, not `release`.** nixpkgs builds Hadrian's `release` flavour, which
  is `perf` plus `-fno-write-if-self-recomp`, Haddock in interfaces, and hashed
  unit ids. `--ghc-source` checks each retained source hash and CPP usage file
  against the tree, so the self-recompilation data has to stay. Unit ids are
  unhashed, as in upstream's recipe (for example `ghc-9.14.1-inplace`).
- **No `--with-gmp-includes`.** THC requires `ghc-internal`'s configured
  `include-dirs` to be exactly `["include"]`. nixpkgs' explicit GMP include path
  shows up there, so it is dropped, and the cc-wrapper finds `gmp.h` instead.
- **PIC C objects in GHC's static libraries.** For installed packages, THC
  links C objects straight out of their `.a` archives into a shared object
  (for example, `gmp_wrappers.o` from `ghc-internal`). GHC compiles
  static-way C with `-fno-PIC` (GHC #15847), so `ghc-thc` passes
  `*.*.ghc.c.opts += -fPIC`.
- **LLVM 19, not 18.** Upstream CI installs LLVM 18, but the driver's
  package-native step runs `opt -passes=pre-isel-intrinsic-lowering,...`, and
  LLVM 18's new pass manager doesn't register that pass. Sulong 25.3.4.1 is
  itself built with clang 22, so LLVM 19 bitcode is well within what it reads.
- **zlib 1.2.11 for guest packages.** THC's checksum provider for `digest`
  (a pandoc dependency) compiles the pinned zlib 1.2.11 `adler32`/`crc32`
  sources. It accepts only a configured zlib 1.2.11 header (`ZLIB_VERNUM
  0x12b0`), which is what macOS ships; nixpkgs has 1.3.x. The wrapper
  therefore puts `zlib_1_2_11` on the guest build's pkg-config, compiler and
  linker paths. That version has known CVEs (CVE-2018-25032, CVE-2022-37434).
- **Explicit LLVM tools.** The driver looks for `llvm-objcopy` next to
  `clang`. nixpkgs keeps the clang wrapper and the LLVM tools in separate
  packages, so the wrapper sets `THC_LLVM_{OBJCOPY,LINK,NM,OPT,DIS}`.
- **No libdw.** The runtime reimplements the RTS's unavailable-DWARF profile
  and refuses a GHC with `USE_LIBDW=1`.
- **The GHC submodule** pins `ghc-9.14.1-release`, so `thc-src` uses nixpkgs'
  release source for it. Every `nih/pinned/ghc-9.14.1/...` path that THC
  references is present there.
- **Updating Gradle dependencies:**
  `USE_BWRAP=0 $(nix build --print-out-paths .#thc-runtime.mitmCache.updateScript)`.
  bwrap can't mount `/proc` inside containers.
