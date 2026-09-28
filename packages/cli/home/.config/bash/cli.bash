# cli.bash — bash-only config for pde/cli's tools (the portable part is .config/sh/cli.sh)

# key bindings (ctrl-r, ctrl-t) and completion
command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"
