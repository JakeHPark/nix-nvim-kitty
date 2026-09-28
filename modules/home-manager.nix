{
  nix-home-utils,
  self,
}:

{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:

let
  cfg = config.programs.nvim-kitty;

  osPackage =
    if
      osConfig != null
      && osConfig ? programs
      && osConfig.programs ? nvim-kitty
      && osConfig.programs.nvim-kitty ? package
    then
      osConfig.programs.nvim-kitty.package
    else
      null;

  defaultPackage =
    if osPackage != null then
      osPackage
    else
      pkgs.nvim-kitty or self.packages.${pkgs.stdenv.hostPlatform.system}.default;

  defaultTabKeybindings = {
    "ctrl+t" = lib.mkDefault "new_tab";
    "ctrl+w" = lib.mkDefault "close_tab";
    "ctrl+shift+w" = lib.mkDefault "close_os_window";
    "ctrl+right" = lib.mkDefault "next_tab";
    "ctrl+left" = lib.mkDefault "previous_tab";
  }
  // builtins.listToAttrs (
    map (tabNumber: {
      name = "ctrl+${tabNumber}";
      value = lib.mkDefault "goto_tab ${tabNumber}";
    }) (builtins.genList (index: toString (index + 1)) 9)
  );

in
{
  options.programs.nvim-kitty = {
    enable = lib.mkEnableOption "nvim-kitty";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "osConfig.programs.nvim-kitty.package or pkgs.nvim-kitty or inputs.nix-nvim-kitty.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "The nvim-kitty package to install.";
    };

    kittySocketName = lib.mkOption {
      type = lib.types.str;
      default = cfg.package.passthru.kittySocketName or "kitty-main";
      defaultText = lib.literalExpression ''programs.nvim-kitty.package.passthru.kittySocketName or "kitty-main"'';
      description = "The Kitty remote-control socket name used by nvim-kitty.";
    };

    sensibleMiscDefaults = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to set miscellaneous Kitty defaults useful for nvim-kitty.";
    };

    sensibleDefaultPrompt = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to set a convenient default shell prompt in Kitty.";
    };

    sensibleTabKeybindings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to set common Kitty tab keybindings.";
    };

    plasmaFocusStealingFix = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to configure KWin to allow nvim-kitty to focus Kitty.";
    };

    plasmaDefaultTerminal = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to configure KDE to use Kitty as the default terminal.";
    };
  };

  config = lib.mkMerge (
    [
      (lib.mkIf cfg.enable {
        home.packages = [
          cfg.package
        ];

        programs.kitty = {
          enable = lib.mkDefault true;

          environment = lib.mkMerge [
            (lib.mkIf cfg.sensibleMiscDefaults {
              HISTCONTROL = lib.mkDefault "ignoredups";
            })
            (lib.mkIf cfg.sensibleDefaultPrompt {
              PROMPT = lib.mkDefault "\\[\\e]0;\\W\\a\\]\${debian_chroot:+(debian_chroot)}\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\e[00;35m\\]$(__git_ps1)\\[\\033[00m\\]$";
              PROMPT_COMMAND = lib.mkDefault ''export PS1="$PROMPT "'';
            })
          ];

          keybindings = lib.mkIf cfg.sensibleTabKeybindings defaultTabKeybindings;

          settings = lib.mkIf cfg.sensibleMiscDefaults {
            scrollback_lines = lib.mkDefault 10000;
            enable_audio_bell = lib.mkDefault false;
            confirm_os_window_close = lib.mkDefault 0;

            allow_remote_control = lib.mkDefault "socket-only";
            listen_on = lib.mkDefault "unix:@${cfg.kittySocketName}";
          };
        };
      })
    ]
    ++ [
      (lib.mkMerge [
        (lib.mkIf (cfg.enable && cfg.plasmaFocusStealingFix) {
          home.activation.nvim-kitty-kwin = lib.mkDefault (
            nix-home-utils.lib.mkPatchIniActivation {
              inherit lib pkgs;
              path = ".config/kwinrc";
              options.Windows.FocusStealingPreventionLevel = 0;
            }
          );
        })
        (lib.mkIf (cfg.enable && cfg.plasmaDefaultTerminal) {
          home.activation.nvim-kitty-kdeglobals = lib.mkDefault (
            nix-home-utils.lib.mkPatchIniActivation {
              inherit lib pkgs;
              path = ".config/kdeglobals";
              options.General = {
                TerminalApplication = "kitty";
                TerminalService = "kitty.desktop";
              };
            }
          );
        })
      ])
    ]
  );
}
