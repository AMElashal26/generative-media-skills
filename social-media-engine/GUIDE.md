# Social Media Engine Operating Guide

This guide explains how to use `social-media-engine`, how it operates, what
state is written where, how metrics close the loop, and how to test changes.

## Purpose

`social-media-engine` is the operating layer above the generative media skills.
It does not try to replace `core/` or `library/`. Instead, it answers these
questions:

- What campaign are we working on?
- Which platform is this asset for?
- What did we ask the generator to make?
- What outputs, packages, queue files, and metrics came back?
- What should the next generation learn from prior results?

The parent repository remains responsible for generating and editing media.
This engine is responsible for campaign memory, packaging, export readiness, and
feedback.

## Mental model

```text
Campaign setup
  -> Planned or executed generation
  -> Platform package
  -> Manual publishing queue
  -> Metrics import
  -> Performance summary
  -> Better next prompt
```

Each step appends an event to `campaigns/<campaign-id>/manifest.jsonl`. The
manifest is the durable source of truth.

## Directory responsibilities

```text
social-media-engine/
  README.md                 quick start and repository overview
  GUIDE.md                  operating guide
  config/
    platforms.json          platform defaults and safe-zone guidance
    campaign.example.json   example campaign shape
  schemas/
    campaign.schema.json
    manifest-entry.schema.json
  scripts/
    lib.sh                  shared path, platform, ledger helpers
    init-campaign.sh        creates campaign state
    generate-video.sh       records or runs a social video generation
    build-package.sh        creates upload-ready platform packages
    export-queue.sh         creates manual publishing queue files
    import-metrics.sh       imports platform analytics snapshots
    summarize-performance.sh summarizes metrics and recent packages
  campaigns/
    <campaign-id>/          local runtime state, ignored by default if split
```

When extracted into its own repository, point it at the media skill library:

```bash
export GENERATIVE_MEDIA_SKILLS_ROOT=/path/to/generative-media-skills
```

When kept inside this repository, scripts auto-detect the parent directory.

## Runtime configuration

The scripts are intentionally environment-light so they can run inside this
monorepo or after `social-media-engine/` is split into its own repository.

| Setting | Used by | Default | When to set it |
| --- | --- | --- | --- |
| `GENERATIVE_MEDIA_SKILLS_ROOT` | `generate-video.sh` through `lib.sh` | Parent directory of `social-media-engine/` | Set this after extracting the engine into a separate repository. |
| `SOCIAL_ENGINE_CAMPAIGNS_DIR` | All campaign scripts through `lib.sh` | `social-media-engine/campaigns` | Set this for smoke tests, CI, or shared runtime state outside the repo. |
| `MUAPI_KEY` | Parent social video skill when `--run` is used | None | Required only for real media generation. Planned runs, packaging, exports, and metrics imports do not need it. |

Platform defaults are local data, not remote API state. Add or edit platforms in
`config/platforms.json`, then use `ensure_platform_exists` validation by running
the lifecycle smoke test below.

## Lifecycle

### 1. Initialize a campaign

Use `init-campaign.sh` before any generation. It creates the campaign directory,
standard subdirectories, `campaign.json`, and the first manifest entry.

```bash
bash social-media-engine/scripts/init-campaign.sh \
  --campaign-id coldbrew-launch \
  --name "Cold Brew Launch" \
  --objective "Generate short-form launch assets" \
  --platforms instagram,youtube-short,tiktok,threads \
  --notes "Premium macro product campaign"
```

What happens:

- `campaigns/coldbrew-launch/campaign.json` is created.
- `assets/`, `briefs/`, `metrics/`, `packages/`, and `queue/` are created.
- `manifest.jsonl` gets a `campaign_initialized` entry.

Why this matters:

- Later steps can validate the campaign exists.
- All future outputs have a stable campaign ID.
- Multiple campaigns can run independently.

### 2. Plan a generation

By default, `generate-video.sh` records a planned command without spending MuAPI
credits.

```bash
bash social-media-engine/scripts/generate-video.sh \
  --campaign-id coldbrew-launch \
  --platform instagram \
  --camera product \
  --prompt "0-3s: macro cold brew bottle reveal on black marble; 3-7s: slow orbit; 7-10s: CTA hold"
```

What happens:

- Platform defaults are read from `config/platforms.json`.
- A command for `library/social/social-media-video/scripts/run-social-video.sh`
  is assembled with `--async`, platform, aspect, duration, and camera settings.
- A `video_generation` entry with `status: "planned"` is appended to
  `manifest.jsonl`.

Why this matters:

- You can review prompts and package drafts before spending credits.
- Content calendars can be planned as ledger entries.
- The exact eventual generation command is preserved.

### 3. Execute a generation

Add `--run` when you want to call the parent media generation script.

```bash
bash social-media-engine/scripts/generate-video.sh \
  --campaign-id coldbrew-launch \
  --platform instagram \
  --camera product \
  --prompt "0-3s: macro cold brew bottle reveal..." \
  --run
```

What happens:

- The same command is executed through the existing social video skill.
- Output JSON is captured when available.
- A `video_generation` entry is appended with `status: "completed"` or
  `status: "failed"`.

Why this matters:

- The engine keeps orchestration and lineage while generation remains delegated.
- Failures are still useful because the attempted command is recorded.
- Future tooling can poll request IDs or hydrate output URLs from the manifest.

### 4. Build a platform package

Use `build-package.sh` after planning or running a generation. It uses the latest
`video_generation` entry unless `--source-run-id` is provided.

```bash
bash social-media-engine/scripts/build-package.sh \
  --campaign-id coldbrew-launch \
  --platform instagram \
  --caption "Precision brewed. Zero compromise." \
  --hashtags "#coldbrew,#coffee,#launch" \
  --cta "Try the launch blend" \
  --thumbnail-prompt "Cold brew bottle on black marble with gold rim light"
```

What happens:

- A package JSON file is written under `packages/`.
- Platform defaults, safe-zone guidance, caption fields, source prompt, source
  run ID, media URL, and local file path are included when available.
- A `package` entry is appended to `manifest.jsonl`.

Why this matters:

- Upload details stay separate from generation details.
- One generated asset can have different packages for different platforms.
- Manual or automated publishing can consume the same package format.

### 5. Export a manual publishing queue

Use `export-queue.sh` to gather packages into an upload-ready queue.

```bash
bash social-media-engine/scripts/export-queue.sh \
  --campaign-id coldbrew-launch \
  --platform instagram
```

What happens:

- Matching package files are copied into a queue JSON structure under `queue/`.
- The queue file contains package file paths and package contents.
- An `export_queue` entry is appended to `manifest.jsonl`.

Why this matters:

- Publishing stays export-first and credential-free.
- A human can upload from the queue.
- Future publisher adapters can read the queue without changing generation.

Queue files are snapshots. If package metadata changes after export, run
`export-queue.sh` again to create a new queue entry rather than editing an old
queue file in place.

### 6. Import metrics

After publishing manually or through a future adapter, export platform metrics to
a JSON file and import them.

Example metrics file:

```json
{
  "views": 1200,
  "likes": 87,
  "comments": 9,
  "shares": 14,
  "saves": 31,
  "watch_time_seconds": 940,
  "retention_percent": 41.5,
  "notes": "Strong hook, weak CTA"
}
```

Import command:

```bash
bash social-media-engine/scripts/import-metrics.sh \
  --campaign-id coldbrew-launch \
  --platform instagram \
  --source-run-id video_20260427T031631Z_6123 \
  --metrics-file ./metrics/coldbrew-instagram-day1.json \
  --notes "Day 1 manual import"
```

What happens:

- The metrics JSON is normalized with `jq` and copied to `metrics/`.
- A `metrics` entry is appended to `manifest.jsonl`.

Why this matters:

- Analytics become part of the same campaign memory as prompts and packages.
- Imported metrics can be summarized without platform API credentials.
- Later prompt planning can compare creative choices against outcomes.

### 7. Summarize performance

Use `summarize-performance.sh` to produce an aggregate feedback object.

```bash
bash social-media-engine/scripts/summarize-performance.sh \
  --campaign-id coldbrew-launch
```

What happens:

- Manifest entries are read as one event stream.
- Totals are calculated for generations, packages, exports, metrics, views,
  likes, comments, shares, and saves.
- Recent package captions and hashtags are surfaced.
- A short `feedback_prompt` is emitted for planning future variants.

Why this matters:

- This is the first feedback loop for continuous generation.
- It is intentionally simple and inspectable.
- The output can be pasted into an agent prompt or used by future scripts.

## Metrics model

The importer accepts arbitrary platform JSON, but these fields are recommended:

| Field | Meaning | Why it matters |
| --- | --- | --- |
| `views` | Reach or plays | Measures distribution |
| `likes` | Lightweight positive signal | Measures broad appeal |
| `comments` | Conversation signal | Measures prompt/comment resonance |
| `shares` | Virality signal | Measures usefulness or emotional pull |
| `saves` | Durable value signal | Measures reference value |
| `watch_time_seconds` | Total watch time | Helps compare retention by duration |
| `retention_percent` | Percent watched | Helps improve opening and pacing |
| `clicks` | Link or profile clicks | Measures CTA effectiveness |
| `notes` | Human observations | Captures qualitative learning |

Recommended practice:

- Import metrics per platform and per source run when possible.
- Keep raw platform exports in `metrics/` instead of only entering summaries.
- Use notes for qualitative context that numbers do not capture.
- Compare creative variables: hook family, visual motif, CTA, duration, platform.

## Data contracts

These files are the public interface between the engine, agents, manual
operators, and future publisher adapters.

### Campaign record

`campaign.json` is created by `init-campaign.sh` and must include:

- `campaign_id`: lowercase letters, numbers, dots, underscores, or hyphens.
- `name`, `objective`, `platforms`, and `created_at`.
- Optional `notes`, `brand_files`, and cadence or creative metadata.

The schema is intentionally permissive (`additionalProperties: true`) so teams
can attach brand, client, or schedule metadata without changing scripts.

### Manifest ledger

`manifest.jsonl` is append-only. Each line is one JSON object with the shared
fields from `schemas/manifest-entry.schema.json`:

- `run_id`, `timestamp`, `campaign_id`, `kind`, and `status`.
- Optional linkage fields such as `platform`, `source_run_id`, `prompt`,
  `command`, `outputs`, `package`, `metrics`, and `notes`.

Current `kind` values are `campaign_initialized`, `video_generation`,
`package`, `export_queue`, `metrics`, and `note`. Scripts read the ledger with
`jq -s`, so keep each event on a single valid JSON line.

### Package files

`build-package.sh` writes `packages/<package_id>_<platform>.json`. A package
contains:

- `media`: source prompt plus `video_url` or `local_file` when available.
- `upload`: title, caption, description, hashtags, CTA, thumbnail prompt,
  alt text, post text, sound note, and reply prompt.
- `platform_defaults`: aspect ratio, duration, and safe-zone text copied from
  `config/platforms.json`.
- `status: "ready_for_export"`.

Hashtags can be passed as comma-separated or space-separated text; the script
normalizes them to an array.

### Queue files

`export-queue.sh` writes `queue/<queue_id>.json` with:

- `status: "ready_for_manual_publish"`.
- `items[]`, where each item includes the original `package_file` path and the
  package JSON content.
- Optional `platform`; it is `null` when exporting all package files.

Publisher adapters should consume queue files or package files, then append a
new manifest event instead of mutating existing package or queue records.

## Extension points

### Add a platform

1. Add a key to `config/platforms.json` with `label`, `aspect`,
   `duration_seconds`, `format`, `safe_zone`, `package_fields`, and
   `publishing`.
2. If real generation should use a matching default, update the platform case in
   `library/social/social-media-video/scripts/run-social-video.sh`.
3. Run the no-credit smoke test with `--platform <new-platform>`.

The engine can package any platform present in `config/platforms.json`, but the
parent social video skill owns generation defaults.

### Add a publisher adapter

Keep publishing separate from generation:

1. Read a queue file from `campaigns/<campaign-id>/queue/`.
2. Upload using the platform API and credentials outside this engine.
3. Append a new manifest event with `kind: "note"` or a future publisher kind,
   including published URLs, account IDs, and API response references.

Do not make `generate-video.sh` depend on OAuth, token refresh, or platform
quota; those concerns belong in publisher adapters.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `jq is required` | `jq` is not installed or not on `PATH`. | Install `jq` before running any engine script. |
| `Campaign '<id>' does not exist` | A lifecycle step ran before initialization or with a different campaigns directory. | Run `init-campaign.sh` first, or check `SOCIAL_ENGINE_CAMPAIGNS_DIR`. |
| `Unknown platform` | The platform key is missing from `config/platforms.json`. | Add the platform defaults or use an existing key such as `instagram`, `youtube-short`, `tiktok`, `threads`, or `linkedin`. |
| `Social video script not found` | The engine cannot locate the parent skills repo. | Set `GENERATIVE_MEDIA_SKILLS_ROOT` to the `generative-media-skills` checkout. |
| `MUAPI_KEY is not set` | `generate-video.sh --run` delegated to the parent skill without credentials. | Configure `MUAPI_KEY` or omit `--run` for a planned ledger entry. |
| `No video_generation manifest entry found` | Packaging ran before planning or executing a generation. | Run `generate-video.sh` first, then package the resulting `run_id`. |
| `No package files found` | Queue export ran before package creation, or the platform filter excluded all packages. | Run `build-package.sh`, or retry export without `--platform` to inspect all packages. |
| Performance summary totals are zero | Metrics were not imported, or metric values are non-numeric strings. | Import a JSON metrics file with numeric `views`, `likes`, `comments`, `shares`, and `saves` fields. |

## Testing

### Syntax and JSON validation

Run these before committing script or config changes:

```bash
bash -n social-media-engine/scripts/*.sh

jq empty \
  social-media-engine/config/platforms.json \
  social-media-engine/config/campaign.example.json \
  social-media-engine/schemas/campaign.schema.json \
  social-media-engine/schemas/manifest-entry.schema.json
```

### Smoke test without MuAPI credits

Use a temporary campaigns directory so tests do not write into real campaign
state.

```bash
TMPDIR=$(mktemp -d)
export SOCIAL_ENGINE_CAMPAIGNS_DIR="$TMPDIR/campaigns"

bash social-media-engine/scripts/init-campaign.sh \
  --campaign-id smoke \
  --name "Smoke Test" \
  --objective "Verify social engine" \
  --platforms instagram,youtube-short

bash social-media-engine/scripts/generate-video.sh \
  --campaign-id smoke \
  --platform instagram \
  --camera product \
  --prompt "0-3s: product reveal with clear hook" \
  > "$TMPDIR/video.json"

SOURCE_RUN_ID=$(jq -r '.run_id' "$TMPDIR/video.json")

bash social-media-engine/scripts/build-package.sh \
  --campaign-id smoke \
  --platform instagram \
  --source-run-id "$SOURCE_RUN_ID" \
  --caption "Hook caption" \
  --hashtags "#test,#reel" \
  --cta "Follow for more"

bash social-media-engine/scripts/export-queue.sh \
  --campaign-id smoke \
  --platform instagram

printf '{"views":100,"likes":12,"comments":2,"shares":3,"saves":4}' \
  > "$TMPDIR/metrics.json"

bash social-media-engine/scripts/import-metrics.sh \
  --campaign-id smoke \
  --platform instagram \
  --source-run-id "$SOURCE_RUN_ID" \
  --metrics-file "$TMPDIR/metrics.json"

bash social-media-engine/scripts/summarize-performance.sh \
  --campaign-id smoke \
  > "$TMPDIR/summary.json"

jq -e '.totals.metric_snapshots == 1 and .totals.views == 100' \
  "$TMPDIR/summary.json"

rm -rf "$TMPDIR"
```

This validates the lifecycle without calling MuAPI because `generate-video.sh`
does not execute generation unless `--run` is passed.

### Generation test with MuAPI

Only run this when `MUAPI_KEY` is configured and you intend to spend credits:

```bash
bash social-media-engine/scripts/generate-video.sh \
  --campaign-id smoke \
  --platform instagram \
  --prompt "0-3s: simple branded product reveal" \
  --run
```

Use this sparingly. Most engine changes should be validated through planned
runs, package output, queue output, and metrics summaries.

## When to use each step

| Moment | Script | Reason |
| --- | --- | --- |
| New campaign, client, product, or series | `init-campaign.sh` | Creates durable state and boundaries |
| Before spending credits | `generate-video.sh` without `--run` | Plans prompt and exact command |
| When creative brief is approved | `generate-video.sh --run` | Executes generation through parent skill |
| Before upload | `build-package.sh` | Creates platform-specific metadata |
| For manual publishing | `export-queue.sh` | Produces an upload checklist/queue |
| After publishing | `import-metrics.sh` | Adds performance data to campaign memory |
| Before next iteration | `summarize-performance.sh` | Turns prior results into prompt guidance |

## Operating principles

- Keep generation scripts focused on generation.
- Keep campaign state append-only and inspectable.
- Package per platform because caption, safe-zone, and CTA needs differ.
- Treat publishing adapters as optional consumers of queue files.
- Import metrics even if they are manual; incomplete metrics are better than no
  feedback loop.
- Prefer planned runs for reviews and tests; use `--run` only when generation is
  intended.

## Future extensions

Good next additions:

- `generate-episode.sh`: reads recent ledger entries and creates a next episode
  brief.
- `generate-variants.sh`: creates A/B prompt variants for a selected platform.
- `publish-youtube.sh`: consumes queue files and uploads through YouTube Data
  API credentials.
- `publish-instagram.sh`: consumes queue files and uploads through Meta Graph
  API credentials.
- `poll-generation.sh`: refreshes async request IDs and attaches final output
  URLs to the ledger.
- richer performance summaries by platform, hook family, CTA, and visual motif.
