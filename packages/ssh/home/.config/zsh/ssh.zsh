# ssh — dispatcher for package-provided ssh hooks.
#
# Wrapping `ssh` once, here, lets any package extend it without each one
# defining its own competing `ssh` function. Packages drop a file in
# ~/.config/zsh/ssh/ that registers a hook; that directory sorts after this
# file in .zshrc's `$ZSH_CONFIG/**/*.zsh(N)` glob ('.' is 0x2E, '/' is 0x2F),
# so ssh_register always exists by the time a hook file runs.
#
# A hook is called with ssh's own arguments and may append to three arrays.
# They are locals of ssh() below; zsh's dynamic scoping is what lets a hook
# see and modify them:
#
#   ssh_opts     extra ssh options, e.g. ssh_opts+=(-o SendEnv=FOO)
#   ssh_env      VAR=value pairs exported for the ssh process only
#   ssh_cleanup  function names run after the connection closes, in reverse
#                registration order
#
# Returning non-zero from a hook aborts the connection without running ssh.
# A hook that has nothing to contribute returns 0 and appends nothing.
#
# Call `ssh_target "$@"` for the resolved hostname; it memoises a single
# `ssh -G` lookup and shares it across hooks for this invocation.
#
# `ssh --no-op` skips every hook and runs ssh unmodified.

typeset -ga ssh_wrapper_functions

# Idempotent: `zsrc` re-sources every snippet, and a hook must not register twice.
ssh_register() {
  typeset -ga ssh_wrapper_functions
  local f
  for f in "$@"; do
    (( ${ssh_wrapper_functions[(Ie)$f]} )) || ssh_wrapper_functions+=("$f")
  done
}

# Capture whatever `ssh` already exists so we extend it rather than replace it.
# Ghostty's shell integration defines an ssh() when shell-integration-features
# includes ssh-* ; it installs xterm-ghostty terminfo on the remote and adds its
# own -o SetEnv/SendEnv. Calling `command ssh` instead of chaining would silently
# break remote terminfo.
#
# Guarded so that re-sourcing this file does not capture our own wrapper and
# recurse forever.
if (( ! $+functions[_ssh_next] )); then
  if (( $+functions[ssh] )); then
    functions[_ssh_next]=$functions[ssh]
  else
    _ssh_next() { command ssh "$@" }
  fi
fi

ssh() {
  emulate -L zsh
  local -a ssh_opts ssh_env ssh_cleanup
  local ssh_target_cached hook ret

  # --no-op is consumed here and never reaches ssh. Note this strips the token
  # anywhere in the line, including inside a remote command.
  local -a args=("${(@)argv:#--no-op}")
  local -i skip=${argv[(Ie)--no-op]}

  if (( $#args && ! skip )); then
    for hook in $ssh_wrapper_functions; do
      $hook "${args[@]}" || return $?
    done
  fi

  if (( $#ssh_env )); then
    # A subshell, not `env`: _ssh_next may be a shell function (Ghostty's), and
    # `env` can only exec an external command.
    ( export "${ssh_env[@]}"; _ssh_next "${ssh_opts[@]}" "${args[@]}" )
  else
    _ssh_next "${ssh_opts[@]}" "${args[@]}"
  fi
  ret=$?

  for hook in ${(Oa)ssh_cleanup}; do $hook; done
  return $ret
}

# Resolved hostname for this invocation, memoised into ssh()'s local.
ssh_target() {
  [[ -n $ssh_target_cached ]] && { print -r -- $ssh_target_cached; return 0 }
  ssh_target_cached=$(command ssh -G "$@" 2>/dev/null | awk '$1=="hostname"{print $2; exit}')
  print -r -- $ssh_target_cached
}

# The host as typed on the command line: the first non-option argument, skipping
# options and their values. `ssh -J bastion vm1 uptime` -> vm1.
# Hooks that match on host aliases want this; hooks that need the real hostname
# want ssh_target.
ssh_host_arg() {
  emulate -L zsh
  local -r withval='bcDEeFIiJLlmOopQRSWw'   # ssh options that consume a value
  while (( $# )); do
    case $1 in
      --) shift; break ;;
      -[$withval]) shift 2; continue ;;     # -o Foo=bar
      -[$withval]*) shift; continue ;;      # -oFoo=bar
      -*) shift; continue ;;                # valueless flag, possibly bundled
      *) break ;;
    esac
  done
  (( $# )) && print -r -- "${1#*@}"          # strip user@
}
