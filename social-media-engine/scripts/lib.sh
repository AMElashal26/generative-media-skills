#!/bin/bash

set -euo pipefail

ENGINE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$ENGINE_SCRIPT_DIR/.." && pwd)"

if [ -n "${GENERATIVE_MEDIA_SKILLS_ROOT:-}" ]; then
    SKILLS_ROOT="$GENERATIVE_MEDIA_SKILLS_ROOT"
else
    SKILLS_ROOT="$(cd "$ENGINE_ROOT/.." && pwd)"
fi

CAMPAIGNS_DIR="${SOCIAL_ENGINE_CAMPAIGNS_DIR:-$ENGINE_ROOT/campaigns}"
PLATFORMS_FILE="$ENGINE_ROOT/config/platforms.json"

require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required." >&2
        exit 1
    fi
}

usage_error() {
    echo "Error: $1" >&2
    exit 1
}

campaign_dir() {
    local campaign_id="$1"
    echo "$CAMPAIGNS_DIR/$campaign_id"
}

campaign_manifest() {
    local campaign_id="$1"
    echo "$(campaign_dir "$campaign_id")/manifest.jsonl"
}

ensure_campaign_exists() {
    local campaign_id="$1"
    local dir
    dir="$(campaign_dir "$campaign_id")"
    if [ ! -f "$dir/campaign.json" ]; then
        usage_error "Campaign '$campaign_id' does not exist. Run init-campaign.sh first."
    fi
}

ensure_platform_exists() {
    local platform="$1"
    require_jq
    if ! jq -e --arg platform "$platform" '.[$platform]' "$PLATFORMS_FILE" >/dev/null; then
        usage_error "Unknown platform '$platform'. See $PLATFORMS_FILE."
    fi
}

new_run_id() {
    local prefix="${1:-run}"
    printf "%s_%s_%s" "$prefix" "$(date -u +%Y%m%dT%H%M%SZ)" "$$"
}

utc_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

append_manifest_entry() {
    local campaign_id="$1"
    local entry_file="$2"
    local manifest
    manifest="$(campaign_manifest "$campaign_id")"
    mkdir -p "$(dirname "$manifest")"
    jq -c . "$entry_file" >> "$manifest"
}

latest_manifest_entry() {
    local campaign_id="$1"
    local kind_filter="${2:-}"
    local manifest
    manifest="$(campaign_manifest "$campaign_id")"
    if [ ! -s "$manifest" ]; then
        return 1
    fi
    if [ -n "$kind_filter" ]; then
        jq -s -c --arg kind "$kind_filter" 'map(select(.kind == $kind)) | last // empty' "$manifest"
    else
        jq -s -c 'last // empty' "$manifest"
    fi
}

platform_value() {
    local platform="$1"
    local key="$2"
    jq -r --arg platform "$platform" --arg key "$key" '.[$platform][$key] // empty' "$PLATFORMS_FILE"
}
