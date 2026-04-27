#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CAMPAIGN_ID=""
PLATFORM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --campaign-id) CAMPAIGN_ID="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --help|-h)
            cat <<'HELP'
Export a manual publishing queue.

Usage:
  bash export-queue.sh --campaign-id ID [--platform instagram]
HELP
            exit 0 ;;
        *) usage_error "Unknown argument '$1'" ;;
    esac
done

[ -n "$CAMPAIGN_ID" ] || usage_error "--campaign-id is required."

require_jq
ensure_campaign_exists "$CAMPAIGN_ID"

CAMPAIGN_DIR="$(campaign_dir "$CAMPAIGN_ID")"
PACKAGES_DIR="$CAMPAIGN_DIR/packages"
QUEUE_DIR="$CAMPAIGN_DIR/queue"
mkdir -p "$QUEUE_DIR"

RUN_ID="$(new_run_id export)"
QUEUE_FILE="$QUEUE_DIR/${RUN_ID}.json"
TMP_ENTRY="$(mktemp)"

if [ -n "$PLATFORM" ]; then
    ensure_platform_exists "$PLATFORM"
    PACKAGE_PATTERN="$PACKAGES_DIR"/*_"$PLATFORM".json
else
    PACKAGE_PATTERN="$PACKAGES_DIR"/*.json
fi

PACKAGE_FILES=()
shopt -s nullglob
for package_file in $PACKAGE_PATTERN; do
    PACKAGE_FILES+=("$package_file")
done
shopt -u nullglob

if [ "${#PACKAGE_FILES[@]}" -eq 0 ]; then
    usage_error "No package files found. Run build-package.sh first."
fi

# jq cannot read variable file paths from slurp mode portably, so enrich packages in bash.
{
    echo "{"
    printf '  "queue_id": %s,\n' "$(jq -Rn --arg v "$RUN_ID" '$v')"
    printf '  "timestamp": %s,\n' "$(jq -Rn --arg v "$(utc_now)" '$v')"
    printf '  "campaign_id": %s,\n' "$(jq -Rn --arg v "$CAMPAIGN_ID" '$v')"
    if [ -n "$PLATFORM" ]; then
        printf '  "platform": %s,\n' "$(jq -Rn --arg v "$PLATFORM" '$v')"
    else
        echo '  "platform": null,'
    fi
    echo '  "status": "ready_for_manual_publish",'
    echo '  "items": ['
    for i in "${!PACKAGE_FILES[@]}"; do
        file="${PACKAGE_FILES[$i]}"
        [ "$i" -gt 0 ] && echo ","
        jq --arg package_file "$file" '{package_file: $package_file, package: .}' "$file"
    done
    echo
    echo '  ]'
    echo "}"
} > "$QUEUE_FILE"

jq -n \
    --arg run_id "$RUN_ID" \
    --arg timestamp "$(utc_now)" \
    --arg campaign_id "$CAMPAIGN_ID" \
    --arg platform "$PLATFORM" \
    --arg queue_file "$QUEUE_FILE" \
    --argjson count "${#PACKAGE_FILES[@]}" '
    {
      run_id: $run_id,
      timestamp: $timestamp,
      campaign_id: $campaign_id,
      kind: "export_queue",
      status: "exported",
      platform: (if $platform == "" then null else $platform end),
      outputs: {
        queue_file: $queue_file,
        package_count: $count
      }
    }' > "$TMP_ENTRY"

append_manifest_entry "$CAMPAIGN_ID" "$TMP_ENTRY"
rm -f "$TMP_ENTRY"

echo "$QUEUE_FILE"
