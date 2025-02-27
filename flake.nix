{
  description = "Errgonomic";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-24.11";
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      allSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      overlays = [
        (final: prev: {
          gems = final.bundlerEnv {
            name = "errgonomic";
            gemdir = ./.;
            # src = final.lib.cleanSource ../.;
          };
        })
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs allSystems (
          system:
          f {
            pkgs = import nixpkgs { inherit system overlays; };
            inherit system;
          }
        );
    in
    {
      devShells = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.ruby
              pkgs.bundix
              pkgs.gems
            ];
          };
        }
      );

    };
}
