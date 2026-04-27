#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

CAMPAIGN_ID=""
SOURCE_RUN_ID=""
PLATFORM=""
METRICS_FILE=""
NOTES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --campaign-id) CAMPAIGN_ID="$2"; shift 2 ;;
        --source-run-id) SOURCE_RUN_ID="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --metrics-file) METRICS_FILE="$2"; shift 2 ;;
        --notes) NOTES="$2"; shift 2 ;;
        --help|-h)
            cat <<'HELP'
Import social metrics into a campaign ledger.

Usage:
  bash import-metrics.sh --campaign-id ID --platform instagram --metrics-file metrics.json

The metrics file can contain any platform export shape. Recommended fields:
views, likes, comments, shares, saves, watch_time_seconds, retention_percent.
HELP
            exit 0 ;;
        *) usage_error "Unknown argument '$1'" ;;
    esac
done

[ -n "$CAMPAIGN_ID" ] || usage_error "--campaign-id is required"
[ -n "$PLATFORM" ] || usage_error "--platform is required"
[ -n "$METRICS_FILE" ] || usage_error "--metrics-file is required"
[ -f "$METRICS_FILE" ] || usage_error "Metrics file not found: $METRICS_FILE"

require_jq
ensure_campaign_exists "$CAMPAIGN_ID"
ensure_platform_exists "$PLATFORM"

RUN_ID="$(new_run_id metrics)"
DEST_DIR="$(campaign_dir "$CAMPAIGN_ID")/metrics"
mkdir -p "$DEST_DIR"
DEST_FILE="$DEST_DIR/${RUN_ID}_${PLATFORM}.json"
jq . "$METRICS_FILE" > "$DEST_FILE"

ENTRY_FILE="$(mktemp)"
jq -n \
    --arg run_id "$RUN_ID" \
    --arg timestamp "$(utc_now)" \
    --arg campaign_id "$CAMPAIGN_ID" \
    --arg platform "$PLATFORM" \
    --arg source_run_id "$SOURCE_RUN_ID" \
    --arg metrics_file "$DEST_FILE" \
    --arg notes "$NOTES" \
    --slurpfile metrics "$DEST_FILE" \
    '{
      run_id: $run_id,
      timestamp: $timestamp,
      campaign_id: $campaign_id,
      kind: "metrics",
      status: "completed",
      platform: $platform,
      metrics: $metrics[0],
      outputs: {
        metrics_file: $metrics_file
      }
    }
    + (if $source_run_id == "" then {} else {source_run_id: $source_run_id} end)
    + (if $notes == "" then {} else {notes: $notes} end)' > "$ENTRY_FILE"

append_manifest_entry "$CAMPAIGN_ID" "$ENTRY_FILE"
rm -f "$ENTRY_FILE"

echo "Imported metrics: $DEST_FILE"
