{
  description = "Open files from Dolphin in the Neovim instance already displaying them inside Kitty";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

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
