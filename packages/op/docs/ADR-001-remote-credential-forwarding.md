# ADR-001: Remote Credential Forwarding via 1Password Service Accounts

**Status:** Accepted  
**Date:** 2026-02-09  
**Authors:** Roberto

## Context

We need a way to use CLI tools (`gh`, `aws`, `gcloud`, etc.) on remote Linux hosts without storing credentials on disk. The requirements are:

1. No plaintext secrets written to remote filesystems
2. Centralized credential management with easy revocation
3. Environment isolation (development, staging, production)
4. Minimal friction for day-to-day use
5. Must work over standard SSH connections

We are preparing to go live with production infrastructure (Proxmox, etc.) and need the credential discipline in place before production secrets exist.

## Options considered

### Option 1: 1Password Shell Plugins on each host

Each remote host authenticates independently with 1Password using biometric or interactive login.

**Rejected:** Biometric auth is not available on headless Linux hosts. Interactive login requires a full 1Password account on each machine.

### Option 2: Forward 1Password agent socket over SSH

Similar to SSH agent forwarding, forward the 1Password Unix socket to the remote host.

**Rejected:** The `op` CLI does not use a socket-based protocol suitable for forwarding. This is not officially supported by 1Password.

### Option 3: SSH protocol for git + one-time token injection

Use SSH agent forwarding for git operations, manually inject tokens for API calls via `gh auth login --with-token`.

**Rejected:** Writes the token to `~/.config/gh/hosts.yml` on disk. Doesn't generalize to other tools (AWS, GCP, etc.).

### Option 4: Inject credentials as env vars per SSH session

Export each credential individually from the Mac into the remote shell session.

**Rejected:** Doesn't scale — requires maintaining a growing list of secrets in the SSH wrapper. Each new tool requires modifying the wrapper.

### Option 5: 1Password Service Accounts (selected)

Create a 1Password Service Account with read-only access to environment-specific vaults. Forward a single SA token to the remote host. The remote `op` CLI uses this token to fetch individual credentials on demand.

## Decision

We chose Option 5: 1Password Service Accounts. The approach:

1. **One SA token** is injected into the remote session (via `rssh` wrapper)
2. **Tool wrappers** (`gh`, `aws`, etc.) lazily call `op read` on first invocation
3. **Credentials are cached in env vars** for the session duration — fetched once, reused
4. **SA tokens are cached in macOS Keychain** to avoid repeated `op read` calls on the Mac
5. **Vault naming convention** `SA - <env>` applies to both the vault and the SA credential item

### Vault architecture

```
Admin vault ($OP_SA_CREDENTIALS_VAULT)
  └── SA - development          # SA token (meta-credential)
  └── SA - staging
  └── SA - production

SA - development                # Environment vault (SA has read-only access)
  └── GitHub CLI Token
  └── AWS
  └── ...
```

The SA tokens live in a separate admin vault, not in the environment vaults they grant access to. This avoids circular dependencies and limits the SA's access to only the secrets it needs to serve.

### Platform separation

Shell functions are split across platform-specific directories managed by ppm (PPM_GROUP_ID):

- `home/` — shared functions (`_op_env`, tool wrappers, opcreds aliases)
- `macos/` — keychain caching, `rssh`
- `linux/` — (currently empty, shared functions cover remote host needs)

This eliminates alias/function conflicts between 1Password desktop plugins and our tool wrappers.

## Consequences

### Positive

- No secrets on disk on any remote host
- Single point of revocation per environment (revoke SA token → all access stops)
- Adding new tools is a 3-line wrapper function
- Environment isolation is enforced by vault boundaries
- Keychain caching makes `rssh` fast after first use
- Fully supported by 1Password (Service Accounts are a first-class feature)

### Negative

- Credentials are visible in process environment on the remote host during the session
- SA token in env grants read access to all items in the environment vault
- Requires a 1Password Teams or Business plan for Service Accounts
- Additional dependency on `op` CLI being installed on remote hosts
- Keychain cache must be manually cleared when SA tokens are rotated

### Risks

- If a remote host is compromised while a session is active, the attacker gets the SA token and can read all secrets in that environment's vault until the token is revoked
- Mitigation: read-only access, vault isolation per environment, centralized revocation

## Future considerations

- Evaluate HCP Vault or similar solutions for production environments with stricter security requirements
- Consider short-lived SA tokens if 1Password adds support for token expiration
- SSH config `SetEnv`/`AcceptEnv` for per-host vault mapping when multiple environments are in regular use

---

## Revision 2026-09: fnox replaces the hand-rolled implementation

**Status:** The decision above — Option 5, service accounts — stands. The
implementation it describes is superseded.

### What prompted this

The implementation had stopped working, and it is worth recording why, because
the failure was invisible. `_op_env()` and `zssh` derived the vault name from
`$OP_SPACE` or `$CHORUS_SPACE`. Nothing in the shipped system ever set either:
the `.mise.toml` files that `op.zsh` claimed would set them did not exist in any
space, and `CHORUS_SPACE` appeared only in the chorus gem's planning documents.
Both functions therefore failed on every invocation while continuing to load in
every shell. The documented `SA - <env>` vault convention had also drifted from
the `<space>-<area>` naming the code actually built.

The lesson worth keeping: **credential plumbing that derives its configuration
from ambient environment variables fails silently when nothing sets them.** The
replacement derives nothing; configuration is a file whose presence is the
signal.

### What changed

- **fnox owns credential loading.** `_op_env()`, the lazy `gh`/`aws` wrappers,
  and `_op_space`/`_op_area`/`_op_vault` are deleted. fnox's `1password`
  provider shells out to the same `op` CLI, so the trust model is unchanged;
  only the plumbing moved. Adding a credential is now a line of TOML rather than
  a new shell function.
- **Configuration is layered by directory.** `~/.config/fnox/config.toml` for
  cross-cutting secrets, a `fnox.toml` in any project or space directory for
  that scope; both load and the directory file wins. This replaces the derived
  `<space>-<area>` vault name with an explicit declaration whose location *is*
  the scope.
- **Keychain caching dropped.** The fnox daemon's cache replaces `_op_sa_token`.
  This retires the consequence listed above: "Keychain cache must be manually
  cleared when SA tokens are rotated." The token secret sets
  `daemon_cache = false`, so a rotation takes effect immediately.
- **`zssh` is gone; plain `ssh` carries the token.** pde/ssh now provides a
  single `ssh` wrapper that packages register hooks with; pde/op registers one
  that forwards the token, and pde/ghostty registers the per-host theming that
  used to require typing `sshg`. A wrapper command only helps when you remember
  to type it, which is a poor property for a security control.
- **Transport is `SendEnv`, not an interpolated remote command.** This closes a
  real hole. The previous implementation built
  `ssh -t host "export OP_SERVICE_ACCOUNT_TOKEN='$tok'; exec \$SHELL -l"`, so a
  token containing a single quote was arbitrary remote code execution. The token
  now never enters a string that a shell will parse, and never enters argv,
  where `ps` would expose it. Dropping the remote command also made
  `ssh host <command>` work, which the wrapper had silently discarded.
- **`SendEnv` is passed per invocation, not configured.** Putting
  `SendEnv OP_SERVICE_ACCOUNT_TOKEN` under `Host *` would transmit the token to
  every host, including github.com on every push. The hook adds `-o` only when
  the current directory resolves a token.
- **The token is `env = false`.** It is never in any shell environment. This
  matters more than it did when this ADR was written: editors, language servers
  and coding agents are routinely started from project directories and inherit
  whatever is exported there.
- **Vault layout: shared plus per-scope.** Each service account is granted
  `--vault <scope>:read_items --vault <shared>:read_items`, so one token covers
  a scope's secrets and the cross-cutting ones. The `SA - <env>` naming
  convention in the Decision section is retired; scopes are named for what they
  serve. Note 1Password refuses to grant a service account access to Personal or
  Private, so scope vaults must be regular shared vaults.
- **Provisioning is a guided script**, `op-provision`, rather than shell
  functions: create, status, rotate, destroy, link.

### Deferred: short-lived tokens

"Future considerations" above anticipated token expiry, and 1Password has since
shipped it — `op service-account create --expires-in 24h`. Not adopted yet. With
`env = false` the token is materialised on demand rather than held in a session,
so the exposure window is already small, and expiry would mean re-running
provisioning on a schedule. Revisit when rotation can run unattended.

Worth noting for whoever picks that up: 1Password cannot reissue a token for an
existing service account, and `op` has no `service-account delete`. Rotation is
therefore create-new-then-revoke-old, and revocation goes through `op user
delete` or the web console.

### Also delivered from "Future considerations"

`SSH config SetEnv/AcceptEnv for per-host vault mapping` — `AcceptEnv` is now in
use on the server side. Scoping turned out to belong to the *directory* (via
fnox config layering) rather than the host, which is a better fit: the same host
is often used from several scopes.
