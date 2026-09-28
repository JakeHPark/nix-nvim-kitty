{
  description = "Open files from your Linux file manager in the Neovim instance already displaying them inside Kitty";

  inputs = {
    nix-home-utils = {
      url = "github:JakeHPark/nix-home-utils";
      flake = false;
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nix-home-utils,
      nixpkgs,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      nixHomeUtils = {
        lib = import "${nix-home-utils}/lib" {
          inherit (nixpkgs) lib;
        };
      };

      mkPackage =
        {
          pkgs,
          neovim ? pkgs.neovim,
          kittySocketName ? "kitty-main",
        }:
        pkgs.callPackage ./package.nix {
          inherit neovim kittySocketName;
        };
    in
    {
      overlays.default =
        final: prev:
        let
          makeNvimKittyPackage =
            {
              neovim ? prev.neovim,
              kittySocketName ? "kitty-main",
            }:
            mkPackage {
              pkgs = final;
              inherit neovim kittySocketName;
            };
        in
        {
          inherit makeNvimKittyPackage;

          nvim-kitty = makeNvimKittyPackage {
            neovim = prev.neovim;
          };
        };

      nixosModules.default = import ./modules/nixos.nix {
        inherit self;
      };

      homeManagerModules.default = import ./modules/home-manager.nix {
        nix-home-utils = nixHomeUtils;
        inherit self;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
        in
        rec {
          nvim-kitty = mkPackage {
            inherit pkgs;
          };

          default = nvim-kitty;
        }
      );
    };
}
