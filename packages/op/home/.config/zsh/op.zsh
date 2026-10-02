# 1password — shared configuration (all platforms).
#
# Credential loading belongs to fnox (see packages/fnox): a fnox.toml in a
# project or space directory declares what that directory needs, and fnox
# resolves it through this same `op` CLI.
#
# Forwarding the service account token to a remote host is the ssh hook in
# ssh/op.zsh. Creating and rotating vaults and service accounts is op-provision.

zcomp op

if [[ "$(os)" == "macos" && -z "$SSH_CLIENT" ]]; then
  export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
fi
