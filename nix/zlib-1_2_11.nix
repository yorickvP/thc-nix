# THC's zlib checksum source provider (used for `digest`) compiles the pinned
# zlib 1.2.11 adler32/crc32 sources and refuses any configured zlib header
# other than 1.2.11 (ZLIB_VERNUM 0x12b0). nixpkgs has 1.3.x.
# 1.2.11 has known CVEs (CVE-2018-25032, CVE-2022-37434); it is only used for
# building and linking guest packages through the `thc` wrapper.
{ zlib, fetchurl }:

zlib.overrideAttrs (old: {
  version = "1.2.11";
  src = fetchurl {
    url = "https://zlib.net/fossils/zlib-1.2.11.tar.gz";
    hash = "sha256-w+Xp/dUATctUL+2l7k8P8HRGKLr47S3V1m+MoRl8saE=";
  };
  # Both target the 1.3.x sources.
  patches = [ ];
  postPatch = "";
})
