#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CAMPAIGN_ID=""
NAME=""
OBJECTIVE=""
PLATFORMS="instagram,youtube-short"
NOTES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --campaign-id) CAMPAIGN_ID="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --objective) OBJECTIVE="$2"; shift 2 ;;
        --platforms) PLATFORMS="$2"; shift 2 ;;
        --notes) NOTES="$2"; shift 2 ;;
        --help|-h)
            cat <<'HELP'
Initialize a social media campaign ledger.

Usage:
  bash init-campaign.sh --campaign-id ID --name NAME --objective TEXT [options]

Options:
  --platforms LIST  Comma-separated platforms. Default: instagram,youtube-short
  --notes TEXT      Optional campaign notes.
HELP
            exit 0 ;;
        *) usage_error "Unknown argument '$1'" ;;
    esac
done

require_jq

[ -n "$CAMPAIGN_ID" ] || usage_error "--campaign-id is required."
[ -n "$NAME" ] || usage_error "--name is required."
[ -n "$OBJECTIVE" ] || usage_error "--objective is required."

if [[ ! "$CAMPAIGN_ID" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    usage_error "--campaign-id must use lowercase letters, numbers, dots, underscores, or hyphens."
fi

IFS=',' read -r -a PLATFORM_ARRAY <<< "$PLATFORMS"
for platform in "${PLATFORM_ARRAY[@]}"; do
    ensure_platform_exists "$platform"
done

DIR="$(campaign_dir "$CAMPAIGN_ID")"
if [ -e "$DIR/campaign.json" ]; then
    usage_error "Campaign '$CAMPAIGN_ID' already exists at $DIR."
fi

mkdir -p "$DIR/assets" "$DIR/packages" "$DIR/queue" "$DIR/metrics" "$DIR/briefs"

CREATED_AT="$(utc_now)"
PLATFORMS_JSON="$(printf '%s\n' "${PLATFORM_ARRAY[@]}" | jq -R . | jq -s .)"

jq -n \
    --arg campaign_id "$CAMPAIGN_ID" \
    --arg name "$NAME" \
    --arg objective "$OBJECTIVE" \
    --arg created_at "$CREATED_AT" \
    --arg notes "$NOTES" \
    --argjson platforms "$PLATFORMS_JSON" \
    '{
      campaign_id: $campaign_id,
      name: $name,
      objective: $objective,
      platforms: $platforms,
      created_at: $created_at,
      notes: $notes,
      brand_files: [],
      cadence: "manual"
    }' > "$DIR/campaign.json"

RUN_ID="$(new_run_id campaign)"
ENTRY_FILE="$(mktemp)"
jq -n \
    --arg run_id "$RUN_ID" \
    --arg timestamp "$CREATED_AT" \
    --arg campaign_id "$CAMPAIGN_ID" \
    --arg notes "$NOTES" \
    '{
      run_id: $run_id,
      timestamp: $timestamp,
      campaign_id: $campaign_id,
      kind: "campaign_initialized",
      status: "completed",
      notes: $notes
    }' > "$ENTRY_FILE"
append_manifest_entry "$CAMPAIGN_ID" "$ENTRY_FILE"
rm -f "$ENTRY_FILE"

echo "Campaign initialized: $DIR"
