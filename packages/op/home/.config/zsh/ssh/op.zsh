# Forward the 1Password service account token to the remote host.
#
# Registers with the ssh dispatcher in packages/ssh, so plain `ssh` carries the
# token — there is no separate command to remember, and sshg/scp/anything else
# routed through that wrapper gets it too.
#
# The hook fires only when a fnox config applying to the current directory
# declares OP_SERVICE_ACCOUNT_TOKEN. That is deliberately a per-directory
# declaration and not a global one: if it were global it would resolve from
# anywhere and every `ssh` — including to github.com — would offer your token.
#
# The token is declared `env = false`, so it is not in this shell's environment
# and nothing started from this directory (editor, language server, coding
# agent) can read it. It is materialised here, exported into the ssh process
# alone, and handed to the server by the SSH protocol via SendEnv. It never
# appears in argv, so it is not visible in `ps`.
#
# The remote sshd needs `AcceptEnv OP_SERVICE_ACCOUNT_TOKEN`, written by this
# package's install.sh. Without it sshd drops the variable and says nothing.

(( $+functions[ssh_register] )) || return 0   # pde/ssh not installed

_op_ssh_hook() {
  (( $+commands[fnox] || $+functions[fnox] )) || return 0

  local token
  if token=$(fnox get OP_SERVICE_ACCOUNT_TOKEN 2>/dev/null) && [[ -n $token ]]; then
    ssh_env+=("OP_SERVICE_ACCOUNT_TOKEN=$token")
    ssh_opts+=(-o SendEnv=OP_SERVICE_ACCOUNT_TOKEN)
    return 0
  fi

  # Resolution failed. If no config declares the key this is simply an
  # unprovisioned directory and silence is right; if one does, something is
  # wrong (1Password locked, signed out) and you should hear about it before
  # you land on a host with no credentials. Either way we still connect.
  if fnox list 2>/dev/null | awk '{print $1}' | grep -qx OP_SERVICE_ACCOUNT_TOKEN; then
    print -ru2 -- "ssh: op: could not resolve OP_SERVICE_ACCOUNT_TOKEN; connecting without it"
    print -ru2 -- "         check: op whoami"
  fi
  return 0
}

ssh_register _op_ssh_hook
