#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

CAMPAIGN_ID=""
PLATFORM=""
SOURCE_RUN_ID=""
TITLE=""
CAPTION=""
DESCRIPTION=""
HASHTAGS=""
CTA=""
THUMBNAIL_PROMPT=""
ALT_TEXT=""
POST_TEXT=""
SOUND_NOTE=""
REPLY_PROMPT=""
NOTES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --campaign-id) CAMPAIGN_ID="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --source-run-id) SOURCE_RUN_ID="$2"; shift 2 ;;
        --title) TITLE="$2"; shift 2 ;;
        --caption) CAPTION="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --hashtags) HASHTAGS="$2"; shift 2 ;;
        --cta) CTA="$2"; shift 2 ;;
        --thumbnail-prompt) THUMBNAIL_PROMPT="$2"; shift 2 ;;
        --alt-text) ALT_TEXT="$2"; shift 2 ;;
        --post-text) POST_TEXT="$2"; shift 2 ;;
        --sound-note) SOUND_NOTE="$2"; shift 2 ;;
        --reply-prompt) REPLY_PROMPT="$2"; shift 2 ;;
        --notes) NOTES="$2"; shift 2 ;;
        --help|-h)
            cat <<'HELP'
Build a platform upload package from a campaign manifest entry.

Usage:
  bash build-package.sh --campaign-id ID --platform instagram [options]

Options:
  --source-run-id ID       Use a specific video_generation run.
  --title TEXT
  --caption TEXT
  --description TEXT
  --hashtags TEXT         Comma or space separated tags.
  --cta TEXT
  --thumbnail-prompt TEXT
  --alt-text TEXT
  --post-text TEXT
  --sound-note TEXT
  --reply-prompt TEXT
  --notes TEXT
HELP
            exit 0 ;;
        *) usage_error "Unknown argument '$1'" ;;
    esac
done

[ -n "$CAMPAIGN_ID" ] || usage_error "--campaign-id is required."
[ -n "$PLATFORM" ] || usage_error "--platform is required."

require_jq
ensure_campaign_exists "$CAMPAIGN_ID"
ensure_platform_exists "$PLATFORM"

CAMPAIGN_DIR="$(campaign_dir "$CAMPAIGN_ID")"
PACKAGE_DIR="$CAMPAIGN_DIR/packages"
mkdir -p "$PACKAGE_DIR"

if [ -n "$SOURCE_RUN_ID" ]; then
    SOURCE_ENTRY=$(jq -s -c --arg run_id "$SOURCE_RUN_ID" 'map(select(.run_id == $run_id)) | last // empty' "$(campaign_manifest "$CAMPAIGN_ID")")
else
    SOURCE_ENTRY=$(latest_manifest_entry "$CAMPAIGN_ID" "video_generation" || true)
fi

[ -n "$SOURCE_ENTRY" ] || usage_error "No video_generation manifest entry found for campaign '$CAMPAIGN_ID'."

SOURCE_RUN_ID=$(echo "$SOURCE_ENTRY" | jq -r '.run_id')
RUN_ID="$(new_run_id package)"
PACKAGE_FILE="$PACKAGE_DIR/${RUN_ID}_${PLATFORM}.json"
ENTRY_FILE="$(mktemp)"
PACKAGE_TMP="$(mktemp)"

ASPECT="$(platform_value "$PLATFORM" "aspect")"
DURATION="$(platform_value "$PLATFORM" "duration_seconds")"
SAFE_ZONE="$(platform_value "$PLATFORM" "safe_zone")"
LABEL="$(platform_value "$PLATFORM" "label")"
VIDEO_URL="$(echo "$SOURCE_ENTRY" | jq -r '.outputs.video_url // .outputs.raw.outputs[0] // empty')"
LOCAL_FILE="$(echo "$SOURCE_ENTRY" | jq -r '.outputs.local_file // empty')"
PROMPT="$(echo "$SOURCE_ENTRY" | jq -r '.prompt // empty')"

jq -n \
    --arg package_id "$RUN_ID" \
    --arg created_at "$(utc_now)" \
    --arg campaign_id "$CAMPAIGN_ID" \
    --arg platform "$PLATFORM" \
    --arg platform_label "$LABEL" \
    --arg source_run_id "$SOURCE_RUN_ID" \
    --arg title "$TITLE" \
    --arg caption "$CAPTION" \
    --arg description "$DESCRIPTION" \
    --arg hashtags "$HASHTAGS" \
    --arg cta "$CTA" \
    --arg thumbnail_prompt "$THUMBNAIL_PROMPT" \
    --arg alt_text "$ALT_TEXT" \
    --arg post_text "$POST_TEXT" \
    --arg sound_note "$SOUND_NOTE" \
    --arg reply_prompt "$REPLY_PROMPT" \
    --arg safe_zone "$SAFE_ZONE" \
    --arg aspect "$ASPECT" \
    --argjson duration "$DURATION" \
    --arg video_url "$VIDEO_URL" \
    --arg local_file "$LOCAL_FILE" \
    --arg source_prompt "$PROMPT" \
    --arg notes "$NOTES" \
    '{
      package_id: $package_id,
      created_at: $created_at,
      campaign_id: $campaign_id,
      platform: $platform,
      platform_label: $platform_label,
      source_run_id: $source_run_id,
      media: {
        video_url: $video_url,
        local_file: $local_file,
        source_prompt: $source_prompt
      },
      upload: {
        title: $title,
        caption: $caption,
        description: $description,
        hashtags: ($hashtags | gsub(" "; ",") | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))),
        cta: $cta,
        thumbnail_prompt: $thumbnail_prompt,
        alt_text: $alt_text,
        post_text: $post_text,
        sound_note: $sound_note,
        reply_prompt: $reply_prompt
      },
      platform_defaults: {
        aspect: $aspect,
        duration_seconds: $duration,
        safe_zone: $safe_zone
      },
      status: "ready_for_export",
      notes: $notes
    }' > "$PACKAGE_TMP"

mv "$PACKAGE_TMP" "$PACKAGE_FILE"

jq -n \
    --arg run_id "$RUN_ID" \
    --arg timestamp "$(utc_now)" \
    --arg campaign_id "$CAMPAIGN_ID" \
    --arg platform "$PLATFORM" \
    --arg source_run_id "$SOURCE_RUN_ID" \
    --arg package_file "$PACKAGE_FILE" \
    --slurpfile package "$PACKAGE_FILE" \
    '{
      run_id: $run_id,
      timestamp: $timestamp,
      campaign_id: $campaign_id,
      kind: "package",
      status: "completed",
      platform: $platform,
      source_run_id: $source_run_id,
      outputs: {
        package_file: $package_file
      },
      package: $package[0]
    }' > "$ENTRY_FILE"

append_manifest_entry "$CAMPAIGN_ID" "$ENTRY_FILE"
rm -f "$ENTRY_FILE"

echo "$PACKAGE_FILE"
