# ~/.bashrc — bash config assembled from package-contributed snippets (pde/bash)
#
# Two tiers, sourced in this order:
#   ~/.config/sh/*.sh        portable, shared with zsh
#   ~/.config/bash/*.bash    bash-specific
# A portable file must not rely on a helper defined in a bash-specific one at source time;
# calling one at runtime is fine (that is how ppm's _ppm_shell_reload hook works).

case $- in *i*) ;; *) return ;; esac   # interactive shells only

# XDG and ppm directories, matching pde/zsh's aliases.zsh
export XDG_CACHE_HOME=$HOME/.cache
export XDG_CONFIG_HOME=$HOME/.config
export XDG_DATA_HOME=$HOME/.local/share
export XDG_STATE_HOME=$HOME/.local/state
export BIN_DIR=$HOME/.local/bin
export LIB_DIR=$HOME/.local/lib

# Put $target first on PATH, removing any existing occurrence so repeated sourcing can't
# duplicate it. pde/zsh's .zshrc defines the same helper, so a portable ~/.config/sh/*.sh
# snippet can call it in either shell (pde/ruby-tools and pdt/solana already do from .zsh).
# Written for bash 3.2: ${v//pat/rep} and ${v:+...} are all it needs.
ensure_path() {
  local target="$1"
  # Strip target from start, middle, and end of PATH
  local clean_path=":$PATH:"
  clean_path="${clean_path//:$target:/:}"
  clean_path="${clean_path#:}"
  clean_path="${clean_path%:}"

  export PATH="$target${clean_path:+:$clean_path}"
}

# Homebrew on PATH, wherever it is installed, before $BIN_DIR is prepended so ~/.local/bin
# stays first. The base env lives here rather than in a ~/.config/bash/*.bash snippet because
# the snippet loop below needs ppm and mise to already be findable, and because shipping
# ~/.bash_profile stops bash login shells from reading the distro's ~/.profile (which is what
# puts ~/.local/bin on PATH on Debian).
#
# `brew shellenv` forks, and everything it exports but PATH survives being inherited
# ($HOMEBREW_*, INFOPATH), so it stays behind this guard and runs once per session.
if [ -z "${HOMEBREW_PREFIX:-}" ]; then
  for _brew_prefix in /opt/homebrew /home/linuxbrew/.linuxbrew; do
    if [ -x "$_brew_prefix/bin/brew" ]; then
      eval "$("$_brew_prefix/bin/brew" shellenv bash)"
      break
    fi
  done
  unset _brew_prefix
fi

# PATH is the one thing shellenv sets that does NOT survive, so re-assert it on every run, guard
# or no guard: macOS runs /usr/libexec/path_helper from /etc/profile in EVERY login shell,
# including nested ones (tmux starts one by default, as do `bash -l`, ssh to self, and an
# editor's or agent's shell), and it rebuilds PATH with the /etc/paths entries in front. A nested
# login shell inherits $HOMEBREW_PREFIX, so the guard above skips shellenv and path_helper's
# demotion would stand, leaving /bin/bash (3.2.57) ahead of the brew bash 5 this rc exists to
# bootstrap into. sbin is prepended first so bin lands ahead of it, the order shellenv produces.
if [ -n "${HOMEBREW_PREFIX:-}" ]; then
  [ -d "$HOMEBREW_PREFIX/sbin" ] && ensure_path "$HOMEBREW_PREFIX/sbin"
  [ -d "$HOMEBREW_PREFIX/bin" ] && ensure_path "$HOMEBREW_PREFIX/bin"
fi

ensure_path "$BIN_DIR"

# bash-completion, before the snippet loop: generated completion scripts (cobra-style, e.g.
# varlock's) call its _get_comp_words_by_ref, so a snippet that registers one checks for it.
# The distro's own ~/.bashrc used to load it, and pde/bash moves that file aside. Both
# profile.d scripts return early when already loaded (BASH_COMPLETION_VERSINFO), which keeps a
# reload cheap, and when bash is older than 4.2 — /bin/bash 3.2 on macOS simply goes without.
# brew's copy also loads $HOMEBREW_PREFIX/etc/bash_completion.d, where formulas put theirs.
for _bc in "${HOMEBREW_PREFIX:-/nonexistent}/etc/profile.d/bash_completion.sh" \
           /etc/profile.d/bash_completion.sh; do
  [ -r "$_bc" ] && { . "$_bc"; break; }
done
unset _bc

# The distro's bash-completion only knows /etc/bash_completion.d, so on Linux load the
# completions Homebrew formulas install. Once per shell: a reload must not re-source them.
if [ -z "${_PPM_BREW_COMPLETIONS:-}" ] && [ -n "${HOMEBREW_PREFIX:-}" ] &&
   [ -n "${BASH_COMPLETION_VERSINFO:-}" ] &&
   [ ! -r "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh" ]; then
  _PPM_BREW_COMPLETIONS=1
  for _bc in "$HOMEBREW_PREFIX"/etc/bash_completion.d/*; do
    [ -r "$_bc" ] && . "$_bc"
  done
  unset _bc
fi

# Two levels of nesting are globbed explicitly rather than with `shopt -s globstar`: macOS
# ships bash 3.2, which has no globstar. Two levels is what packages actually use
# (~/.config/zsh/op/, ssh/, ruby/).
_ppm_nullglob=$(shopt -p nullglob)
shopt -s nullglob
for _ppm_file in "$HOME"/.config/sh/*.sh "$HOME"/.config/sh/*/*.sh \
                 "$HOME"/.config/bash/*.bash "$HOME"/.config/bash/*/*.bash; do
  . "$_ppm_file"
done
eval "$_ppm_nullglob"
unset _ppm_nullglob _ppm_file
