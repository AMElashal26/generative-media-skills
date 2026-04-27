# Social Media Generation Engine

A small, repo-shaped operating layer for continuous generative social media.

This engine is intentionally separate from the media skill library. It decides
what to generate, records what happened, packages outputs for platforms, and
leaves model execution to `generative-media-skills`.

## Relationship to the parent repo

```text
generative-media-skills/
  core/ and library/     media generation primitives

social-media-engine/
  campaigns/            local campaign state, manifests, packages, metrics
  scripts/              orchestration, packaging, export queue, summaries
  schemas/              JSON contracts for durable records
  config/               example campaign and platform defaults
```

When extracted into its own repository, set:

```bash
export GENERATIVE_MEDIA_SKILLS_ROOT=/path/to/generative-media-skills
```

When used inside this repository, the scripts auto-detect the parent directory.

## Quick start

```bash
# 1. Create durable campaign state
bash social-media-engine/scripts/init-campaign.sh \
  --campaign-id coldbrew-launch \
  --name "Cold Brew Launch" \
  --objective "Generate daily short-form launch assets" \
  --platforms instagram,youtube-short,tiktok,threads

# 2. Generate or queue a social video run
bash social-media-engine/scripts/generate-video.sh \
  --campaign-id coldbrew-launch \
  --platform instagram \
  --camera product \
  --prompt "0-3s: macro cold brew bottle reveal on black marble..."

# 3. Build platform upload packages from the latest manifest entry
bash social-media-engine/scripts/build-package.sh \
  --campaign-id coldbrew-launch \
  --platform instagram \
  --caption "Precision brewed. Zero compromise." \
  --hashtags "#coldbrew,#coffee,#launch"

# 4. Export a manual publishing queue
bash social-media-engine/scripts/export-queue.sh \
  --campaign-id coldbrew-launch
```

To inspect the feedback loop after importing metrics:

```bash
bash social-media-engine/scripts/import-metrics.sh \
  --campaign-id coldbrew-launch \
  --platform instagram \
  --metrics-file ./metrics/coldbrew-instagram.json

bash social-media-engine/scripts/summarize-performance.sh \
  --campaign-id coldbrew-launch
```

For the full operating model, see `[GUIDE.md](./GUIDE.md)`.

## Design goals

- Durable state: every run is recorded in `manifest.jsonl`.
- Successive output: future prompts can read prior assets and packages.
- Export-first: publishing can stay manual until API credentials exist.
- Adapter-friendly: YouTube, Instagram, TikTok, and Threads can be added later
without changing generation scripts.
- Repo split friendly: this folder can become its own project.

## Campaign layout

```text
campaigns/<campaign-id>/
  campaign.json          campaign metadata and platform targets
  manifest.jsonl         append-only generation/package/export ledger
  assets/                downloaded or copied media assets
  packages/              platform-specific upload packages
  queue/                 export-ready queue files
  metrics/               imported analytics snapshots
  briefs/                reusable prompts, storyboards, and episode notes
```

## Core systems

### Campaign ledger

`manifest.jsonl` is the source of truth. Each entry records:

- `run_id`
- `timestamp`
- `campaign_id`
- `kind` such as `video_generation`, `package`, `export_queue`, `metrics`
- prompts, platform, command, model outputs, request IDs, URLs, files
- status and notes

### Social package builder

`build-package.sh` creates platform-specific JSON files with:

- upload title/caption/description
- hashtags
- CTA
- safe-zone guidance
- recommended aspect/duration
- source manifest entry

### Continuous series

This first version establishes the durable state needed for continuous series.
The next layer can read `manifest.jsonl`, summarize previous posts, and generate
episode briefs or variants before invoking `generate-video.sh`.

`generate-video.sh` records a planned generation entry without calling MuAPI by
default. Add `--run` only when you want to spend generation credits and capture
the parent generation response in the ledger.

### Publisher layer

`export-queue.sh` produces manual publishing queue files. Official API adapters
should be added as separate scripts later, for example:

- `publish-youtube.sh`
- `publish-instagram.sh`
- `publish-tiktok.sh`
- `publish-threads.sh`

Keeping publishing separate avoids coupling generation to OAuth, token refresh,
quota, account eligibility, and review requirements.

## Platform defaults

Defaults live in `config/platforms.json`. The current short-form baseline is
9:16 vertical video for Instagram Reels, YouTube Shorts, TikTok, and Threads.

## Requirements

- Bash 3.2+
- `jq`
- The parent `generative-media-skills` repo or `GENERATIVE_MEDIA_SKILLS_ROOT`
- `MUAPI_KEY` configured if actually generating media

