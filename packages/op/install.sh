# op

# The service account token reaches a remote host as an environment variable carried by the
# SSH protocol: `ssh -o SendEnv=OP_SERVICE_ACCOUNT_TOKEN`, sent by the ssh hook this package
# installs. sshd discards any variable it has not been told to accept, and says nothing when it
# does — a host missing this looks exactly like "no secrets configured" — so the matching
# AcceptEnv is written here.
#
# /etc/ssh is root-owned, so this cannot be stowed. Same shape as pde/bash registering brew's
# bash in /etc/shells, and handled the same way: grep first so a settled host never prompts,
# _system_sudo to prime the credential cache, then `sudo -n` so an unattended install cannot block.
#
# Not gated on the OS. macOS ships sshd with Include /etc/ssh/sshd_config.d/* too, and a Mac can
# be the host you ssh into; gating on "linux" would encode one person's workflow rather than a
# real platform difference. It is gated on sshd actually running, so a machine that is only ever
# an ssh client is left alone and never prompts for sudo.
_OP_SSHD_DROPIN=/etc/ssh/sshd_config.d/50-ppm-op.conf
_OP_ACCEPT_ENV='AcceptEnv OP_SERVICE_ACCOUNT_TOKEN'

post_install() {
  _op_sshd_accept_env
}

# This host answers ssh, so the AcceptEnv is worth writing.
_op_sshd_is_server() {
  command -v sshd >/dev/null 2>&1 || return 1
  pgrep -x sshd >/dev/null 2>&1 && return 0
  systemctl is-enabled --quiet ssh 2>/dev/null && return 0
  systemctl is-enabled --quiet sshd 2>/dev/null && return 0
  return 1
}

_op_sshd_accept_env() {
  [[ -n "${PPM_OP_SKIP_SSHD:-}" ]] && return 0
  _op_sshd_is_server || return 0

  # Settled: no sudo, no prompt, no reload.
  grep -qxF "$_OP_ACCEPT_ENV" "$_OP_SSHD_DROPIN" 2>/dev/null && return 0

  # Debian 11 and older ship no Include line, so a drop-in would sit there doing nothing.
  # Say so rather than writing a file that silently has no effect.
  if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config 2>/dev/null; then
    user_message "This sshd does not Include /etc/ssh/sshd_config.d/.\nAdd to /etc/ssh/sshd_config by hand:\n  $_OP_ACCEPT_ENV\nthen: sudo sshd -t && sudo systemctl reload ssh"
    return 0
  fi

  if ! _system_sudo "$_OP_ACCEPT_ENV" \
      "Forwarding the 1Password service account token needs sudo. Run:\n  printf '%s\\n' '$_OP_ACCEPT_ENV' | sudo tee $_OP_SSHD_DROPIN\n  sudo sshd -t && sudo systemctl reload ssh"
  then
    return 0
  fi

  printf '# ppm pde/op: accept the service account token forwarded by the ssh hook\n%s\n' "$_OP_ACCEPT_ENV" \
    | sudo -n tee "$_OP_SSHD_DROPIN" >/dev/null || { user_message "Could not write $_OP_SSHD_DROPIN"; return 0; }
  sudo -n chmod 0644 "$_OP_SSHD_DROPIN" 2>/dev/null

  # Validate before reloading. This host is quite possibly only reachable over ssh, so a drop-in
  # that fails validation must not be left where the next sshd restart would find it.
  if ! sudo -n sshd -t 2>/dev/null; then
    sudo -n rm -f "$_OP_SSHD_DROPIN"
    user_message "sshd rejected $_OP_SSHD_DROPIN; reverted, nothing changed"
    return 0
  fi

  # reload, not restart: established sessions — including the one running this — survive.
  sudo -n systemctl reload ssh 2>/dev/null \
    || sudo -n systemctl reload sshd 2>/dev/null \
    || user_message "Wrote $_OP_SSHD_DROPIN. Reload sshd to apply it: sudo systemctl reload ssh"
}

# Root-owned and machine-wide, so it is left in place and explained rather than removed silently —
# the same call pde/bash makes about its /etc/shells line.
post_remove() {
  [[ -f "$_OP_SSHD_DROPIN" ]] || return 0
  user_message "Left $_OP_SSHD_DROPIN in place.\nTo remove it: sudo rm $_OP_SSHD_DROPIN && sudo systemctl reload ssh"
}
