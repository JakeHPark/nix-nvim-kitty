{
  lib,
  symlinkJoin,
  writeShellApplication,
  coreutils,
  gawk,
  jq,
  kitty,
  neovim,
  kittySocketName ? "kitty-main",
}:

let
  nvimKittyChild = writeShellApplication {
    name = "nvim-kitty-child";

    runtimeInputs = [
      coreutils
      kitty
    ];

    text = builtins.replaceStrings [ "@REAL_NVIM@" ] [ "${neovim}/bin/nvim" ] (
      builtins.readFile ./scripts/nvim-kitty-child.sh
    );
  };

  nvimKitty = writeShellApplication {
    name = "nvim-kitty";

    runtimeInputs = [
      coreutils
      gawk
      jq
      kitty
    ];

    text =
      builtins.replaceStrings
        [
          "@REAL_NVIM@"
          "@NVIM_KITTY_CHILD@"
          "@KITTY_SOCKET_NAME@"
        ]
        [
          "${neovim}/bin/nvim"
          "${nvimKittyChild}/bin/nvim-kitty-child"
          (lib.escapeShellArg kittySocketName)
        ]
        (builtins.readFile ./scripts/nvim-kitty.sh);
  };
in
symlinkJoin {
  name = "nvim-kitty-${lib.getVersion neovim}";

  paths = [
    neovim
    nvimKitty
    nvimKittyChild
  ];

  postBuild = ''
    mkdir -p "$out/bin"

    # All interactive vi/vim/nvim launches must register their RPC socket with
    # the containing Kitty window, so route them through the managed child.
    rm -f -- \
      "$out/bin/vi" \
      "$out/bin/vim" \
      "$out/bin/nvim"

    ln -s ${nvimKittyChild}/bin/nvim-kitty-child "$out/bin/vi"
    ln -s ${nvimKittyChild}/bin/nvim-kitty-child "$out/bin/vim"
    ln -s ${nvimKittyChild}/bin/nvim-kitty-child "$out/bin/nvim"

    mkdir -p "$out/share/applications"
    rm -f -- "$out/share/applications/nvim.desktop"

    substitute ${./nvim.desktop.in} "$out/share/applications/nvim.desktop" \
      --replace-fail '@out@' "$out"
  '';

  passthru = {
    inherit neovim nvimKitty nvimKittyChild;
  };

  meta = {
    description = "Dolphin, Kitty and Neovim single-instance integration";
    homepage = "https://github.com/JakeHPark/nix-nvim-kitty";
    license = lib.licenses.mit;
    mainProgram = "nvim-kitty";
    platforms = lib.platforms.linux;
  };
}
