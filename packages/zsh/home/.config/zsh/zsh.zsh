# zsh.zsh

# vim keybindings
bindkey -v

# General Aliases and helpers
alias lsar="lsa -R"

# case-insensitive list of defined aliases
ag() {
  if [[ -z "$1" ]]; then
    echo "Usage: ag <pattern>"
    echo "Search for aliases matching the given pattern"
    return 1
  fi

  echo "Aliases matching '$1':"
  alias | grep --color=auto -i "$1" | sort
}


zconf() {
  local dir=$XDG_CONFIG_HOME/zsh file="aliases.zsh" ext="zsh"
  if [[ $# == 1 && "$1" == ".zshrc" ]]; then
    ext=""
  fi
  load_conf "$@"
}

# cd to the directory containing the real file behind a symlink
lcd() {
  [[ -z "$1" ]] && { echo "Usage: lcd <symlink>"; return 1; }
  [[ ! -L "$1" ]] && return
  cd "$(dirname "$(realpath "$1")")"
}
