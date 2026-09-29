# Upstream's pandoc 3.11 workload (src/examples/standard-apps/pandoc), run on
# THC with complete installed Core. Needs network for Hackage.
{ writeShellApplication, cabal-install, diffutils, coreutils, thc, thc-src }:

writeShellApplication {
  name = "thc-pandoc-demo";
  runtimeInputs = [ thc cabal-install diffutils coreutils ];
  text = ''
    work=''${1:-$PWD/thc-pandoc}
    shift || true
    mkdir -p "$work"
    cd "$work"
    if [ ! -d pandoc-3.11 ]; then
      cp -r ${thc-src}/src/examples/standard-apps/pandoc/. .
      chmod -R u+w .
      cabal get pandoc-3.11 pandoc-cli-3.11
      cache=$(cabal path --remote-repo-cache)/hackage.haskell.org
      sha256sum -c <<EOF
    50a04f7e8b244491546c45e81a6e7a0263d7e8c46a776b80738d51294a79f8a8  $cache/pandoc/3.11/pandoc-3.11.tar.gz
    a9f3fc8c64962c8778b379cc2238c7c554541e1e94fd36a210c3f92e1729e929  $cache/pandoc-cli/3.11/pandoc-cli-3.11.tar.gz
    EOF
    fi
    # Upstream's cabal.project says `jobs: 2`; only parallelism is overridden.
    # Kept modest: GHC slows down superlinearly with many concurrent jobs.
    jobs=''${THC_PANDOC_JOBS:-$(( $(nproc) < 8 ? $(nproc) : 8 ))}
    echo "jobs: $jobs" > cabal.project.local
    export pandoc_datadir="$work/pandoc-3.11"
    thc run pandoc-cli:exe:pandoc --installed-core required \
      --dist-dir "$work/dist-thc" "$@" -- --from markdown --to html smoke.md > guest.html
    if diff -u expected.html guest.html; then
      echo "pandoc on THC: output matches expected.html" >&2
    else
      echo "pandoc on THC: output differs from expected.html" >&2
      exit 1
    fi
  '';
}
