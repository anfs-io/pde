# ruby.bash — the portable part is .config/sh/ruby.sh

# Only function definitions and a `complete`, so re-sourcing on _ppm_shell_reload is harmless
command -v gem-local >/dev/null 2>&1 && eval "$(command gem-local completion bash)"
