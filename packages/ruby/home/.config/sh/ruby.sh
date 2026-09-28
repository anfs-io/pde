# ruby.sh — portable (bash and zsh); gem-local's completion is in .config/{zsh,bash}/ruby.*

export RUBY_LOCAL_GEMS_HOME="$XDG_DATA_HOME/gems"

# Single bin dir from bundle install
ensure_path "$RUBY_LOCAL_GEMS_HOME/bin"

# RUBYLIB: every local gem's lib/ dir, then ~/.local/lib/ruby, then whatever else was inherited.
# Rebuilt on every shell start (dropping inherited gem entries) so gems linked since the parent
# shell started show up, and gems unlinked since are gone.
_ruby_rubylib() {
  # zsh aborts on a glob with no match; bash leaves it literal, which the -d test skips
  [ -n "${ZSH_VERSION:-}" ] && setopt local_options null_glob
  local libs="" rest="${RUBYLIB:-}" entry dir
  for dir in "$RUBY_LOCAL_GEMS_HOME"/*/lib; do
    [ -d "$dir" ] && libs="${libs:+$libs:}$dir"
  done
  libs="${libs:+$libs:}$LIB_DIR/ruby"
  while [ -n "$rest" ]; do
    entry="${rest%%:*}"
    case "$rest" in *:*) rest="${rest#*:}" ;; *) rest="" ;; esac
    case "$entry" in
      ""|"$LIB_DIR/ruby"|"$RUBY_LOCAL_GEMS_HOME"/*) ;;
      *) libs="$libs:$entry" ;;
    esac
  done
  export RUBYLIB="$libs"
}
_ruby_rubylib
unset -f _ruby_rubylib

# Wrapper to handle `local-gems cd` since subshells can't change parent directory
gem-local() {
  if [[ "${1:-}" == "cd" ]]; then
    shift
    local dir
    dir=$(command gem-local path "$@") || return $?
    builtin cd "$dir"
  else
    command gem-local "$@"
  fi
}

# bu - bundle
alias bua="bundle add"

bucd() {
  if [[ -z "$1" ]]; then
    echo "Usage: bucd <gem-name> [subpath]"
    return 1
  fi

  local gem_path
  gem_path=$(bundle show "$1" 2>/dev/null)

  if [[ -z "$gem_path" || ! -d "$gem_path" ]]; then
    echo "Error: Could not find gem '$1' in current bundle."
    return 1
  fi

  local target_path="$gem_path"
  if [[ -n "$2" ]]; then
    target_path="$gem_path/$2"
  fi

  if [[ -d "$target_path" ]]; then
    cd "$target_path" || return 1
  else
    echo "Error: Path '$target_path' does not exist."
    return 1
  fi
}

alias buf="bundle fund"

bug() {
  bundle gem --git --mit --test=rspec --no-ci --linter=rubocop --coc --no-changelog "$1"
  rm -rf "$1/.git"
}

alias bui="bundle install"

# ru - rubocop
# Auto fix the current dir (default) or the path passed in
rua() {
  rubocop -A "${1:-.}"
}

alias rmlsp='find . -type d -name .ruby-lsp -prune -exec rm -rf {} +'
