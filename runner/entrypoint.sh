#!/usr/bin/env bash
# Registers one just-in-time (single-use) GitHub Actions runner for one repository and runs exactly one job:
#   1. reads the Registrar App's private key from Key Vault with the job's managed identity
#      (local test mode: from the file GH_REGISTRAR_KEY_FILE instead),
#   2. signs a GitHub App JWT and exchanges it for an installation token limited to the repository and to
#      Administration: write,
#   3. asks GitHub for a JIT runner configuration,
#   4. clears every sensitive variable, then replaces itself with the runner (run.sh --jitconfig), which runs one job
#      and exits;
#   5. meanwhile, a watchdog removes the runner if no job reaches it within RUNNER_IDLE_TIMEOUT seconds: the scaler can
#      start more executions than there are jobs (a run listed both as queued and in progress is counted twice), and a
#      cancelled run leaves its runner waiting. The watchdog holds the installation token until a job starts, no longer.
# Secrets stay in shell variables (never in files, logs or command lines, apart from the JIT configuration that
# run.sh requires as an argument). Logs are JSON lines on stderr. Exit codes: 1 settings, 2 Azure, 3 GitHub.
set -euo pipefail

GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
GITHUB_API_VERSION="2026-03-10"
KEY_VAULT_API_VERSION="2025-07-01"
MANAGED_IDENTITY_API_VERSION="2019-08-01"
RUNNER_DIR="${RUNNER_DIR:-/home/runner}"
RUNNER_IDLE_TIMEOUT="${RUNNER_IDLE_TIMEOUT:-300}"
# Container Apps names each job execution; elsewhere (local test mode) the host name stands in.
EXECUTION_NAME="${CONTAINER_APP_JOB_EXECUTION_NAME:-$(hostname)}"
RUNNER_NAME=""

# Every variable that may give access to a secret: cleared before the runner starts, so the job's steps don't inherit
# them. The managed identity endpoint may still be reachable from the steps: see docs/SECURITY.md.
SENSITIVE_VARIABLES=(
  IDENTITY_ENDPOINT IDENTITY_HEADER MSI_ENDPOINT MSI_SECRET
  KV_SECRET_URI_REGISTRAR AZURE_CLIENT_ID_RUNTIME GH_REGISTRAR_KEY_FILE
  GH_REGISTRAR_CLIENT_ID GH_REGISTRAR_INSTALLATION_ID
)

# log <phase> [message]: one JSON line on stderr, never with a secret in it.
log() {
  jq -cn --arg phase "$1" --arg message "${2:-}" --arg execution "$EXECUTION_NAME" --arg runner "$RUNNER_NAME" \
    --arg repository "${GH_OWNER:-}/${GH_REPO:-}" \
    '{time: (now | todate), phase: $phase, execution: $execution, runner: $runner, repository: $repository,
      message: $message}' >&2
}

# fail <exit code> <message>: logs the failure and stops.
fail() {
  log exit "exit code $1: $2"
  exit "$1"
}

require_settings() {
  local name missing=()
  local required=(GH_OWNER GH_REPO GH_REGISTRAR_CLIENT_ID GH_REGISTRAR_INSTALLATION_ID RUNNER_LABELS RUNNER_GROUP_ID)
  if [[ -z "${GH_REGISTRAR_KEY_FILE:-}" ]]; then
    required+=(KV_SECRET_URI_REGISTRAR AZURE_CLIENT_ID_RUNTIME IDENTITY_ENDPOINT IDENTITY_HEADER)
  fi
  for name in "${required[@]}"; do
    [[ -n "${!name:-}" ]] || missing+=("$name")
  done
  if ((${#missing[@]})); then
    fail 1 "missing settings: ${missing[*]}"
  fi
  [[ "$RUNNER_GROUP_ID" =~ ^[0-9]+$ ]] || fail 1 "RUNNER_GROUP_ID must be a number"
}

# request <method> <url> [json body]: prints the response body, fails unless the status is 2xx. The headers come
# from stdin, one per line, because they hold tokens. curl retries twice on 408, 429 and 5xx, with backoff and
# Retry-After.
request() {
  local method=$1 url=$2 body=${3:-} output status
  local arguments=(--silent --show-error --retry 2 --retry-max-time 120 --max-time 30 --request "$method" --header @-
    --write-out '\n%{http_code}')
  if [[ -n "$body" ]]; then
    arguments+=(--header "Content-Type: application/json" --data "$body")
  fi
  output=$(curl "${arguments[@]}" "$url") || return 1
  status=${output##*$'\n'}
  if [[ "$status" != 2?? ]]; then
    log error "HTTP $status from $method ${url%%\?*}"
    return 1
  fi
  printf '%s' "${output%$'\n'*}"
}

# github <method> <path> <token> [json body]: a GitHub REST API call.
github() {
  printf 'Accept: application/vnd.github+json\nX-GitHub-Api-Version: %s\nAuthorization: Bearer %s\n' \
    "$GITHUB_API_VERSION" "$3" | request "$1" "$GITHUB_API_URL$2" "${4:-}"
}

# The Registrar App's private key (PEM): from Key Vault through the job's managed identity, or from a local file.
registrar_key() {
  if [[ -n "${GH_REGISTRAR_KEY_FILE:-}" ]]; then
    cat "$GH_REGISTRAR_KEY_FILE"
    return
  fi
  local vault_token
  vault_token=$(printf 'X-IDENTITY-HEADER: %s\n' "$IDENTITY_HEADER" |
    request GET "$IDENTITY_ENDPOINT?resource=https://vault.azure.net&api-version=$MANAGED_IDENTITY_API_VERSION&client_id=$AZURE_CLIENT_ID_RUNTIME" |
    jq -er .access_token) || return 1
  printf 'Authorization: Bearer %s\n' "$vault_token" |
    request GET "$KV_SECRET_URI_REGISTRAR?api-version=$KEY_VAULT_API_VERSION" | jq -er .value
}

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# app_jwt <client id> <private key>: an RS256 JWT for the GitHub App, valid from 60 s ago for 9 minutes.
app_jwt() {
  local now header payload signature
  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | base64url)
  payload=$(jq -cn --arg iss "$1" --argjson now "$now" '{iat: ($now - 60), exp: ($now + 540), iss: $iss}' | base64url)
  signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -binary -sign <(printf '%s\n' "$2") | base64url)
  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

# installation_token <jwt>: a token for the repository only, with Administration: write only.
installation_token() {
  local body
  body=$(jq -cn --arg repository "$GH_REPO" '{repositories: [$repository], permissions: {administration: "write"}}')
  github POST "/app/installations/$GH_REGISTRAR_INSTALLATION_ID/access_tokens" "$1" "$body" | jq -er .token
}

# jit_config <token>: GitHub's answer for a new single-use runner named RUNNER_NAME: its id and encoded configuration.
jit_config() {
  local body
  body=$(jq -cn --arg name "$RUNNER_NAME" --arg labels "$RUNNER_LABELS" --argjson group "$RUNNER_GROUP_ID" \
    '{name: $name, runner_group_id: $group, labels: ($labels | split(",") | map(select(. != ""))), work_folder: "_work"}')
  github POST "/repos/$GH_OWNER/$GH_REPO/actions/runners/generate-jitconfig" "$1" "$body" |
    jq -ce '{id: .runner.id, config: .encoded_jit_config}'
}

# watch_idle_runner <runner id> <token>: run in the background. Returns as soon as a job starts (the runner writes a
# Worker log), forgetting the token; after RUNNER_IDLE_TIMEOUT seconds without one, removes the runner, which then
# stops, ending the execution.
watch_idle_runner() {
  local deadline=$((SECONDS + RUNNER_IDLE_TIMEOUT))
  while :; do
    if compgen -G "$RUNNER_DIR/_diag/Worker_*.log" >/dev/null; then
      return 0
    fi
    ((SECONDS < deadline)) || break
    sleep 2
  done
  log idle "no job within ${RUNNER_IDLE_TIMEOUT}s: removing the runner"
  github DELETE "/repos/$GH_OWNER/$GH_REPO/actions/runners/$1" "$2" >/dev/null || log error "could not remove the runner"
}

# A new name for every runner: the execution's name and a random suffix, at most 64 characters.
new_runner_name() {
  local suffix
  suffix=$(openssl rand -hex 3)
  printf '%s-%s' "${EXECUTION_NAME:0:57}" "$suffix"
}

main() {
  local key jwt token runner jit runner_id
  RUNNER_NAME=$(new_runner_name)
  log start
  require_settings
  key=$(registrar_key) || fail 2 "could not read the Registrar App's key"
  log kv_read
  jwt=$(app_jwt "$GH_REGISTRAR_CLIENT_ID" "$key") || fail 3 "could not sign the GitHub App JWT"
  log jwt
  token=$(installation_token "$jwt") || fail 3 "could not get an installation token"
  log install_token
  runner=$(jit_config "$token") || fail 3 "could not create the JIT runner configuration"
  jit=$(jq -r .config <<<"$runner")
  runner_id=$(jq -r .id <<<"$runner")
  log jitconfig
  unset key jwt runner
  unset "${SENSITIVE_VARIABLES[@]}"
  watch_idle_runner "$runner_id" "$token" &
  unset token
  log run
  exec "$RUNNER_DIR/run.sh" --jitconfig "$jit"
}

# Run only when executed, so that the tests can source the functions.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
