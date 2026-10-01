# op — 1Password credentials

Installs the 1Password CLI and desktop app, points ssh at the 1Password SSH
agent, and forwards a service account token to remote hosts.


## Division of responsibility

- **fnox owns secrets.** A `fnox.toml` declares what a directory needs and
  resolves it through the `op` CLI. This package ships no per-tool wrappers.
- **This package owns the one thing fnox cannot bootstrap remotely**: getting a
  service account token onto a host so the `op` there can authenticate at all.

## Layout

```
home/.config/zsh/op.zsh          zcomp op — completions, nothing else
home/.config/zsh/ssh/op.zsh      ssh hook: forwards the token
home/.local/bin/op-provision     vault / service account lifecycle (bash)
macos/.ssh/config.d/99-op.conf   IdentityAgent -> 1Password agent socket
linux/.config/mise/conf.d/op.toml
install.sh                       sshd AcceptEnv drop-in
```

`home/.config/zsh/ssh/` is a hook directory owned by pde/ssh. Files there load
after `ssh.zsh` because `.` (0x2E) sorts before `/` (0x2F) in `.zshrc`'s
`$ZSH_CONFIG/**/*.zsh(N)` glob, so `ssh_register` always exists in time.

## Invariants — do not break these

1. **Exactly one secret crosses ssh:** `OP_SERVICE_ACCOUNT_TOKEN`. Everything
   else is declared at both ends and re-resolved remotely. Do not add a
   mechanism to forward more; that is ADR-001's rejected Option 4.
2. **`env = false` on the token.** `op` reads `OP_SERVICE_ACCOUNT_TOKEN` from the
   environment, so an exported token would override desktop auth for every local
   `op` call and would be readable by anything started in that directory. The
   hook materialises it with `fnox get` for the ssh process alone.
3. **The token is declared per directory, never globally.** The hook forwards
   whatever the current directory resolves; a global declaration forwards it
   everywhere, including to third-party hosts.
4. **`provider = "onepass"` on every secret.** A bare `{ value = "op://..." }`
   is a stored literal — fnox returns it verbatim and never calls the provider,
   even with `default_provider` set.
5. **The token never enters argv.** Not in the ssh command line (SendEnv carries
   it), not in `op item create` (piped as JSON on stdin). argv is world-readable
   via `ps`.
6. **`op-provision` runs `op` via `env -u OP_SERVICE_ACCOUNT_TOKEN`**, so it
   authenticates as the human even inside a provisioned directory.
7. **Every token item is tagged `$OP_PROVISION_TAG` and carries scope metadata
   fields.** It is the only queryable index of what has been provisioned, because
   vaults and service accounts cannot be tagged. Do not stop writing the tag or
   the fields; `list` depends on them.

## Useful facts about the tools

- `op service-account` has only `create` and `ratelimit`. No delete, no token
  reissue. Rotation means a new account; revocation goes through
  `op user delete` or the web UI.
- 1Password refuses to grant a service account access to Personal or Private.
- `op service-account create` repeats `--vault`, and supports `--expires-in`
  (available, deliberately not adopted — see ADR-001's revision).
- sshd silently discards environment variables not named in `AcceptEnv`. A
  missing `AcceptEnv` looks exactly like "no secrets configured".
- Only *items* support tags and `--tags` filtering. `op vault create` offers just
  `--description`/`--icon`, and `op vault list` filters only by
  `--group`/`--user`/`--permission`.
- `op item list --format json | op item get -` is 1Password's documented way to
  fetch many items in one call; use it rather than a loop.

## Testing

```bash
bats packages/op/tests/ssh-hook.bats
bats packages/op/tests/op-provision.bats
```

Offline, stubbed, under a second. Keep them that way — no test should require a
1Password account or the network.
