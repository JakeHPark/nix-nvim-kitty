# Nix Neovim Kitty

A deliberately specific integration for **Neovim + Kitty + Dolphin/KDE**.

When Dolphin opens a file, `nvim-kitty`:

1. Finds every managed Neovim instance running inside Kitty.
2. Checks whether one of them already has that file loaded.
3. Selects the existing Neovim window/buffer and its exact Kitty tab.
4. Otherwise opens the file in a new tab of the existing Kitty instance.
5. Starts Kitty normally when no Kitty instance exists.

Terminal launches through `vi`, `vim`, or `nvim` can also be found from Dolphin.

The package also installs its own `nvim.desktop`. It calls `nvim-kitty`, uses `Terminal=false`, and disables startup notification.

https://github.com/user-attachments/assets/ab251983-aa9c-4c46-b0c7-1544eeda679e

## Requirements

This discovers Kitty's abstract remote-control socket through `/proc/net/unix`. Kitty must enable remote control and use the matching socket name:

```nix
programs.kitty.settings = {
  allow_remote_control = "socket-only";
  listen_on = "unix:@kitty-main";
};
```

The default `kittySocketName` is `"kitty-main"`.

On Plasma/Wayland, KWin may turn an external focus request into an orange taskbar attention marker. This [Plasma Manager](https://github.com/nix-community/plasma-manager) setting permits `nvim-kitty` to focus Kitty:

```nix
programs.plasma.configFile.kwinrc."Windows"."FocusStealingPreventionLevel" = 0;
```

## Use the stock Neovim package

Add the flake input:

```nix
inputs.nix-nvim-kitty = {
  url = "github:JakeHPark/nix-nvim-kitty";
  inputs.nixpkgs.follows = "nixpkgs";
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

## Binaries

- `nvim-kitty`: Dolphin/desktop launcher.
- `nvim-kitty-child`: starts and registers a Neovim RPC server inside a Kitty window.
- `nvim`, `vim`, `vi`: symlinks to `nvim-kitty-child`.
