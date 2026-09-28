set -euo pipefail

real_nvim=@REAL_NVIM@
child=@NVIM_KITTY_CHILD@
kitty_socket_name=@KITTY_SOCKET_NAME@

find_kitty_socket() {
  local address

  # When called from inside Kitty, use its exact socket.
  if [[ -n "${KITTY_LISTEN_ON:-}" ]]; then
    if kitten @ \
      --to "$KITTY_LISTEN_ON" \
      ls \
      >/dev/null 2>&1; then
      printf '%s\n' "$KITTY_LISTEN_ON"
      return 0
    fi
  fi

  # When called from Dolphin, discover the configured abstract Kitty socket.
  # Kitty may expose either @NAME or @NAME-PID.
  while IFS= read -r address; do
    address="unix:$address"

    if kitten @ \
      --to "$address" \
      ls \
      >/dev/null 2>&1; then
      printf '%s\n' "$address"
      return 0
    fi
  done < <(
    awk -v base="@$kitty_socket_name" '
      $8 == base {
        print $8
        next
      }

      index($8, base "-") == 1 {
        suffix = substr($8, length(base) + 2)

        if (suffix ~ /^[0-9]+$/) {
          print $8
        }
      }
    ' /proc/net/unix
  )

  return 1
}

kitty_socket="$(find_kitty_socket || true)"

canonical=()

for arg in "$@"; do
  if [[ -e "$arg" ]]; then
    canonical+=("$(realpath -- "$arg")")
  else
    canonical+=("$arg")
  fi
done

files=()

for arg in "${canonical[@]}"; do
  if [[ -e "$arg" && ! -d "$arg" ]]; then
    files+=("$arg")
  fi
done

kitty_json=""

if [[ -n "$kitty_socket" ]]; then
  kitty_json="$(
    kitten @ \
      --to "$kitty_socket" \
      ls \
      2>/dev/null ||
      true
  )"

  if ! jq -e '
    type == "array"
  ' >/dev/null 2>&1 <<<"$kitty_json"; then
    kitty_json=""
  fi
fi

focus_existing_file() {
  local window_id="$1"
  local server="$2"
  local path="$3"
  local buffer_number

  buffer_number="$(loaded_buffer_number "$server" "$path")"

  # bufnr() returns a positive buffer number when the file is loaded.
  if [[ ! "$buffer_number" =~ ^[1-9][0-9]*$ ]]; then
    return 1
  fi

  # --remote uses :drop, selecting the existing Neovim window or tab
  # containing the file rather than creating a duplicate buffer.
  if ! "$real_nvim" \
    --server "$server" \
    --remote \
    "$path" \
    >/dev/null 2>&1; then
    return 1
  fi

  # Select the exact Kitty tab/window containing this Neovim server.
  kitten @ \
    --to "$kitty_socket" \
    focus-window \
    --match "id:$window_id" \
    >/dev/null 2>&1 ||
    true

  return 0
}

loaded_buffer_number() {
  local server="$1"
  local path="$2"
  local path_json
  local buffer_number

  # Encode the path as a valid Vimscript string literal.
  path_json="$(
    jq -Rn \
      --arg path "$path" \
      '$path'
  )"

  buffer_number="$(
    "$real_nvim" \
      --server "$server" \
      --remote-expr "bufnr($path_json)" \
      2>/dev/null ||
      true
  )"

  printf '%s\n' "$buffer_number"
}

file_is_loaded() {
  local server="$1"
  local path="$2"
  local buffer_number

  buffer_number="$(loaded_buffer_number "$server" "$path")"

  [[ "$buffer_number" =~ ^[1-9][0-9]*$ ]]
}

if [[ 
  -n "$kitty_json" &&
  ${#files[@]} -gt 0 ]] \
  ; then
  remaining=("${canonical[@]}")
  existing_window_id=""
  existing_server=""
  existing_file=""

  # Every managed Kitty window advertises:
  #
  #   user_vars.nvim_kitty_server = /run/user/.../server.sock
  while IFS=$'\t' read -r window_id server; do
    if [[ -z "$window_id" || -z "$server" ]]; then
      continue
    fi

    # Ignore stale registrations.
    if ! "$real_nvim" \
      --server "$server" \
      --remote-expr '1' \
      >/dev/null 2>&1; then
      continue
    fi

    for index in "${!remaining[@]}"; do
      file="${remaining[$index]}"

      if [[ ! -e "$file" || -d "$file" ]]; then
        continue
      fi

      if file_is_loaded "$server" "$file"; then
        remaining[index]=""

        if [[ -z "$existing_file" ]]; then
          existing_window_id="$window_id"
          existing_server="$server"
          existing_file="$file"
        fi
      fi
    done
  done < <(
    jq -r '
      .[]?
      | .tabs[]?
      | .windows[]?
      | select(
          (.user_vars.nvim_kitty_server? // "") != ""
        )
      | [
          (.id | tostring),
          .user_vars.nvim_kitty_server
        ]
      | @tsv
    ' <<<"$kitty_json"
  )

  canonical=()

  for file in "${remaining[@]}"; do
    if [[ -n "$file" ]]; then
      canonical+=("$file")
    fi
  done

  if ((${#canonical[@]} == 0)); then
    if [[ -n "$existing_file" ]]; then
      focus_existing_file "$existing_window_id" "$existing_server" "$existing_file" ||
        true
    fi

    exit 0
  fi
fi

cwd="$PWD"
tab_title="nvim"

if ((${#canonical[@]} > 0)); then
  first="${canonical[0]}"

  if [[ -d "$first" ]]; then
    cwd="$first"
  elif [[ "$first" == */* ]]; then
    cwd="$(dirname -- "$first")"
  fi

  tab_title="nvim: $(basename -- "$first")"
fi

runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

umask 077

instance_directory="$(
  mktemp -d -- "$runtime/nvim-kitty.XXXXXXXX"
)"

server="$instance_directory/server.sock"

if [[ -n "$kitty_json" ]]; then
  new_window_id=""

  if new_window_id="$(
    kitten @ \
      --to "$kitty_socket" \
      launch \
      --type=tab \
      --location=after \
      --keep-focus=no \
      --cwd="$cwd" \
      --tab-title="$tab_title" \
      --var "nvim_kitty_server=$server" \
      --env "NVIM_KITTY_SERVER=$server" \
      -- \
      "$child" \
      "${canonical[@]}" \
      2>/dev/null
  )"; then
    # launch prints the ID of the newly created Kitty window.
    if [[ "$new_window_id" =~ ^[0-9]+$ ]]; then
      kitten @ \
        --to "$kitty_socket" \
        focus-window \
        --match "id:$new_window_id" \
        >/dev/null 2>&1 ||
        true
    else
      # The server variable uniquely identifies the newly created window.
      kitten @ \
        --to "$kitty_socket" \
        focus-window \
        --match "var:nvim_kitty_server=$server" \
        >/dev/null 2>&1 ||
        true
    fi

    exit 0
  fi
fi

# No Kitty instance exists. Start one normally and pass the chosen socket
# through the environment.
exec env \
  NVIM_KITTY_SERVER="$server" \
  kitty \
  --directory "$cwd" \
  "$child" \
  "${canonical[@]}"
