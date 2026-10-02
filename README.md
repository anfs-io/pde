
# PDE - Personal Development Environment

## Usage

An [anfs](https://github.com/anfs-io/system) source (`packages/`), in anfs's default
`system.list`. wsm, which used to live here, is part of anfs now.

```bash
anfs src add https://github.com/anfs-io/pde pde   # only if it is not already listed
ppm list pde
ppm install [PACKAGE]
```

## Common Packages

```bash
ppm install zsh git nvim tmux
```

### Shortcut to install all packages

```bash
ppm install pde/
```


### Chorus

Installs the latest neovim and adds many common plugins along with a sensible configuration

### Claude

Installs the latest claude code via mise. claude code depends on Node

### Cli

The command-line toolset every shell gets (bat, fzf, htop, tree) with its config: `PAGER=bat`,
fzf key bindings for bash and zsh, `tsa`/`bata`, `ip_addr` and a vi-mode `.inputrc`. `bash` and
`zsh` both depend on it, so the tools are the same whichever shell is installed.

### Git

Installs a systemwide .gitignore and a few zsh aliases

### Mise

mise is part of anfs's base install (install.sh brews it); packages declare the tools they want
in `home/.config/mise/conf.d/<tool>.toml`. Node is `anfs/node`.

### Nvim

Installs the latest neovim and adds many common plugins along with a sensible configuration

### Op

Installs the 1Password CLI and desktop app, points ssh at the 1Password SSH agent so private
keys stay off the filesystem, and forwards a service account token to remote hosts so the `op`
there can authenticate. Secrets themselves are declared in fnox; `op-provision` creates and
rotates the vaults and service accounts. See `packages/op/README.md`.

```bash
op-provision create lgat          # vault + service account + token
cd ~/spaces/lgat && op-provision link lgat
ssh vm1                           # credentials follow you to the remote
```

### SSH

- Provides the ssh hook registry: `ssh` is wrapped once here and packages register hooks with it
  by dropping a file in `~/.config/zsh/ssh/`, rather than each defining a competing wrapper or a
  separate command you have to remember to type. See `packages/ssh/README.md`.
- Installs sshfs on linux and macfuse+sshfs-mac on mac to enable mounting directories on remote hosts via ssh
-  to pull a keys file to `$HOME/.ssh/authorizied_keys`:
```bash
PPM_SSH_AUTHORIZED_KEYS_URL=https://github.com/[USERNAME].keys ppm install ssh
```
- mount/unmount remote host directories at `$HOME/mnt/host`
```bash
ssh_mount host path
ssh_umount host
```

### Tmux

Terminal Multiplexer and the ruby gem tmuxinator to set common window configurations for projects

### Zsh

Installs oh-my-zsh and powerlevel10k on top of the basic z shell. Also installs several zsh scripts to add cli shortcuts for common actions
