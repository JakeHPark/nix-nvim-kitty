{ self }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.nvim-kitty;

  defaultPackage = pkgs.nvim-kitty or self.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.programs.nvim-kitty = {
    enable = lib.mkEnableOption "nvim-kitty";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "pkgs.nvim-kitty or inputs.nix-nvim-kitty.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "The nvim-kitty package to install.";
    };

    setDefaultEnvironmentVariables = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to set convenient global environment and sudo defaults for Kitty and Neovim.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [
        cfg.package
      ];
    })
    (lib.mkIf (cfg.enable && cfg.setDefaultEnvironmentVariables) {
      environment.variables.EDITOR = lib.mkOverride 900 "nvim";
      environment.variables.TERMINAL = lib.mkOverride 900 "kitty";
      environment.variables.VISUAL = lib.mkOverride 900 "nvim";

      security.sudo.extraConfig = lib.mkAfter ''
        Defaults env_keep += "XDG_RUNTIME_DIR WAYLAND_DISPLAY"
      '';
    })
  ];
}
