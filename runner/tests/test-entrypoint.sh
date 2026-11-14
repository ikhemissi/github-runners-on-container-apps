#!/usr/bin/env bash
# Tests of runner/entrypoint.sh, offline: fake_services.py stands in for the managed identity endpoint, Key Vault and
# GitHub, and a stub run.sh records what the runner would receive. Run them in the runner image (make test), which
# has every tool the entrypoint uses.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ENTRYPOINT="$PWD/../entrypoint.sh"
WORK=$(mktemp -d)
SERVERS=()
trap 'kill "${SERVERS[@]}" 2>/dev/null || true; rm -rf "$WORK"' EXIT
failures=0

check() {  # check <description> <command...>
  if "${@:2}"; then echo "  ok: $1"; else echo "  FAILED: $1"; failures=$((failures + 1)); fi
}

# start_fake <name> [--fail-github]: starts a fake in the background, sets FAKE_URL and FAKE_LOG.
start_fake() {
  FAKE_LOG="$WORK/$1-requests.jsonl"
  python3 fake_services.py "$WORK/app.pem" "$FAKE_LOG" "$WORK/$1.port" "${@:2}" &
  SERVERS+=($!)
  for _ in {1..50}; do [[ -s "$WORK/$1.port" ]] && break; sleep 0.1; done
  FAKE_URL="http://127.0.0.1:$(cat "$WORK/$1.port")"
}

# run_entrypoint <name> [VARIABLE=value...]: runs the entrypoint with a stub runner, which records its arguments and
# environment, starts a job (writes a Worker log) unless STUB_STARTS_JOB=0, and lives 4 s so the idle watchdog can
# act. Sets EXIT_CODE.
run_entrypoint() {
  local name=$1
  mkdir -p "$WORK/$name/runner"
  cat >"$WORK/$name/runner/run.sh" <<EOF
#!/usr/bin/env bash
printf "%s\\n" "\$@" > "$WORK/$name/args"
env > "$WORK/$name/env"
if [[ "\${STUB_STARTS_JOB:-1}" == 1 ]]; then mkdir -p "$WORK/$name/runner/_diag" && touch "$WORK/$name/runner/_diag/Worker_1.log"; fi
sleep 4
EOF
  chmod +x "$WORK/$name/runner/run.sh"
  EXIT_CODE=0
  env -i PATH="$PATH" HOME="$HOME" GITHUB_API_URL="$FAKE_URL" RUNNER_DIR="$WORK/$name/runner" \
    CONTAINER_APP_JOB_EXECUTION_NAME="test-execution" GH_OWNER=octo GH_REPO=demo RUNNER_IDLE_TIMEOUT=2 \
    GH_REGISTRAR_CLIENT_ID=Iv1.test GH_REGISTRAR_INSTALLATION_ID=42 RUNNER_LABELS="aca-agent" RUNNER_GROUP_ID=1 \
    "${@:2}" bash "$ENTRYPOINT" 2>"$WORK/$name/log" || EXIT_CODE=$?
}

requests_to() {  # requests_to <path suffix>: the recorded requests whose path ends with it
  jq -c --arg suffix "$1" 'select(.path | endswith($suffix))' "$FAKE_LOG"
}

openssl genrsa -out "$WORK/app.pem" 2048 2>/dev/null
openssl rsa -in "$WORK/app.pem" -pubout -out "$WORK/app.pub" 2>/dev/null

echo "The GitHub App JWT is signed with the key and carries the claims GitHub requires"
(
  # shellcheck source=runner/entrypoint.sh
  source "$ENTRYPOINT"
  jwt=$(app_jwt "Iv1.test" "$(cat "$WORK/app.pem")")
  IFS=. read -r header payload signature <<<"$jwt"
  decode() { local text=$1; while ((${#text} % 4)); do text+="="; done; tr '_-' '/+' <<<"$text" | openssl base64 -d -A; }
  decode "$signature" >"$WORK/signature"
  printf '%s.%s' "$header" "$payload" >"$WORK/signed"
  claims=$(decode "$payload")
  now=$(date +%s)
  check "the signature verifies with the public key" \
    openssl dgst -sha256 -verify "$WORK/app.pub" -signature "$WORK/signature" "$WORK/signed"
  check "the algorithm is RS256" test "$(decode "$header" | jq -r .alg)" = RS256
  check "the issuer is the client ID" test "$(jq -r .iss <<<"$claims")" = Iv1.test
  check "issued 60 s in the past" test "$(jq -r .iat <<<"$claims")" -le $((now - 59))
  check "expires at most 10 minutes from now" test "$(jq -r .exp <<<"$claims")" -le $((now + 600))
  exit "$failures"
) || failures=$((failures + $?))

echo "Local mode registers one runner and starts it without the secrets"
start_fake local
run_entrypoint local GH_REGISTRAR_KEY_FILE="$WORK/app.pem" RUNNER_LABELS="aca-agent,linux-big"
check "it exits through the runner" test "$EXIT_CODE" = 0
check "the runner gets the JIT configuration" test "$(paste -sd' ' "$WORK/local/args")" = "--jitconfig test-jit-config"
check "the token is limited to the repository and Administration: write" test \
  "$(requests_to /access_tokens | jq -c .body)" = '{"repositories":["demo"],"permissions":{"administration":"write"}}'
check "the runner gets the labels and the group" test \
  "$(requests_to /generate-jitconfig | jq -c '.body | [.labels, .runner_group_id, .work_folder]')" \
  = '[["aca-agent","linux-big"],1,"_work"]'
check "the runner name starts with the execution name" \
  grep -q '"name":"test-execution-[0-9a-f]\{6\}"' <(requests_to /generate-jitconfig)
check "GitHub calls use the API version 2026-03-10" test \
  "$(jq -r .api_version "$FAKE_LOG" | sort -u)" = 2026-03-10
check "the runner's environment holds no sensitive variable" \
  bash -c "! grep -E '^(IDENTITY_|MSI_|KV_SECRET|AZURE_CLIENT_ID_RUNTIME|GH_REGISTRAR)' '$WORK/local/env'"
check "the logs hold no secret" \
  bash -c "! grep -E 'test-installation-token|test-jit-config|BEGIN|eyJ' '$WORK/local/log'"
check "the logs are JSON lines with the phases" test \
  "$(jq -r .phase "$WORK/local/log" | paste -sd,)" = "start,kv_read,jwt,install_token,jitconfig,run"
check "a runner that gets a job is not removed" test "$(requests_to /actions/runners/7 | wc -l)" = 0

echo "Azure mode reads the key from Key Vault with the managed identity"
run_entrypoint azure IDENTITY_ENDPOINT="$FAKE_URL/msi/token" IDENTITY_HEADER=test-identity-header \
  AZURE_CLIENT_ID_RUNTIME=runtime-client-id KV_SECRET_URI_REGISTRAR="$FAKE_URL/secrets/registrar"
check "it exits through the runner" test "$EXIT_CODE" = 0
check "the token request names the runtime identity and Key Vault" test \
  "$(requests_to /msi/token | tail -1 | jq -c '[.query.client_id[0], .query.resource[0], .identity_header]')" \
  = '["runtime-client-id","https://vault.azure.net","test-identity-header"]'
check "Key Vault is called with the identity's token" test \
  "$(requests_to /secrets/registrar | tail -1 | jq -r .authorization)" = "Bearer test-vault-token"
check "the runner's environment holds no identity variable" \
  bash -c "! grep -E '^(IDENTITY_|KV_SECRET|AZURE_CLIENT_ID_RUNTIME)' '$WORK/azure/env'"

echo "A runner that gets no job is removed after the idle timeout"
run_entrypoint idle GH_REGISTRAR_KEY_FILE="$WORK/app.pem" STUB_STARTS_JOB=0
check "it removes its runner, with the installation token" test \
  "$(requests_to /actions/runners/7 | jq -r '"\(.method) \(.authorization)"')" = "DELETE Bearer test-installation-token"
check "it logs why" grep -q '"phase":"idle"' "$WORK/idle/log"
check "the logs still hold no secret" bash -c "! grep -E 'test-installation-token|test-jit-config' '$WORK/idle/log'"

echo "Missing settings stop it before any call"
run_entrypoint missing GH_REPO=
check "it exits with code 1" test "$EXIT_CODE" = 1
check "it names what is missing" grep -q "missing settings: GH_REPO" "$WORK/missing/log"

echo "GitHub errors are retried twice, then it stops"
start_fake failing --fail-github
run_entrypoint failing GH_REGISTRAR_KEY_FILE="$WORK/app.pem"
check "it exits with code 3" test "$EXIT_CODE" = 3
check "the token request was tried 3 times" test "$(requests_to /access_tokens | wc -l)" = 3
check "the runner did not start" test ! -e "$WORK/failing/args"

if ((failures)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All checks passed"
