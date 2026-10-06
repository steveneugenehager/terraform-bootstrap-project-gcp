#!/usr/bin/env bash
#
# create_secondary_org_admin.sh
#
# Bootstrap a secondary (break-glass) organization owner:
#   1. Create the user in Google Workspace / Cloud Identity (Directory API)
#   2. Grant it Super Admin in the Admin console (Directory API makeAdmin)
#   3. Grant it org-level IAM roles on the GCP organization (gcloud)
#
# Must be run by an existing Super Admin. There is no gcloud command for
# Workspace users, so steps 1-2 call the Admin SDK REST API with curl using
# an ADC token that carries Admin SDK scopes.
#
# Requirements: gcloud, curl, jq, openssl
#
# Usage:
#   ./create_secondary_org_admin.sh \
#       --domain example.com \
#       --username breakglass-admin \
#       --given "Break" --family "Glass" \
#       --project my-bootstrap-project \
#       --client-secret my-client-secret.json \
#       [--recovery-email you@personal.example] \
#       [--org-roles "roles/resourcemanager.organizationAdmin,roles/billing.admin"] \
#       [--prompt-password] \
#       [--dry-run]
#
# Password: by default a random temporary password is generated and written
# to a mode-600 temp file. With --prompt-password you type the final password
# instead (hidden input, entered twice); nothing is written to disk.
#
# Change History
# 2026-10-06 Steve Hager v1.1 Incorporated --client-secret argument handling.

set -euo pipefail

# ----------------------------------------------------------------------------
# Defaults / args
# ----------------------------------------------------------------------------
DOMAIN=""
USERNAME=""
GIVEN="Secondary"
FAMILY="Admin"
PROJECT=""
RECOVERY_EMAIL=""
ORG_ROLES="roles/resourcemanager.organizationAdmin"
DRY_RUN=false
PROMPT_PW=false
MIN_PW_LEN=16
CLIENT_SECRET_JSON=""

DIR_API="https://admin.googleapis.com/admin/directory/v1"
ADMIN_SCOPES="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/admin.directory.user"

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)          DOMAIN="$2"; shift 2 ;;
    --username)        USERNAME="$2"; shift 2 ;;
    --given)           GIVEN="$2"; shift 2 ;;
    --family)          FAMILY="$2"; shift 2 ;;
    --project)         PROJECT="$2"; shift 2 ;;
    --recovery-email)  RECOVERY_EMAIL="$2"; shift 2 ;;
    --org-roles)       ORG_ROLES="$2"; shift 2 ;;
    --client-secret)   CLIENT_SECRET_JSON="$2"; shift 2 ;;
    --prompt-password) PROMPT_PW=true; shift ;;
    --dry-run)         DRY_RUN=true; shift ;;
    -h|--help)         usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -z "$DOMAIN" || -z "$USERNAME" || -z "$PROJECT" ]] && usage

EMAIL="${USERNAME}@${DOMAIN}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if $DRY_RUN; then echo "[dry-run] $*"; else "$@"; fi; }

for bin in gcloud curl jq openssl; do
  command -v "$bin" >/dev/null || die "Missing dependency: $bin"
done

# ----------------------------------------------------------------------------
# Auth: ADC token with Admin SDK scope, quota billed to the bootstrap project
# ----------------------------------------------------------------------------
log "Enabling Admin SDK API on $PROJECT"
run gcloud services enable admin.googleapis.com --project "$PROJECT"

get_token() {
  gcloud auth application-default print-access-token 2>/dev/null || true
}

has_admin_scope() {
  local tok="$1"
  curl -fsS "https://oauth2.googleapis.com/tokeninfo?access_token=${tok}" 2>/dev/null \
    | jq -e '.scope | split(" ") | index("https://www.googleapis.com/auth/admin.directory.user")' >/dev/null
}

TOKEN="$(get_token)"
if [[ -z "$TOKEN" ]] || ! has_admin_scope "$TOKEN"; then
  log "Logging in for ADC with Admin SDK scopes (sign in as an existing Super Admin)"
  # If Google blocks the default gcloud client for these scopes, create a
  # Desktop OAuth client in $PROJECT and add: --client-id-file=client_secret.json
  gcloud auth application-default login --scopes="$ADMIN_SCOPES" --client-id-file="${CLIENT_SECRET_JSON}"
  TOKEN="$(get_token)"
  has_admin_scope "$TOKEN" || die "ADC token still lacks admin.directory.user scope"
fi
gcloud auth application-default set-quota-project "$PROJECT" >/dev/null 2>&1 || true

# Directory API helper: api METHOD PATH [JSON_BODY]
api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" -w '\n%{http_code}'
              -H "Authorization: Bearer ${TOKEN}"
              -H "x-goog-user-project: ${PROJECT}"
              -H "Content-Type: application/json")
  # Body goes via stdin, never argv, so the password can't show up in `ps`.
  if [[ -n "$body" ]]; then
    curl "${args[@]}" --data-binary @- "${DIR_API}${path}" <<<"$body"
  else
    curl "${args[@]}" "${DIR_API}${path}"
  fi
}

# Split "body\nstatus" from api()
status_of() { tail -n1 <<<"$1"; }
body_of()   { sed '$d' <<<"$1"; }

# ----------------------------------------------------------------------------
# 1. Create user (idempotent)
# ----------------------------------------------------------------------------
log "Checking whether $EMAIL exists"
resp="$(api GET "/users/${EMAIL}")"
code="$(status_of "$resp")"

PASSWORD=""
if [[ "$code" == "200" ]]; then
  warn "$EMAIL already exists; skipping creation"
elif [[ "$code" == "404" ]]; then
  if $PROMPT_PW; then
    [[ -t 0 ]] || die "--prompt-password needs an interactive terminal"
    while :; do
      read -rsp "Password for $EMAIL (min $MIN_PW_LEN chars): " PASSWORD; echo >&2
      read -rsp "Confirm password: " pw2; echo >&2
      if [[ "$PASSWORD" != "$pw2" ]]; then
        warn "Passwords don't match; try again"
      elif (( ${#PASSWORD} < MIN_PW_LEN )); then
        warn "Too short (${#PASSWORD} < $MIN_PW_LEN); try again"
      else
        break
      fi
    done
    unset pw2
    FORCE_CHANGE=false        # you chose it, so no forced change at first login
  else
    PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"
    FORCE_CHANGE=true
  fi

  user_json="$(jq -n \
    --arg email "$EMAIL" --arg given "$GIVEN" --arg family "$FAMILY" \
    --arg pw "$PASSWORD" --arg rec "$RECOVERY_EMAIL" \
    --argjson force "$FORCE_CHANGE" '
    {
      primaryEmail: $email,
      name: { givenName: $given, familyName: $family },
      password: $pw,
      changePasswordAtNextLogin: $force,
      orgUnitPath: "/"
    }
    + (if $rec != "" then { recoveryEmail: $rec } else {} end)')"

  log "Creating $EMAIL"
  if $DRY_RUN; then
    echo "[dry-run] POST /users $(jq -c 'del(.password)' <<<"$user_json")"
  else
    resp="$(api POST "/users" "$user_json")"
    code="$(status_of "$resp")"
    [[ "$code" == "200" ]] || die "User create failed ($code): $(body_of "$resp")"
  fi
else
  die "Unexpected response checking user ($code): $(body_of "$resp")"
fi

echo "Sleeping here for 30 seconds..."
sleep 30

# ----------------------------------------------------------------------------
# 2. Grant Super Admin
# ----------------------------------------------------------------------------
log "Granting Super Admin to $EMAIL"
if $DRY_RUN; then
  echo "[dry-run] POST /users/${EMAIL}/makeAdmin {\"status\":true}"
else
  # New accounts can take a few seconds to propagate; retry briefly.
  for attempt in 1 2 3 4 5; do
    resp="$(api POST "/users/${EMAIL}/makeAdmin" '{"status":true}')"
    code="$(status_of "$resp")"
    [[ "$code" == "204" || "$code" == "200" ]] && break
    warn "makeAdmin attempt $attempt returned $code; retrying in 5s"
    sleep 5
  done
  [[ "$code" == "204" || "$code" == "200" ]] || die "makeAdmin failed ($code): $(body_of "$resp")"
fi

# ----------------------------------------------------------------------------
# 3. GCP organization IAM
# ----------------------------------------------------------------------------
log "Resolving GCP organization for $DOMAIN"
ORG_ID="$(gcloud organizations list \
  --filter="displayName=${DOMAIN}" --format='value(name)' | sed 's#organizations/##')"
[[ -n "$ORG_ID" ]] || die "No GCP organization found for $DOMAIN"
log "Organization: $ORG_ID"

IFS=',' read -ra ROLES <<<"$ORG_ROLES"
for role in "${ROLES[@]}"; do
  log "Binding $role on organization $ORG_ID"
  run gcloud organizations add-iam-policy-binding "$ORG_ID" \
    --member="user:${EMAIL}" --role="$role" --condition=None --quiet >/dev/null
done

# ----------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------
echo
log "Done: $EMAIL is Super Admin and holds: ${ORG_ROLES}"
if [[ -n "$PASSWORD" ]] && ! $DRY_RUN && ! $PROMPT_PW; then
  CRED_FILE="$(mktemp "${TMPDIR:-/tmp}/breakglass.XXXXXX")"
  chmod 600 "$CRED_FILE"
  printf '%s\n%s\n' "$EMAIL" "$PASSWORD" >"$CRED_FILE"
  warn "Temporary password written to $CRED_FILE (mode 600)."
  warn "Sign in now, change it, enroll a hardware security key, then shred the file:"
  warn "  shred -u '$CRED_FILE'"
elif $PROMPT_PW && ! $DRY_RUN; then
  warn "Sign in now as $EMAIL and enroll a hardware security key."
fi
unset PASSWORD
