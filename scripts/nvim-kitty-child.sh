set -euo pipefail

real_nvim=@REAL_NVIM@
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

umask 077

# nvim-kitty may choose the socket in advance. Ordinary vi/vim/nvim
# invocations create their own private runtime directory here.
server="${NVIM_KITTY_SERVER:-}"

if [[ -n "$server" ]]; then
  instance_directory="$(dirname -- "$server")"
  mkdir -p -- "$instance_directory"
else
  instance_directory="$(
    mktemp -d -- "$runtime/nvim-kitty.XXXXXXXX"
  )"

  server="$instance_directory/server.sock"
fi

cleanup() {
  # Runtime cleanup is best-effort. The entire XDG runtime directory is
  # temporary anyway, so cleanup must never make Neovim appear to fail.
  rm -rf -- "$instance_directory" \
    >/dev/null 2>&1 ||
    true
}

trap cleanup EXIT

# Register this Neovim server with its containing Kitty window.
if [[ 
  -n "${KITTY_WINDOW_ID:-}" &&
  -n "${KITTY_LISTEN_ON:-}" ]] \
  ; then
  kitten @ \
    --to "$KITTY_LISTEN_ON" \
    set-user-vars \
    --match "id:$KITTY_WINDOW_ID" \
    "nvim_kitty_server=$server" \
    >/dev/null 2>&1 ||
    true
fi

"$real_nvim" \
  --listen "$server" \
  "$@"
