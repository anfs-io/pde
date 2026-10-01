# aliases.zsh
# echo ${0:a:h} # The dir of this script

# The XDG/BIN_DIR exports, Homebrew on PATH and ensure_path all moved to .zshrc, which runs
# them before it sources any snippet: the portable ~/.config/sh/*.sh tier is sourced first and
# guards on `command -v <tool>`, so PATH has to be complete before the first snippet loads.

export PPM_FPATH=$XDG_DATA_HOME/omz/custom/completions

xt() { export TERM=xterm-256color; }

# Write a completion file for <cmd> to $PPM_FPATH if <cmd> is installed and the file is missing
# Packages call this from their own .zsh file; `zsrc -c <cmd>` forces a refresh
# Usage: zcomp <cmd> [generator args...]   (default args: completion zsh)
zcomp() {
  local cmd=$1 file=$PPM_FPATH/_$1
  shift
  (( $+commands[$cmd] )) && [[ -n $PPM_FPATH && ! -s $file ]] || return 0
  (( $# )) || set -- completion zsh
  mkdir -p $PPM_FPATH
  if command $cmd "$@" > $file.tmp 2>/dev/null && [[ -s $file.tmp ]]; then
    mv $file.tmp $file
  else
    rm -f $file.tmp
  fi
}

os() {
  case "$(uname)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

load_conf() {
  if [[ $1 == "ls" ]]; then
    shift
    local flags=() target_dir="$dir"
    while [[ $# -gt 0 ]]; do
      if [[ $1 == -* ]]; then
        flags+=("$1")
      elif [[ -d "$target_dir/$1" ]]; then
        target_dir="$target_dir/$1"
        shift
        # Remaining args are treated as flags
        flags+=("$@")
        break
      fi
      shift
    done
    ls "${flags[@]}" "$target_dir"
  elif [[ $1 == "pwd" ]]; then
    echo $dir
  elif [[ $1 == "rm" ]]; then
    file="$dir/$2.${ext}"
    if [[ $# -eq 2 && ( -f $file || -L $file ) ]]; then
      rm $file
    else
      echo "Invalid file $file"
    fi
  elif [[ $1 == "bat" ]]; then
    file="$dir/$2.${ext}"
    if [[ -f $file ]]; then
      bat $file
    else
      echo "Invalid file $file"
    fi
  elif [[ $1 == "cd" ]]; then
    cd "$dir"
  else
    if [[ $# -eq 1 ]]; then
      if [[ -d "$dir/$1" || -z ${ext} ]]; then
        file="${1}"
      else
        file="${1}.${ext}"
      fi
    fi
    (cd $dir; ${EDITOR:-vi} ${file})
  fi
}

zsrc() {
  # Handle the optional -c flag
  local opt run_compinit=0
  local OPTIND=1 # Reset OPTIND locally so repeated calls work correctly

  while getopts "c" opt; do
    case "$opt" in
      c) run_compinit=1 ;;
      *) return 1 ;;
    esac
  done
  shift $((OPTIND - 1)) # Remove the parsed flag, leaving extra arguments in $@

  # Original logic to source the files. Same two tiers, in the same order, as .zshrc.
  setopt local_options nullglob extended_glob
  for file in ${SH_CONFIG:-$HOME/.config/sh}/**/*.sh(N) $ZSH_CONFIG/**/*.zsh(N); do
    source "$file" # No need to check if files exist since nullglob only returns existing files
  done

  # If -c was passed, regenerate the completion file: zsrc -c <cmd> [generator args...]
  if (( run_compinit && $# > 0 )); then
    rm -f "$PPM_FPATH/_$1"
    zcomp "$@"
  fi

  # Re-initialize completion system to register the changes
  autoload -Uz compinit
  compinit
}
