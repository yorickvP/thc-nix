{
  description = "THC (Haskell on Truffle/Graal) packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f45c6f04c2f013f004bf94e284e95d72898d9393";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.${system} = rec {
        ghc-thc = pkgs.callPackage ./nix/ghc-thc.nix { };
        thc-src = pkgs.callPackage ./nix/thc-src.nix { };
        thc-runtime = pkgs.callPackage ./nix/thc-runtime.nix { inherit thc-src ghc-thc; };
        zlib_1_2_11 = pkgs.callPackage ./nix/zlib-1_2_11.nix { };
        thc = pkgs.callPackage ./nix/thc.nix { inherit thc-src thc-runtime ghc-thc zlib_1_2_11; };
        pandoc-demo = pkgs.callPackage ./nix/pandoc-demo.nix { inherit thc thc-src; };
        default = thc;
      };

      apps.${system}.pandoc-demo = {
        type = "app";
        program = "${self.packages.${system}.pandoc-demo}/bin/thc-pandoc-demo";
      };
    };
}
