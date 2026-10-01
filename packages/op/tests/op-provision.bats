#!/usr/bin/env bats
# op-provision, against a stubbed `op`. No network, no 1Password account.
# Run: bats packages/op/tests/op-provision.bats

setup() {
  PROV="$BATS_TEST_DIRNAME/../home/.local/bin/op-provision"
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  export OPLOG="$BATS_TEST_TMPDIR"
  : > "$OPLOG/argv.log"
  : > "$OPLOG/stdin.log"
  export OP_SA_CREDENTIALS_VAULT=Private
  export OP_SHARED_VAULT=shared
  # EXISTING lists what the fake account already has, so idempotence is testable.
  : > "$OPLOG/existing"
  cat > "$STUB/op" <<'EOF'
#!/usr/bin/env bash
echo "op $*" >> "$OPLOG/argv.log"
has() { grep -qx "$1" "$OPLOG/existing" 2>/dev/null; }
case "$1 $2" in
  "vault get")   has "vault:$3" ;;
  "item get")    has "item:$3" ;;
  "user list")   if has "sa:$(cat "$OPLOG/saname" 2>/dev/null)"; then
                   printf '[{"name":"%s"}]' "$(cat "$OPLOG/saname")"
                 else printf '[{"name":"unrelated-sa"}]'; fi ;;
  "vault create") echo '{"id":"v1"}' ;;
  "service-account create") echo '{"id":"s1","token":"ops_SECRET_TOKEN"}' ;;
  "item create") cat >> "$OPLOG/stdin.log"; echo '{"id":"i1"}' ;;
  "item delete") ;;
  "vault delete") ;;
  "user delete") ;;
esac
EOF
  chmod +x "$STUB/op"
  PATH="$STUB:$PATH"
  export PATH
}

@test "strict mode names what is missing and points at the wizard" {
  run "$PROV" create
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing <name>"* ]]
  [[ "$output" == *"--wizard"* ]]
}

@test "--dry-run shows the plan and changes nothing" {
  run "$PROV" create lgat --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"CREATE vault           lgat"* ]]
  [[ "$output" == *"CREATE service account lgat-sa"* ]]
  ! grep -qE 'vault create|service-account create|item create' "$OPLOG/argv.log"
}

@test "refuses to act unattended without --yes" {
  run "$PROV" create lgat
  [ "$status" -ne 0 ]
  [[ "$output" == *"--yes"* ]]
  ! grep -q 'vault create' "$OPLOG/argv.log"
}

@test "the service account is granted its own vault and the shared vault" {
  run "$PROV" create lgat --yes
  [ "$status" -eq 0 ]
  grep -qx 'op service-account create lgat-sa --vault lgat:read_items --vault shared:read_items --format json' "$OPLOG/argv.log"
}

@test "--shared overrides OP_SHARED_VAULT" {
  run "$PROV" create lgat --shared ops --yes
  grep -q -- '--vault ops:read_items' "$OPLOG/argv.log"
}

@test "the token is never in argv and always on stdin" {
  run "$PROV" create lgat --yes
  [ "$status" -eq 0 ]
  ! grep -q 'ops_SECRET_TOKEN' "$OPLOG/argv.log"
  grep -q 'ops_SECRET_TOKEN' "$OPLOG/stdin.log"
  grep -q '"category": "API_CREDENTIAL"' "$OPLOG/stdin.log"
  grep -q '"id": "credential"' "$OPLOG/stdin.log"
}

@test "op is always invoked with any forwarded service account token unset" {
  # Inside a provisioned directory OP_SERVICE_ACCOUNT_TOKEN is resolvable; a
  # read-only single-vault SA cannot create anything, so provisioning must
  # authenticate as the human.
  cat > "$STUB/op" <<'EOF'
#!/usr/bin/env bash
echo "TOKEN=${OP_SERVICE_ACCOUNT_TOKEN-unset}" >> "$OPLOG/argv.log"
case "$1 $2" in
  "user list") printf '[]' ;;
  "service-account create") echo '{"token":"t"}' ;;
  *) echo '{}' ;;
esac
EOF
  chmod +x "$STUB/op"
  OP_SERVICE_ACCOUNT_TOKEN=ops_FORWARDED run "$PROV" create lgat --yes
  grep -q 'TOKEN=unset' "$OPLOG/argv.log"
  ! grep -q 'ops_FORWARDED' "$OPLOG/argv.log"
}

@test "create is idempotent: nothing already present is recreated" {
  printf 'vault:lgat\nvault:shared\nitem:lgat-sa-token\n' > "$OPLOG/existing"
  echo 'lgat-sa' > "$OPLOG/saname"
  printf 'sa:lgat-sa\n' >> "$OPLOG/existing"
  run "$PROV" create lgat --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to do."* ]]
  ! grep -qE 'vault create|service-account create' "$OPLOG/argv.log"
}

@test "a service account response with no token is fatal and creates no item" {
  cat > "$STUB/op" <<'EOF'
#!/usr/bin/env bash
echo "op $*" >> "$OPLOG/argv.log"
case "$1 $2" in
  "user list") printf '[]' ;;
  "service-account create") echo '{"id":"s1"}' ;;   # no token field
  *) echo '{}' ;;
esac
EOF
  chmod +x "$STUB/op"
  run "$PROV" create lgat --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"no token"* ]]
  ! grep -q 'item create' "$OPLOG/argv.log"
}

@test "rotate stores the replacement token before revoking the old account" {
  echo 'lgat-sa' > "$OPLOG/saname"
  printf 'sa:lgat-sa\n' > "$OPLOG/existing"
  run "$PROV" rotate lgat --yes
  [ "$status" -eq 0 ]
  local create_line revoke_line
  create_line=$(grep -n 'item create' "$OPLOG/argv.log" | head -1 | cut -d: -f1)
  revoke_line=$(grep -n 'user delete' "$OPLOG/argv.log" | head -1 | cut -d: -f1)
  [ -n "$create_line" ]
  [ -n "$revoke_line" ]
  [ "$create_line" -lt "$revoke_line" ]
}

@test "rotate refuses when there is no account to rotate" {
  run "$PROV" rotate lgat --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"no service account"* ]]
}

@test "destroy removes item, account and vault, and leaves the shared vault" {
  echo 'lgat-sa' > "$OPLOG/saname"
  printf 'vault:lgat\nitem:lgat-sa-token\nsa:lgat-sa\n' > "$OPLOG/existing"
  run "$PROV" destroy lgat --yes
  [ "$status" -eq 0 ]
  grep -q 'item delete lgat-sa-token' "$OPLOG/argv.log"
  grep -q 'user delete lgat-sa' "$OPLOG/argv.log"
  grep -q 'vault delete lgat' "$OPLOG/argv.log"
  ! grep -q 'vault delete shared' "$OPLOG/argv.log"
  [[ "$output" == *"not reversible"* ]]
}

@test "link writes a fnox.toml that names the provider explicitly" {
  cd "$BATS_TEST_TMPDIR"
  run "$PROV" link lgat --yes
  [ "$status" -eq 0 ]
  # A bare `{ value = ... }` is stored verbatim and never reaches the provider,
  # so the op:// reference would not resolve.
  grep -q 'provider = "onepass"' fnox.toml
  grep -q 'op://Private/lgat-sa-token/credential' fnox.toml
  grep -q 'env = false' fnox.toml
}

@test "link will not clobber an existing config without --force" {
  cd "$BATS_TEST_TMPDIR"
  echo 'keep me' > fnox.toml
  run "$PROV" link lgat --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
  [ "$(cat fnox.toml)" = "keep me" ]
  run "$PROV" link lgat --yes --force
  [ "$status" -eq 0 ]
  grep -q 'OP_SERVICE_ACCOUNT_TOKEN' fnox.toml
}

@test "status reports each piece" {
  printf 'vault:lgat\n' > "$OPLOG/existing"
  run "$PROV" status lgat
  [ "$status" -eq 0 ]
  [[ "$output" == *"vault lgat"*"present"* ]]
  [[ "$output" == *"MISSING"* ]]
}

@test "destroy revokes a rotated account, whose name is not literally <name>-sa" {
  # rotate() cannot reuse the old name while it exists, so it creates
  # <name>-sa-<timestamp>. Anything that looks an account up has to match that,
  # or destroy leaves a live credential behind.
  cat > "$STUB/op" <<'EOF'
#!/usr/bin/env bash
echo "op $*" >> "$OPLOG/argv.log"
case "$1 $2" in
  "user list") printf '[{"name":"lgat-sa-20260922120000"},{"name":"lgat-sandbox-sa"},{"name":"unrelated"}]' ;;
  "vault get") exit 0 ;;
  "item get")  exit 0 ;;
  *) ;;
esac
EOF
  chmod +x "$STUB/op"
  run "$PROV" destroy lgat --yes
  [ "$status" -eq 0 ]
  grep -q 'user delete lgat-sa-20260922120000' "$OPLOG/argv.log"
  # scope "lgat" must not sweep up the separate "lgat-sandbox" scope
  ! grep -q 'user delete lgat-sandbox-sa' "$OPLOG/argv.log"
}

@test "status shows a rotated account under its real name" {
  cat > "$STUB/op" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "user list") printf '[{"name":"lgat-sa-20260922120000"}]' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/op"
  run "$PROV" status lgat
  [[ "$output" == *"lgat-sa-20260922120000"* ]]
}

@test "the token item is tagged and records the scope's metadata" {
  # Vaults and service accounts cannot be tagged, so the token item is the only
  # thing `list` can query. It has to carry the tag and the scope details.
  run "$PROV" create lgat --yes
  [ "$status" -eq 0 ]
  grep -q '"op-provision"' "$OPLOG/stdin.log"
  grep -q '"lgat"' "$OPLOG/stdin.log"
  grep -q '"shared vault"' "$OPLOG/stdin.log"
  grep -q '"service account"' "$OPLOG/stdin.log"
  # metadata is not secret, but the credential still must not be in argv
  ! grep -q 'ops_SECRET_TOKEN' "$OPLOG/argv.log"
}

@test "created vaults are stamped with a description, since they cannot be tagged" {
  run "$PROV" create lgat --yes
  grep -q 'vault create lgat --description op-provision: scope lgat' "$OPLOG/argv.log"
}

@test "list queries by tag and needs only two calls whatever the scope count" {
  cat > "$STUB/op" <<'EOF'
#!/usr/bin/env bash
echo "op $*" >> "$OPLOG/argv.log"
case "$1 $2" in
  "item list") printf '[{"id":"a"},{"id":"b"},{"id":"c"}]' ;;
  "item get")  cat >/dev/null
               printf '[{"id":"a","title":"lgat-sa-token","vault":{"name":"Private"},"fields":[{"id":"scope","value":"lgat"},{"id":"service_account","value":"lgat-sa"}]}]' ;;
esac
EOF
  chmod +x "$STUB/op"
  run "$PROV" list
  [ "$status" -eq 0 ]
  grep -q -- '--tags op-provision' "$OPLOG/argv.log"
  [[ "$output" == *"lgat"* ]]
  [[ "$output" == *"lgat-sa"* ]]
  [ "$(grep -c 'item list\|item get' "$OPLOG/argv.log")" -eq 2 ]
}

@test "list says something useful when nothing is provisioned" {
  cat > "$STUB/op" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in "item list") printf '[]' ;; esac
EOF
  chmod +x "$STUB/op"
  run "$PROV" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing tagged"* ]]
  [[ "$output" == *"create"* ]]
}

@test "list tolerates an item with no metadata fields" {
  # e.g. a token item created by hand before this convention existed
  cat > "$STUB/op" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "item list") printf '[{"id":"z"}]' ;;
  "item get")  cat >/dev/null
               printf '[{"id":"z","title":"legacy-sa-token","vault":{"name":"Private"},"fields":[{"id":"credential","value":"x"}]}]' ;;
esac
EOF
  chmod +x "$STUB/op"
  run "$PROV" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"legacy"* ]]     # scope recovered from the title
}

@test "OP_PROVISION_TAG overrides the marker tag" {
  OP_PROVISION_TAG=mytag run "$PROV" create lgat --yes
  grep -q '"mytag"' "$OPLOG/stdin.log"
}
