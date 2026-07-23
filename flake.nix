{
  description = "Errgonomic";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    gems4nix = {
      url = "github:omc/gems4nix/nz/gemspec-directive-fix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      gems4nix,
      ...
    }:
    let
      allSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      overlays = [ gems4nix.overlays.default ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs allSystems (
          system:
          f {
            pkgs = import nixpkgs { inherit system overlays; };
            inherit system;
          }
        );
      # lib/errgonomic/version.rb is the single source of truth for the version.
      version = builtins.head (
        builtins.match ".*VERSION = '([^']+)'.*" (builtins.readFile ./lib/errgonomic/version.rb)
      );
      # The full Gemfile.lock environment, shared by the dev shell and the
      # package's check phase. The gemspec and version.rb ride along because the
      # Gemfile references the gemspec, which requires version.rb.
      gemEnvFor =
        pkgs:
        pkgs.gemfileEnv {
          name = "errgonomic-gems";
          gemfile = ./Gemfile;
          gemfileLock = ./Gemfile.lock;
          gemspec = ./errgonomic.gemspec;
          extraFiles = {
            "lib/errgonomic/version.rb" = ./lib/errgonomic/version.rb;
          };
          # Committed group mapping keeps evaluation pure (no Ruby IFD), so
          # foreign systems still evaluate on one machine. Regenerate with
          # `rake gems4nix:groups` after changing the Gemfile.
          gemGroups = builtins.fromJSON (builtins.readFile ./gem-groups.json);
        };
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        let
          gems = gemEnvFor pkgs;
        in
        rec {
          default = errgonomic;
          errgonomic = pkgs.stdenv.mkDerivation {
            pname = "errgonomic";
            inherit version;
            src = ./.;
            nativeBuildInputs = [
              pkgs.ruby
              pkgs.git
            ];
            # The gemspec computes its file list with `git ls-files`, so give the
            # sandboxed source copy a git index to enumerate.
            buildPhase = ''
              runHook preBuild
              git init -q
              git add -A
              gem build errgonomic.gemspec
              runHook postBuild
            '';
            nativeCheckInputs = [ gems ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              export HOME="$TMPDIR"
              export GEM_PATH="${gems}/${pkgs.ruby.gemPath}"
              rake
              runHook postCheck
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp errgonomic-${version}.gem $out/
              runHook postInstall
            '';
          };
        }
      );

      # Every package builds and its tests pass; `nix flake check` certifies it.
      checks = self.packages;

      devShells = forAllSystems (
        { pkgs, ... }:
        let
          gems = gemEnvFor pkgs;
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.ruby
              gems
            ];
            env.GEM_PATH = "${gems}/${pkgs.ruby.gemPath}";
          };
        }
      );
    };
}
