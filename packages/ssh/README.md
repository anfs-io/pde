# ssh

Installs sshfs, ships the `Include config.d/*.conf` line that lets packages drop
ssh config fragments into `~/.ssh/config.d/`, and provides the **ssh hook
registry**.

## The hook registry

Several packages want to extend `ssh`. Before this, each defined its own wrapper
or — worse — a differently-named command you had to remember to type instead of
`ssh`, which is how `sshg` worked. Competing `ssh` functions silently clobber
each other depending on load order.

So `ssh` is wrapped exactly once, here, and packages register hooks.

A package drops a file in `~/.config/zsh/ssh/`. That directory loads after
`ssh.zsh` in `.zshrc`'s `$ZSH_CONFIG/**/*.zsh(N)` glob — `.` is 0x2E and `/` is
0x2F, so `ssh.zsh` sorts first — which means `ssh_register` always exists by the
time a hook file runs.

```zsh
# ~/.config/zsh/ssh/example.zsh
(( $+functions[ssh_register] )) || return 0   # degrade quietly if pde/ssh is absent

_example_ssh_hook() {
  ssh_opts+=(-o SendEnv=EXAMPLE)
  ssh_env+=("EXAMPLE=$(compute-it)")
  ssh_cleanup+=(_example_restore)
}

ssh_register _example_ssh_hook
```

### The contract

A hook is called with ssh's own arguments and may append to three arrays. They
are locals of `ssh()`; zsh's dynamic scoping is what lets a hook reach them.

| | |
|---|---|
| `ssh_opts` | extra ssh options, prepended to the command line |
| `ssh_env` | `VAR=value` pairs exported for the ssh process only |
| `ssh_cleanup` | function names run after the connection closes, in reverse registration order |

Two helpers:

| | |
|---|---|
| `ssh_target "$@"` | the resolved hostname, via a memoised single `ssh -G` |
| `ssh_host_arg "$@"` | the host **as typed**, skipping options and their values |

Use `ssh_host_arg` to match on host aliases and `ssh_target` when you need the
real address.

Returning non-zero from a hook **aborts the connection** and ssh never runs; its
status becomes ssh's. A hook with nothing to contribute returns 0 and appends
nothing. Hooks should not abort for "there is nothing to do here" — a hook that
cannot do its job should generally warn and return 0, so a broken hook never
makes `ssh` unusable.

`ssh --no-op <host>` skips every hook for one invocation.

### Chaining

`ssh.zsh` captures any pre-existing `ssh` function into `_ssh_next` and calls
that rather than `command ssh`. This matters: Ghostty's shell integration defines
its own `ssh()` when `shell-integration-features` includes `ssh-*`, and it
installs `xterm-ghostty` terminfo on the remote. Bypassing it with `command ssh`
reintroduces broken displays on every remote host.

The capture is guarded against re-sourcing, and `ssh_register` is idempotent, so
`zsrc` does not produce infinite recursion or duplicate hooks.

### Known registrants

| Package | Hook |
|---|---|
| pde/op | forwards `OP_SERVICE_ACCOUNT_TOKEN` to the remote |
| pde/ghostty | per-host background colour and tab title |

## Other contents

- `sshfs` — mount and unmount remote directories at `$HOME/mnt/host`:
  `ssh_mount host path`, `ssh_umount host`
- `install.sh` — optionally fetches `$HOME/.ssh/authorized_keys`:
  `PPM_SSH_AUTHORIZED_KEYS_URL=https://github.com/USER.keys ppm install ssh`
