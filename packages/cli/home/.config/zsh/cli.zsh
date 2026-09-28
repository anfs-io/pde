# cli.zsh — zsh-only config for pde/cli's tools (the portable part is .config/sh/cli.sh)

# key bindings (ctrl-r, ctrl-t) and completion; this must be sourced, it is not a fpath completion file
(( $+commands[fzf] )) && source <(fzf --zsh)
