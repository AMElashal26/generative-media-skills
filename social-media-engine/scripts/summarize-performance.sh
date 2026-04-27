#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CAMPAIGN_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --campaign-id) CAMPAIGN_ID="$2"; shift 2 ;;
        --help|-h)
            cat <<'HELP'
Usage: bash summarize-performance.sh --campaign-id ID

Summarizes imported metrics and recent packages for a campaign. This is an
export-friendly feedback layer; it does not call platform APIs.
HELP
            exit 0 ;;
        *) usage_error "Unknown argument '$1'" ;;
    esac
done

[ -n "$CAMPAIGN_ID" ] || usage_error "--campaign-id is required."
ensure_campaign_exists "$CAMPAIGN_ID"
require_jq

MANIFEST="$(campaign_manifest "$CAMPAIGN_ID")"
[ -s "$MANIFEST" ] || usage_error "No manifest entries found for '$CAMPAIGN_ID'."

jq -s '
  def metric_num($name):
    [.[] | select(.kind == "metrics") | .metrics[$name] // empty | tonumber?] | add // 0;

  {
    campaign_id: $campaign_id,
    generated_at: $generated_at,
    totals: {
      video_generations: ([.[] | select(.kind == "video_generation")] | length),
      packages: ([.[] | select(.kind == "package")] | length),
      exports: ([.[] | select(.kind == "export_queue")] | length),
      metric_snapshots: ([.[] | select(.kind == "metrics")] | length),
      views: metric_num("views"),
      likes: metric_num("likes"),
      comments: metric_num("comments"),
      shares: metric_num("shares"),
      saves: metric_num("saves")
    },
    recent_packages: [
      .[]
      | select(.kind == "package")
      | {
          run_id,
          platform,
          timestamp,
          source_run_id,
          caption: (.package.upload.caption // .package.upload.post_text // .package.upload.description // ""),
          hashtags: (.package.upload.hashtags // [])
        }
    ][-5:],
    feedback_prompt: (
      "Review the campaign ledger for recurring hooks, platforms, and metrics. " +
      "Prefer future variants that preserve high-performing motifs, open with a clear 0-3s hook, " +
      "and keep platform-safe text placement."
    )
  }
' --arg campaign_id "$CAMPAIGN_ID" --arg generated_at "$(utc_now)" "$MANIFEST"
