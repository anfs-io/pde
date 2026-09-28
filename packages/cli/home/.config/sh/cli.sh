# cli.sh — portable config for pde/cli's tools, sourced by both the bash and the zsh rc.
# fzf's key bindings are shell-specific: see .config/zsh/cli.zsh and .config/bash/cli.bash.

# Debian's apt package installs the binary as batcat; Homebrew's is bat
command -v bat >/dev/null 2>&1 || { command -v batcat >/dev/null 2>&1 && alias bat=batcat; }

# use bat as pager for commands such as git diff
command -v bat >/dev/null 2>&1 && export PAGER=bat

command -v fzf >/dev/null 2>&1 && alias ff="fzf --filter"

# bat all (or a pattern of) the files in all (or depth -L) subdirs
bata() {
  local depth=""
  local pattern=""
  local hidden="-not -path '*/\.*'"
  local interactive=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -L) depth="-maxdepth $2"; shift 2 ;;
      -p|--pattern) pattern="-name '$2'"; shift 2 ;;
      -a|--all) hidden=""; shift ;;
      -i|--interactive) interactive=true; shift ;;
      *) break ;;
    esac
  done

  local files=$(eval "find . $depth -type f $hidden $pattern 2>/dev/null")

  if [[ -z "$files" ]]; then
    echo "No files found"
    return 1
  fi

  if $interactive; then
    echo "$files" | \
      fzf --multi \
          --preview 'bat --color=always --style=numbers --line-range=:500 {}' \
          --preview-window 'right:60%:wrap' \
          --bind 'ctrl-a:select-all' \
          --bind 'ctrl-d:deselect-all' \
          --bind 'ctrl-/:toggle-preview' | \
      xargs -r bat
  else
    echo "$files" | xargs bat
  fi
}

# Directories/globs to ignore in tree/file listings (shared by tsa, viall, ...).
# Override by reassigning the array in a later-sourced or machine-local file. A plain assignment,
# not typeset: zsrc sources this inside a function, where typeset would make it local.
[ -n "${PPM_IGNORE_DIRS+x}" ] || PPM_IGNORE_DIRS=(
  tmp .git .terraform .obsidian .ruby-lsp .DS_Store '._*'
)

# invoke tree in various forms with specific hidden files
tsa() {
  # -a shows hidden files; -l follow symlinks; -I ignore
  local -a iargs=(); local p
  for p in "${PPM_IGNORE_DIRS[@]}"; do iargs+=( -I "$p" ); done
  tree -a -l "${iargs[@]}" "$@"
}

# Helper: tsa with base dir, optional subdir (first non-flag param), and flags
_tsa_base() {
  local target_dir="$1"
  shift

  # First param: if not a flag, treat as subdir
  if [[ $# -gt 0 && $1 != -* ]]; then
    target_dir="$target_dir/$1"
    shift
  fi

  tsa "$target_dir" "$@"
}

tsac() { _tsa_base "$XDG_CONFIG_HOME" "$@"; }
tsap() { _tsa_base "$XDG_DATA_HOME/ppm" "$@"; }

# Print this machine's primary IPv4 address; any argument keeps the /CIDR suffix
case "$(uname)" in
  Darwin)
    ip_addr() {
      local iface ip_cidr

      # Get active network interface name
      iface=$(route -n get 8.8.8.8 2>/dev/null | awk '/interface:/ {print $2}')
      [[ -z "$iface" ]] && return 1

      # Extract "IP/CIDR" directly using -f inet:cidr
      ip_cidr=$(ifconfig -f inet:cidr "$iface" | awk '/inet / && !/127\.0\.0\.1/ {print $2; exit}')
      [[ -z "$ip_cidr" ]] && return 1

      if [[ -n "$1" ]]; then
        echo "$ip_cidr"
      else
        echo "${ip_cidr%%/*}"
      fi
    }

    alias up="caffeinate -d"
    ;;
  Linux)
    ip_addr() {
      local iface ip_cidr

      # Get active network interface name via route lookup
      iface=$(ip -4 route show default 2>/dev/null | awk '/default/ {print $5; exit}')
      [[ -z "$iface" ]] && return 1

      # Extract "IP/CIDR" directly from ip address output
      ip_cidr=$(ip -4 -br addr show dev "$iface" 2>/dev/null | awk '{print $3; exit}')
      [[ -z "$ip_cidr" ]] && return 1

      if [[ -n "$1" ]]; then
        echo "$ip_cidr"
      else
        echo "${ip_cidr%%/*}"
      fi
    }
    ;;
esac
