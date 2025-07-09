{
  description = "Errgonomic";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
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
        let
          inherit (pkgs) ruby bundix;
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              ruby
              bundix
              (pkgs.bundlerEnv {
                name = "errgonomic";
                gemdir = ./.;
                extraConfigPaths = [
                  ./errgonomic.gemspec
                  ./lib/errgonomic/version.rb
                ];
                postInstall = ''
                  find . >&2
                '';
              })
            ];
          };
        }
      );

    };
}
