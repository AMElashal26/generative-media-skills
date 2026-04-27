#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CAMPAIGN_ID=""
PLATFORM="instagram"
PROMPT=""
CAMERA=""
MODE=""
TIER=""
QUALITY=""
DURATION=""
ASPECT=""
RUN=false
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --campaign-id) CAMPAIGN_ID="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --camera) CAMERA="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --tier) TIER="$2"; shift 2 ;;
        --quality|-q) QUALITY="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --aspect) ASPECT="$2"; shift 2 ;;
        --run) RUN=true; shift ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do EXTRA_ARGS+=("$1"); shift; done
            ;;
        --help|-h)
            cat <<'HELP'
Generate or queue a social video run.

By default this records a planned command in the campaign ledger. Pass --run to
execute the parent generative-media-skills social video script and record the
JSON response.

Usage:
  bash generate-video.sh --campaign-id ID --platform instagram --prompt TEXT [--run]

Options after -- are passed through to run-social-video.sh.
HELP
            exit 0 ;;
        *) EXTRA_ARGS+=("$1"); shift ;;
    esac
done

require_jq
[ -n "$CAMPAIGN_ID" ] || usage_error "--campaign-id is required."
[ -n "$PROMPT" ] || usage_error "--prompt is required."
ensure_campaign_exists "$CAMPAIGN_ID"
ensure_platform_exists "$PLATFORM"

SOCIAL_VIDEO_SCRIPT="$SKILLS_ROOT/library/social/social-media-video/scripts/run-social-video.sh"
[ -f "$SOCIAL_VIDEO_SCRIPT" ] || usage_error "Social video script not found at $SOCIAL_VIDEO_SCRIPT."

ASPECT="${ASPECT:-$(platform_value "$PLATFORM" aspect)}"
DURATION="${DURATION:-$(platform_value "$PLATFORM" duration_seconds)}"
RUN_ID="$(new_run_id video)"
ENTRY_FILE="$(mktemp)"

COMMAND=(bash "$SOCIAL_VIDEO_SCRIPT" --prompt "$PROMPT" --platform "$PLATFORM" --async)
[ -n "$CAMERA" ] && COMMAND+=(--camera "$CAMERA")
[ -n "$MODE" ] && COMMAND+=(--mode "$MODE")
[ -n "$TIER" ] && COMMAND+=(--tier "$TIER")
[ -n "$QUALITY" ] && COMMAND+=(--quality "$QUALITY")
[ -n "$ASPECT" ] && COMMAND+=(--aspect "$ASPECT")
[ -n "$DURATION" ] && COMMAND+=(--duration "$DURATION")
for arg in "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"; do COMMAND+=("$arg"); done

if [ "$RUN" = true ]; then
    OUTPUT_FILE="$(mktemp)"
    STATUS="completed"
    if ! "${COMMAND[@]}" > "$OUTPUT_FILE"; then
        STATUS="failed"
    fi
    if ! jq -e . "$OUTPUT_FILE" >/dev/null 2>&1; then
        RAW_OUTPUT="$(cat "$OUTPUT_FILE")"
        jq -n --arg raw "$RAW_OUTPUT" '{raw_text: $raw}' > "$OUTPUT_FILE.json"
        mv "$OUTPUT_FILE.json" "$OUTPUT_FILE"
    fi

    jq -n \
        --arg run_id "$RUN_ID" \
        --arg timestamp "$(utc_now)" \
        --arg campaign_id "$CAMPAIGN_ID" \
        --arg platform "$PLATFORM" \
        --arg status "$STATUS" \
        --arg prompt "$PROMPT" \
        --argjson command "$(printf '%s\n' "${COMMAND[@]}" | jq -R . | jq -s .)" \
        --slurpfile outputs "$OUTPUT_FILE" \
        '{
          run_id: $run_id,
          timestamp: $timestamp,
          campaign_id: $campaign_id,
          kind: "video_generation",
          status: $status,
          platform: $platform,
          prompt: $prompt,
          command: $command,
          outputs: ($outputs[0] // {})
        }' > "$ENTRY_FILE"
else
    jq -n \
        --arg run_id "$RUN_ID" \
        --arg timestamp "$(utc_now)" \
        --arg campaign_id "$CAMPAIGN_ID" \
        --arg platform "$PLATFORM" \
        --arg prompt "$PROMPT" \
        --argjson command "$(printf '%s\n' "${COMMAND[@]}" | jq -R . | jq -s .)" \
        '{
          run_id: $run_id,
          timestamp: $timestamp,
          campaign_id: $campaign_id,
          kind: "video_generation",
          status: "planned",
          platform: $platform,
          prompt: $prompt,
          command: $command,
          outputs: {}
        }' > "$ENTRY_FILE"
fi

append_manifest_entry "$CAMPAIGN_ID" "$ENTRY_FILE"
jq . "$ENTRY_FILE"
rm -f "$ENTRY_FILE" "${OUTPUT_FILE:-}"
