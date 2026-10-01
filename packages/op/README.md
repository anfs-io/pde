# op — 1Password credentials for local and remote work

This package installs the 1Password CLI and desktop app, points ssh at the
1Password SSH agent, and does the one thing fnox cannot do on its own: get a
service account token to a remote host so the `op` CLI there can authenticate.

**Secrets themselves are fnox's job.** A `fnox.toml` in a project or space
directory declares what that directory needs; fnox resolves it through this same
`op` CLI. There are no per-tool wrapper functions here.

## How it works

```
Mac, inside a provisioned directory
  │
  │  ssh vm1
  │    └── ssh hook: fnox get OP_SERVICE_ACCOUNT_TOKEN   (env = false:
  │          materialised for the ssh process only, never in your shell)
  │        ssh -o SendEnv=OP_SERVICE_ACCOUNT_TOKEN vm1
  │
  ▼
vm1  (sshd: AcceptEnv OP_SERVICE_ACCOUNT_TOKEN)
  │
  └── fnox reads the same fnox.toml keys and resolves each one with `op`,
      authenticating with the forwarded token
```

Exactly one secret crosses the connection: the service account token. Everything
else is declared identically at both ends and re-resolved on the far side, so
adding a credential never means touching the ssh path.

## Prerequisites

- 1Password desktop app, with **Settings → Developer → Integrate with 1Password
  CLI** enabled. `op whoami` must print an account.
- A 1Password plan with service accounts (Teams or Business).
- `jq`, for `op-provision`.

## Vault layout

```
Private          service account token items          (you read these; an SA never does)
shared           cross-cutting secrets, e.g. github   (every SA gets read on this)
lgat             one scope's secrets                  (only lgat's SA reads this)
```

1Password **refuses to grant a service account access to Personal or Private**,
so any vault an SA must read has to be a regular shared vault. The token *items*
may live in Private, because you read those with desktop authentication.

Each service account is granted read on its own vault plus the shared vault, so
a single forwarded token covers both a scope's secrets and the cross-cutting
ones without a second token.

## Setting up a scope

```bash
export OP_SA_CREDENTIALS_VAULT=Private   # where token items are saved
export OP_SHARED_VAULT=shared            # cross-cutting vault

op-provision create lgat          # vault + service account + token item
cd ~/spaces/lgat
op-provision link lgat            # writes ./fnox.toml
ssh vm1                           # token forwarded from here
```

`op-provision` has three input modes, because this is infrequent and
security-sensitive work:

| Mode | Behaviour |
|---|---|
| `--wizard` | walks through each decision and explains the tradeoff |
| `--prompt` | asks only for values not given as flags |
| *(neither)* | strict: a missing value is an error naming the flag |

All three print a plan and confirm before touching 1Password. `--yes` skips the
confirmation, `--dry-run` prints the plan and exits.

| Command | |
|---|---|
| `op-provision list` | every scope this tool has provisioned |
| `op-provision create <name>` | vault, service account, token item |
| `op-provision status <name>` | what exists today |
| `op-provision rotate <name>` | new account and token, then revoke the old |
| `op-provision destroy <name>` | remove token item, account and vault |
| `op-provision link <name>` | write `./fnox.toml` for this directory |

`--json` gives `list` machine-readable output.

### Finding what you have provisioned

```
$ op-provision list
SCOPE   SHARED  SERVICE ACCOUNT         TOKEN ITEM       TOKEN VAULT  PROVISIONED
lgat    shared  lgat-sa-20260922120000  lgat-sa-token    Private      2026-09-22
rws     shared  rws-sa                  rws-sa-token     Private      2026-09-20
```

**1Password cannot tag a vault** — `op vault create` takes only `--description`
and `--icon` — and service accounts are account members, which cannot be tagged
either. Only *items* support tags and server-side tag filtering.

So the token item is the index. Every one this tool writes is tagged
`op-provision` (override with `$OP_PROVISION_TAG`) plus the scope name, and
carries the scope, shared vault, service account name and provisioning date as
fields. `list` is therefore two calls no matter how many scopes exist:
`op item list --tags` then `op item get -`, which takes the whole list on stdin.

Vaults are stamped with a description instead, so they are recognisable in the
1Password UI, but they are not searchable by it. A scope's own vault is named
after the scope; `TOKEN VAULT` is where that scope's *token item* lives.

You can use the tags directly too:

```bash
op item list --tags op-provision            # every provisioned scope
op item list --tags lgat                    # one scope
op vault list                               # all vaults (no filtering available)
```

An item created by hand, before this convention, still appears in `list` if you
tag it; without the metadata fields the unknown columns show `-` and the scope
is recovered from the item title.

### On rotation and revocation

1Password cannot issue a second token for an existing service account, so a
rotation is necessarily a *new* account. `rotate` creates it and stores its token
over the old item **before** revoking the old account, so a failure midway leaves
you with working credentials rather than none. Any `fnox.toml` pointing at that
item picks up the new token with no config change.

There is no `op service-account delete`; service accounts are account members, so
revocation goes through `op user delete`. If your account does not permit that
from the CLI, `op-provision` says so and points you at
**my.1password.com → Developer → Service Accounts**. Until you complete it, the
old token still grants read access.

## fnox configuration

Global, in `~/.config/fnox/config.toml` — cross-cutting secrets:

```toml
default_provider = "onepass"

[providers.onepass]
type = "1password"

[secrets]
GH_TOKEN = { provider = "onepass", value = "op://shared/github/token", env = "exec" }
```

Per directory, in `fnox.toml` — written by `op-provision link`:

```toml
[providers.onepass]
type  = "1password"
vault = "lgat"

[secrets]
OP_SERVICE_ACCOUNT_TOKEN = { provider = "onepass", value = "op://Private/lgat-sa-token/credential", env = false }
DATABASE_URL             = { provider = "onepass", value = "postgres/url", env = "exec" }
```

Both files load; the directory file wins on a key collision. `fnox config-files`
shows what applies where.

Three details are load-bearing:

- **`provider = "onepass"` must be named on every secret.** A bare
  `{ value = "op://..." }` is a *stored literal*: fnox returns the string
  verbatim and never consults a provider, even with `default_provider` set.
  `fnox list` shows the difference — `provider (onepass)` versus `stored value`.
- **`OP_SERVICE_ACCOUNT_TOKEN` belongs in a directory config, never the global
  one.** The ssh hook forwards whatever the current directory resolves; declared
  globally, it would be forwarded from everywhere, including to github.com.
- **`env = false` on the token, `env = "exec"` on the rest.** `env = false`
  keeps the token out of your environment entirely, so nothing started in that
  directory — editor, language server, coding agent — can read it; the hook
  fetches it with `fnox get` for the ssh process alone. `env = "exec"` keeps
  other secrets out of the ambient environment too, and out of fnox's
  `precmd`/`chpwd` hook, which would otherwise resolve them on every `cd`.

## Remote hosts

```bash
ppm install op fnox ssh
```

`op` comes from mise on Linux, `fnox` from mise everywhere. The package's
`install.sh` writes `/etc/ssh/sshd_config.d/50-ppm-op.conf` with
`AcceptEnv OP_SERVICE_ACCOUNT_TOKEN`, validates with `sshd -t`, reverts if
validation fails, and reloads rather than restarts so the session running it
survives. It only does this on a host where sshd is actually running, so a
workstation that is only ever an ssh client is left alone.

Give the remote the same `fnox.toml` keys — the same file works on both ends,
because fnox authenticates through `op`, which uses the desktop app locally and
the forwarded token remotely.

## Security model

- The token is **never in your environment** (`env = false`) and **never in
  argv**, so it is not visible in `ps` and no sibling process can read it.
- It is carried by the SSH protocol, not interpolated into a remote command.
- **No `SendEnv` in ssh_config** — the hook passes `-o` per invocation, so the
  token is only ever offered to a host you ssh to *from a provisioned directory*.
- Service accounts are read-only and vault-scoped; revoking one stops that
  scope's access everywhere at once.
- Unchanged from before: while a session is live, the token is in the remote
  process environment and readable by that user.

## Files

| | |
|---|---|
| `home/.config/zsh/op.zsh` | `op` completions |
| `home/.config/zsh/ssh/op.zsh` | the ssh hook that forwards the token |
| `home/.local/bin/op-provision` | vault and service account lifecycle |
| `macos/.ssh/config.d/99-op.conf` | `IdentityAgent` → 1Password SSH agent |
| `linux/.config/mise/conf.d/op.toml` | installs `op` on Linux |
| `install.sh` | the sshd `AcceptEnv` drop-in |

## Testing

```bash
bats packages/op/tests/ssh-hook.bats      # dispatcher + token hook
bats packages/op/tests/op-provision.bats  # provisioning, stubbed op
```

Both run offline in under a second; nothing touches 1Password or the network.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `op whoami` says not signed in | enable Settings → Developer → Integrate with 1Password CLI |
| remote `printenv OP_SERVICE_ACCOUNT_TOKEN` is empty | `AcceptEnv` missing; check `sudo sshd -T \| grep -i acceptenv` on the remote. sshd drops unaccepted variables silently |
| `fnox get` returns `op://...` instead of the secret | the secret is missing `provider = "onepass"` |
| Touch ID prompts on every `cd` | a secret is missing `env = "exec"` |
| the token is forwarded from directories it should not be | it is declared in the global config; move it to a `fnox.toml` |
| `ssh` should not forward this time | `ssh --no-op <host>` |
| which config applies here? | `fnox config-files` |

## History

The shell functions this package used to ship — `_op_env`, lazy `gh`/`aws`
wrappers, `zssh`, macOS Keychain token caching — are gone. They derived the vault
name from `$OP_SPACE`/`$CHORUS_SPACE`, which nothing in the shipped system ever
set, so they could not succeed. See `docs/ADR-001-remote-credential-forwarding.md`
for the original decision and the revision that replaced its implementation.
