# Per-host background colour and tab title on ssh.
#
# Registers with the ssh dispatcher in pde/ssh, so plain `ssh` is themed. This
# replaces the old sshg() wrapper, whose weakness was that it only worked when
# you remembered to type sshg instead of ssh.
#
# Host → colour/title rules live in a profiles file so they can be changed
# without touching this code. See sshg-profiles.conf; override the path with
# $GHOSTTY_SSHG_PROFILES.

(( $+functions[ssh_register] )) || return 0   # pde/ssh not installed

_ghostty_ssh_hook() {
  emulate -L zsh
  setopt local_options extended_glob

  # The host as typed, so profile globs keep matching aliases rather than the
  # resolved address. The old sshg used "${@: -1}", which matched the remote
  # command instead of the host for `sshg vm1 uptime`.
  local host
  host=$(ssh_host_arg "$@") || return 0
  [[ -n $host ]] || return 0

  local profiles="${GHOSTTY_SSHG_PROFILES:-${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/sshg-profiles.conf}"

  # Defaults when no profile matches (preserves the original "other servers" look)
  local bg='#001a33'
  local title='🖥 %h'
  local hl="${host:l}"

  if [[ -r "$profiles" ]]; then
    local pattern color label
    while IFS='|' read -r pattern color label; do
      pattern="${${pattern##[[:space:]]#}%%[[:space:]]#}"
      [[ -z "$pattern" || "$pattern" == '#'* ]] && continue
      color="${${color##[[:space:]]#}%%[[:space:]]#}"
      label="${${label##[[:space:]]#}%%[[:space:]]#}"
      if [[ "$hl" == ${~pattern} ]]; then
        [[ -n "$color" ]] && bg="$color"
        [[ -n "$label" ]] && title="$label"
        break
      fi
    done < "$profiles"
  fi

  set_bg "$bg"
  tab_title "${title//\%h/$host}"
  ssh_cleanup+=(_ghostty_ssh_restore)
}

_ghostty_ssh_restore() {
  reset_colors
  tab_title "${PWD##*/}"
}

ssh_register _ghostty_ssh_hook
