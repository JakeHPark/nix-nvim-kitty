# Nix Neovim Kitty

Open files from your Linux file manager in the Neovim instance already displaying them inside Kitty, or a new Kitty tab. Also comes with sensible defaults for Kitty and Neovim.

When you open a file, `nvim-kitty`:

1. Finds every managed Neovim instance running inside Kitty.
2. Checks whether one of them already has that file loaded.
3. Selects the existing Neovim window/buffer and its exact Kitty tab.
4. Otherwise opens the file in a new tab of the existing Kitty instance.
5. Starts Kitty normally when no Kitty instance exists.

When you open multiple files, it will open them all in different buffers in the same Neovim instance, except for the ones that are already open. Remember to check `:bnext`/`:bprevious` before getting confused that only one file opened.

The package also installs its own `nvim.desktop`. It calls `nvim-kitty`, uses `Terminal=false`, and disables startup notification.

## Requirements

This discovers Kitty's abstract remote-control socket through `/proc/net/unix`. Kitty must enable remote control and use the matching socket name:

```nix
programs.kitty.settings = {
  allow_remote_control = "socket-only";
  listen_on = "unix:@kitty-main";
};
```

The default `kittySocketName` is `"kitty-main"`.

On Plasma/Wayland, KWin may turn an external focus request into an orange taskbar attention marker. The Home Manager module, if enabled, uses [Nix Home Utils](https://github.com/JakeHPark/nix-home-utils)' KConfig patching helper to set this in `~/.config/kwinrc`:

```nix
[Windows]
FocusStealingPreventionLevel=0
```

## Use the stock Neovim package

Add the flake input:

```nix
inputs.nix-nvim-kitty = {
  url = "github:JakeHPark/nix-nvim-kitty";
  inputs.nixpkgs.follows = "nixpkgs";
  # If you also have Nix Home Utils:
  inputs.nix-home-utils.follows = "nix-home-utils";
};
```

Then use the overlay and install the package:

```nix
nixpkgs.overlays = [ inputs.nix-nvim-kitty.overlays.default ];
```

```text
environment.systemPackages = [ pkgs.nvim-kitty ];
```

## Wrap an already configured Neovim package

```nix
nixpkgs.overlays = [
  (final: prev: {
    nvim-kitty-custom = final.makeNvimKittyPackage {
      neovim = prev.wrapNeovimUnstable prev.neovim-unwrapped {
        viAlias = true;
        vimAlias = true;
        luaRcContent = builtins.readFile ./modules/neovim/init.lua;
        # Your existing wrapperArgs/plugins/etc.
      };
    };
  })
];
```

Note that you shouldn't call the new package `nvim-kitty`, because this flake could end up overriding it.

## Custom socket name

A non-default Kitty socket name must be changed in both places:

```nix
final.makeNvimKittyPackage {
  kittySocketName = "my-kitty-socket";
}
```

```nix
programs.kitty.settings.listen_on = "unix:@my-kitty-socket";
```

## Use the modules for sensible defaults

The modules are the easiest way to use the package because they install `nvim-kitty` and apply the related Kitty, shell, sudo, and Plasma defaults together. Defaults are written so they can be overridden one value at a time without disabling the rest of the defaults.

Use the NixOS module for system-wide defaults:

```nix
{
  imports = [
    inputs.nix-nvim-kitty.nixosModules.default
  ];

  programs.nvim-kitty.enable = true;
}
```

Use the Home Manager module for user-level Kitty defaults:

```nix
{
  imports = [
    inputs.nix-nvim-kitty.homeManagerModules.default
  ];

  programs.nvim-kitty.enable = true;
}
```

The modules expose a `package` option if you want to use a wrapped Neovim package:

```nix
programs.nvim-kitty.package = pkgs.nvim-kitty-custom;
```

When Home Manager is used through the NixOS Home Manager module, the Home Manager
module defaults to the system-level `programs.nvim-kitty.package` if that option
exists. This keeps the NixOS and Home Manager modules on the same wrapped
Neovim package unless you override the Home Manager option separately.

### NixOS defaults

When `programs.nvim-kitty.enable = true;`, the NixOS module adds `programs.nvim-kitty.package` to `environment.systemPackages`.

Enabled by default, `programs.nvim-kitty.setDefaultEnvironmentVariables = true;` also sets:

```nix
environment.variables = {
  EDITOR = "nvim";
  TERMINAL = "kitty";
  VISUAL = "nvim";
};
```

These are convenience defaults for shells, launchers, and programs that consult the standard editor or terminal environment variables.

The same option appends this sudo configuration:

```nix
security.sudo.extraConfig = ''
  Defaults env_keep += "XDG_RUNTIME_DIR WAYLAND_DISPLAY"
'';
```

This helps root commands keep enough Wayland session context for tools such as Neovim clipboard integrations that call `wl-copy`. It is appended to any existing `security.sudo.extraConfig`.

Disable the NixOS environment and sudo defaults with:

```nix
programs.nvim-kitty.setDefaultEnvironmentVariables = false;
```

### Home Manager defaults

When `programs.nvim-kitty.enable = true;`, the Home Manager module adds `programs.nvim-kitty.package` to `home.packages` and enables Kitty by default:

```nix
programs.kitty.enable = true;
```

The Kitty options to follow are enabled by default, since the assumption is that anyone using this is using Kitty and Neovim as their main terminal and editor. The Plasma options are enabled by default only when the Home Manager module can see that NixOS Plasma is enabled through `osConfig`, such as when Home Manager is used through the NixOS Home Manager module. I know this is opinionated, but you can just not use the Home Manager module if you don't like it.

#### Miscellaneous Kitty defaults

By default, `programs.nvim-kitty.sensibleMiscDefaults = true;` sets:

```nix
programs.kitty.environment.HISTCONTROL = "ignoredups";

programs.kitty.settings = {
  scrollback_lines = 10000;
  enable_audio_bell = false;
  confirm_os_window_close = 0;
  allow_remote_control = "socket-only";
  listen_on = "unix:@kitty-main";
};
```

`HISTCONTROL = "ignoredups"` keeps repeated adjacent shell commands out of history.

`scrollback_lines = 10000` gives Kitty a larger scrollback buffer than a minimal setup.

`enable_audio_bell = false` disables audible terminal bells.

`confirm_os_window_close = 0` lets Kitty windows close without an extra confirmation prompt.

`allow_remote_control = "socket-only"` and `listen_on = "unix:@kitty-main"` are the important `nvim-kitty` integration defaults. `nvim-kitty` discovers Kitty's abstract socket through `/proc/net/unix`, sends remote-control commands through that socket, and uses it to inspect tabs/windows, focus an existing Neovim instance, or open a new tab. The default socket name is set according to `programs.nvim-kitty.kittySocketName`.

#### Prompt default

By default, `programs.nvim-kitty.sensibleDefaultPrompt = true;` sets:

```nix
programs.kitty.environment = {
  PROMPT = "\\[\\e]0;\\W\\a\\]\${debian_chroot:+(debian_chroot)}\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\e[00;35m\\]$(__git_ps1)\\[\\033[00m\\]$";
  PROMPT_COMMAND = ''export PS1="$PROMPT "'';
};
```

This gives Bash sessions launched by Kitty a colored `user@host:path` prompt, includes the Git branch when `__git_ps1` is available (use `programs.git.prompt.enable = true;`), and updates the terminal title to the current directory. It is kept separate from `sensibleMiscDefaults` because prompts are more personal than the integration defaults.

#### Tab keybindings

By default, `programs.nvim-kitty.sensibleTabKeybindings = true;` sets:

```nix
programs.kitty.keybindings = {
  "ctrl+t" = "new_tab";
  "ctrl+w" = "close_tab";
  "ctrl+shift+w" = "close_os_window";
  "ctrl+right" = "next_tab";
  "ctrl+left" = "previous_tab";
  "ctrl+1" = "goto_tab 1";
  "ctrl+2" = "goto_tab 2";
  "ctrl+3" = "goto_tab 3";
  "ctrl+4" = "goto_tab 4";
  "ctrl+5" = "goto_tab 5";
  "ctrl+6" = "goto_tab 6";
  "ctrl+7" = "goto_tab 7";
  "ctrl+8" = "goto_tab 8";
  "ctrl+9" = "goto_tab 9";
};
```

These bindings make Kitty tabs behave more like browser/editor tabs: create, close, switch left/right, and jump directly to numbered tabs.

#### Plasma/KConfig defaults

`programs.nvim-kitty.plasmaFocusStealingFix` defaults to true only when the module detects NixOS Plasma. When enabled, it patches `.config/kwinrc` with:

```nix
[Windows]
FocusStealingPreventionLevel=0
```

This lets `nvim-kitty` focus the Kitty window after it selects an existing Neovim buffer or opens a new tab. Without it, Plasma on Wayland may show an attention marker in the taskbar instead of actually raising/focusing Kitty.

`programs.nvim-kitty.plasmaDefaultTerminal` uses the same detected default. When enabled, it also sets:

```nix
[General]
TerminalApplication=kitty
TerminalService=kitty.desktop
```

This makes KDE applications that ask Plasma for the preferred terminal use Kitty. For example, file managers and desktop actions that open a terminal should resolve to Kitty instead of another installed terminal emulator. The generated activation entries use `mkDefault`, so you can replace them from your own Home Manager configuration if needed. If you use Home Manager standalone on a Plasma system, set these options explicitly because there is no NixOS `osConfig` available to inspect.

Disable groups of Home Manager defaults with:

```nix
programs.nvim-kitty = {
  sensibleMiscDefaults = false;
  sensibleDefaultPrompt = false;
  sensibleTabKeybindings = false;
  plasmaFocusStealingFix = false;
  plasmaDefaultTerminal = false;
};
```

## Example configuration

```nix
nixpkgs.overlays = [
  (final: prev: {
    nvim-kitty-custom = final.makeNvimKittyPackage {
      neovim = prev.wrapNeovimUnstable prev.neovim-unwrapped {
        viAlias = true;
        vimAlias = true;
        luaRcContent = builtins.readFile ./modules/neovim/init.lua;
      };
    };
  })
];

programs.nvim-kitty = {
  enable = true;
  package = pkgs.nvim-kitty-custom;
};

xdg.mime.defaultApplications =
 let
   markdown = [
     "nvim.desktop"
     "org.gnome.gitlab.somas.Apostrophe.desktop"
   ];
   text = [ "nvim.desktop" ];

   forEach =
     types: apps:
     builtins.listToAttrs (
       map (type: {
         name = type;
         value = apps;
       }) types
     );
 in
 // (forEach [
   "application/xml"
   "application/x-shellscript"
   "text/javascript"
   "text/plain"
   "text/x-lua"
   "text/x-python"
   # Generic/extensionless files.
   "application/octet-stream"
 ] text)
 // (forEach [
   "text/markdown"
 ] markdown);

fonts.packages = with pkgs; [ nerd-fonts.meslo-lg ];

home-manager.users.jakehpark = {
  programs.nvim-kitty.enable = true;

  programs.kitty = {
    font.name = "MesloLGM Nerd Font Mono";

    settings = {
      background_image = "${./modules/kitty/moon.png}";
      background_image_layout = "scaled";
      background_tint = "0.55";
    };
  };
};
```

If you want inspiration for a minimal Neovim configuration, check out [mine](https://gist.github.com/JakeHPark/8d3595e186788c6598bde51e6d029e3a).

## Binaries

- `nvim-kitty`: Dolphin/desktop launcher.
- `nvim-kitty-child`: starts and registers a Neovim RPC server inside a Kitty window.
- `nvim`, `vim`, `vi`: symlinks to `nvim-kitty-child`.
