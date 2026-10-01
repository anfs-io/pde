#!/usr/bin/env bats
# The ssh dispatcher (pde/ssh) and this package's token-forwarding hook.
# Everything is stubbed: no network, no 1Password, no real ssh.
# Run: bats packages/op/tests/ssh-hook.bats

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."
  SSH_ZSH="$REPO/packages/ssh/home/.config/zsh/ssh.zsh"
  OP_HOOK="$REPO/packages/op/home/.config/zsh/ssh/op.zsh"
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  ARGV="$BATS_TEST_TMPDIR/argv"
  ENVF="$BATS_TEST_TMPDIR/env"
}

# $1 = token fnox should return, or "" for "declared but unresolvable",
#      or "undeclared" for a directory with no such secret
#
# The token is passed through a file, never interpolated into the stub's source:
# one of the tests below feeds in a shell-injection payload, and a stub built by
# string substitution would execute it itself and report a false failure.
make_fnox() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/token"
  cat > "$STUB/fnox" <<'EOF'
#!/usr/bin/env bash
tok=$(cat "$BATS_TEST_TMPDIR/token")
case "$1" in
  get)  [[ -z "$tok" || "$tok" == undeclared ]] && exit 1; printf '%s' "$tok"; exit 0 ;;
  list) if [[ "$tok" == undeclared ]]; then printf ' Key\n SOMETHING_ELSE\n'
        else printf ' Key\n OP_SERVICE_ACCOUNT_TOKEN\n'; fi ;;
esac
EOF
  chmod +x "$STUB/fnox"
}

# Runs ssh() with a recording _ssh_next standing in for the real ssh.
run_ssh() {
  PATH="$STUB:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" run zsh -f -c '
    ARGV=$1; ENVF=$2; SSH_ZSH=$3; OP_HOOK=$4; shift 4
    source $SSH_ZSH
    _ssh_next() { print -r -- "$*" > $ARGV; print -r -- "${OP_SERVICE_ACCOUNT_TOKEN-UNSET}" > $ENVF; return 0 }
    source $OP_HOOK
    ssh "$@"
  ' _ "$ARGV" "$ENVF" "$SSH_ZSH" "$OP_HOOK" "$@"
}

@test "no token declared: ssh runs unmodified and says nothing" {
  make_fnox undeclared
  run_ssh vm1 uptime
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGV")" = "vm1 uptime" ]
  [ "$(cat "$ENVF")" = "UNSET" ]
  [ -z "$output" ]
}

@test "token resolves: SendEnv is added and the value reaches ssh's environment" {
  make_fnox "ops_TESTTOKEN"
  run_ssh vm1
  [ "$status" -eq 0 ]
  [[ "$(cat "$ARGV")" == "-o SendEnv=OP_SERVICE_ACCOUNT_TOKEN vm1" ]]
  [ "$(cat "$ENVF")" = "ops_TESTTOKEN" ]
}

@test "the token never appears in argv" {
  make_fnox "ops_TESTTOKEN"
  run_ssh vm1
  ! grep -q "ops_TESTTOKEN" "$ARGV"
}

@test "declared but unresolvable: warns, still connects, sends nothing" {
  make_fnox ""
  run_ssh vm1
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not resolve OP_SERVICE_ACCOUNT_TOKEN"* ]]
  [ "$(cat "$ARGV")" = "vm1" ]
  [ "$(cat "$ENVF")" = "UNSET" ]
}

@test "a token containing quotes, newlines and command substitution survives intact" {
  # The wrapper this replaced interpolated the token into a remote shell string,
  # so a single quote in it was remote code execution.
  local evil='abc'"'"'; touch '"$BATS_TEST_TMPDIR"'/pwned; echo '"'"'$(id)'
  make_fnox "$evil"
  run_ssh vm1
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
  [ "$(cat "$ENVF")" = "$evil" ]
  ! grep -q "pwned" "$ARGV"
}

@test "--no-op skips hooks and is not passed to ssh" {
  make_fnox "ops_TESTTOKEN"
  run_ssh --no-op vm1 uptime
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGV")" = "vm1 uptime" ]
  [ "$(cat "$ENVF")" = "UNSET" ]
}

@test "an existing ssh function is chained, not clobbered" {
  # Ghostty defines ssh() to install remote terminfo; replacing it breaks that.
  make_fnox undeclared
  PATH="$STUB:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" run zsh -f -c '
    ssh() { print -r -- "PREEXISTING got: $*" }
    source '"$SSH_ZSH"'
    ssh vm1
  '
  [[ "$output" == "PREEXISTING got: vm1" ]]
}

@test "re-sourcing does not recurse or double-register" {
  make_fnox undeclared
  PATH="$STUB:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" run zsh -f -c '
    source '"$SSH_ZSH"'; source '"$OP_HOOK"'
    source '"$SSH_ZSH"'; source '"$OP_HOOK"'
    _ssh_next() { print -r -- "ok" }
    print -r -- "hooks=${#ssh_wrapper_functions}"
    ssh vm1
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"hooks=1"* ]]
  [[ "$output" == *"ok"* ]]
}

@test "a hook returning non-zero aborts before ssh runs" {
  make_fnox undeclared
  PATH="$STUB:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" run zsh -f -c '
    source '"$SSH_ZSH"'
    _ssh_next() { print -r -- "SHOULD NOT RUN" }
    nope() { return 3 }
    ssh_register nope
    ssh vm1
  '
  [ "$status" -eq 3 ]
  [[ "$output" != *"SHOULD NOT RUN"* ]]
}

@test "cleanup hooks run in reverse order and ssh's exit status propagates" {
  make_fnox undeclared
  PATH="$STUB:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" run zsh -f -c '
    source '"$SSH_ZSH"'
    _ssh_next() { return 42 }
    c1() { print -r -- one }; c2() { print -r -- two }
    h() { ssh_cleanup+=(c1 c2) }
    ssh_register h
    ssh vm1
    print -r -- "ret=$?"
  '
  [[ "${lines[0]}" == "two" ]]
  [[ "${lines[1]}" == "one" ]]
  [[ "${lines[2]}" == "ret=42" ]]
}

@test "ssh_host_arg finds the host past options and their values" {
  run zsh -f -c '
    source '"$SSH_ZSH"'
    print -r -- "$(ssh_host_arg -o SendEnv=X -A -J bastion prod-web1 df -h)"
    print -r -- "$(ssh_host_arg -p 2222 user@rpi4)"
  '
  [[ "${lines[0]}" == "prod-web1" ]]
  [[ "${lines[1]}" == "rpi4" ]]
}

@test "the hook is inert when the ssh dispatcher is not installed" {
  make_fnox "ops_TESTTOKEN"
  PATH="$STUB:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" run zsh -f -c 'source '"$OP_HOOK"'; print -r -- "survived"'
  [ "$status" -eq 0 ]
  [[ "$output" == "survived" ]]
}
