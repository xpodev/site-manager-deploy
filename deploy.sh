#!/usr/bin/env bash
# Packs a built site and publishes it through a Site Manager deploy service.
# Inputs arrive as environment variables: DEPLOY_URL, DEPLOY_TOKEN, SITE_PATH,
# SITE_NAME (optional) and RETRIES.
set -euo pipefail

fail() {
  echo "::error title=Site deploy failed::$1"
  exit 1
}

human() {
  awk -v b="$1" 'BEGIN {
    split("B KiB MiB GiB", unit); i = 1
    while (b >= 1024 && i < 4) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.1f %s"), b, unit[i]
  }'
}

# field NAME extracts a string or number field from the flat JSON in $body.
field() {
  sed -n "s/.*\"$1\":\"\{0,1\}\([^\",}]*\).*/\1/p" <<<"$body"
}

[[ -n "${DEPLOY_URL:-}" ]] || fail "The 'url' input is required."
[[ -n "${DEPLOY_TOKEN:-}" ]] || fail "The 'token' input is required. Store the deploy key as a secret and pass it in."
echo "::add-mask::$DEPLOY_TOKEN"
SITE_PATH="${SITE_PATH:-dist}"
RETRIES="${RETRIES:-2}"
[[ "$RETRIES" =~ ^[0-9]+$ ]] || fail "The 'retries' input must be a whole number, got '$RETRIES'."
[[ -d "$SITE_PATH" ]] || fail "Folder '$SITE_PATH' does not exist. Did the build run, and does 'path' point at its output folder?"
[[ -n "$(ls -A "$SITE_PATH")" ]] || fail "Folder '$SITE_PATH' is empty."
endpoint="${DEPLOY_URL%/}/deploy"
SITE_NAME="${SITE_NAME:-}"
if [[ -n "$SITE_NAME" ]]; then
  [[ "$SITE_NAME" =~ ^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$ && "$SITE_NAME" != *..* ]] ||
    fail "Invalid 'site' input '$SITE_NAME': use lowercase letters, digits, '.', '-' and '_', starting and ending with a letter or digit."
  endpoint="$endpoint?site=$SITE_NAME"
fi

work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/site-deploy.XXXXXX")"
trap 'rm -rf "$work"' EXIT
archive="$work/site.tar.gz"

tar -czf "$archive" -C "$SITE_PATH" .
echo "Packed '$SITE_PATH' into $(human "$(wc -c <"$archive")")"

echo "Uploading to $endpoint"
status=$(curl -sS -X POST "$endpoint" \
  --retry "$RETRIES" --retry-delay 5 --connect-timeout 20 \
  -H "Authorization: Bearer $DEPLOY_TOKEN" \
  -H "Content-Type: application/gzip" \
  --data-binary "@$archive" \
  -o "$work/response" -w '%{http_code}') || fail "Could not reach $endpoint (curl exit code $?)."
body="$(cat "$work/response")"

if [[ "$status" != 200 ]]; then
  msg="$(field error)"
  msg="HTTP $status: ${msg:-$body}"
  case "$status" in
    400)
      if [[ -z "$SITE_NAME" && "$msg" == *"whole namespace"* ]]; then
        msg="$msg. Set the 'site' input to the site to deploy."
      fi
      ;;
    401) msg="$msg. Check that the token secret holds the current deploy key; creating a new key replaces the old one." ;;
    403) msg="$msg. Remove the 'site' input or use a key for that site." ;;
    413) msg="$msg. The upload is larger than the deploy service or its proxy accepts (MAX_UPLOAD_MB / client_max_body_size)." ;;
    502) msg="$msg. The deploy service is up but cannot reach the admin service." ;;
  esac
  fail "$msg"
fi

namespace="$(field namespace)"
site="$(field site)"
files="$(field files)"
bytes="$(field bytes)"
{
  echo "namespace=$namespace"
  echo "site=$site"
  echo "files=$files"
  echo "bytes=$bytes"
} >>"${GITHUB_OUTPUT:-/dev/null}"

echo "Deployed $namespace/$site: $files files, $(human "$bytes")"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >>"$GITHUB_STEP_SUMMARY" <<EOF
### Deployed \`$namespace/$site\`

| Files | Size |
|------:|-----:|
| $files | $(human "$bytes") |
EOF
fi
