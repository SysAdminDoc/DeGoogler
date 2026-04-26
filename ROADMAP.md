# DeGoogler Roadmap

Three-part migration toolkit: React wizard, PowerShell WPF data processor, Tampermonkey browser assistant. Tracks work beyond v0.0.1.

## Planned Features

### Web App (Wizard)
- Expand the alternatives DB to include Android-only / iOS-only / self-hosted filters
- Add a "difficulty score" and "time estimate" per migration step so the plan is realistic
- Per-service risk callouts (e.g., "deleting Gmail without migrating recovery emails first = lockout")
- Plan export to iCalendar (`.ics`) so each phase lands on a real calendar
- Multi-profile support (personal vs work) with separate plan progress
- Offline-first PWA with `manifest.json` and service-worker cache so the wizard works without the net

### PowerShell Toolkit
- `-DryRun` flag on every tool (mirror Debloat-Win11's pattern) that reports planned actions without writing
- Resumable operations: every long-running tool writes a `.progress.json` checkpoint so crashes don't restart from zero
- Shared structured logging: JSONL at `%LOCALAPPDATA%\DeGoogler\logs\*.jsonl` plus the existing transcript
- Scripted Keep → Joplin / Obsidian converter (Google Keep Takeout → Markdown with labels → folder structure)
- Fit data converter (Google Fit / Google Takeout TCX/JSON → Apple Health XML / Garmin TCX / Strava bulk upload)
- Maps saved places → GeoJSON + GPX + KML
- Hangouts/Chat MBOX export → Matrix / Signal-compatible JSON
- ExifTool bundled offline so first run doesn't require a download

### Browser Assistant
- Shadow-DOM isolation for the overlay panel so Google UI updates can't break layout
- Drive Auditor: scan Drive for shared-with-link docs and produce a risk list
- Forms Auditor: list all Forms still collecting responses
- Calendar Auditor: enumerate external subscriptions and sharing
- One-click "download all pending Takeout exports" (polling Takeout's status page)
- Persist audit state across sessions via `GM_setValue` with encrypted-at-rest flag

### Cross-Cutting
- Deep link the Web App to the right PowerShell tool ("open Takeout Extractor with this folder preselected")
- Shared schema for the migration plan (`plan.json`) consumed by the assistant and the toolkit — progress stays in sync
- Versioned `alternatives.json` pulled from the repo so the wizard always has fresh suggestions without a rebuild

### Packaging
- Sign the PowerShell script with an Authenticode cert once available; publish SHA256SUMS today
- GitHub Pages deploy of the Web App via Actions; auto-publish on `main` push
- Release bundle: assistant `.user.js` + toolkit `.ps1` + Web App static files as a single `.zip`
- Tamper-resistant self-update prompt for the PowerShell toolkit (check GitHub releases API, download verified binary)

## Competitive Research

- **Swiss Post / Proton Easy Switch** — Automates Gmail + Contacts + Calendar import into Proton; validates the direction but locks into one destination. DeGoogler's multi-destination plan is the differentiator.
- **PrivacyTools / PrivacyGuides alternatives lists** — Curated lists without workflow automation; DeGoogler should link to them as references instead of duplicating.
- **Takeout Viewer / Takeout-Importer (GitHub)** — Community tools that parse Takeout archives; worth linking and optionally adopting where quality is high (e.g., Photos EXIF fixers).
- **Bitwarden / Proton Pass importers** — Built-in Chrome/CSV converters. DeGoogler's password converter should defer to their native importers when possible and only fill the gaps (KeePass, 1Password formats).

## Nice-to-Haves

- Web App "progress dashboard" with charts (services migrated per week, categories cleared)
- Browser assistant integration with password managers: after setting a standalone password on a service, auto-save it into Bitwarden via the web clipper API
- Recovery-email sweeper: crawls common services via reset-email detection to surface accounts that silently still rely on Gmail
- "Reverse mode" — given a new email, find every service that sends mail to it and build a migration checklist in the opposite direction
- Localization (i18n) for at least EN/ES/DE/FR on the Web App
- Docker image of the Web App for self-hosters that don't want to use GitHub Pages

## Open-Source Research (Round 2)

### Related OSS Projects
- **tycrek/degoogle** — https://github.com/tycrek/degoogle — The canonical curated list of Google-product alternatives + privacy tips.
- **TheLastGimbus/GooglePhotosTakeoutHelper** — https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper — Consolidates Takeout album/yearly-folder chaos into one chronological tree; recommends Syncthing/Immich/Photoprism/Nextcloud as downstream targets.
- **simulot/immich-go** — https://github.com/simulot/immich-go — Go CLI, no Node dependency, specializes in `from-google-photos`, burst stacking, 100k+ scale, Picasa `.picasa.ini` import.
- **garzj/google-photos-migrate** — https://github.com/garzj/google-photos-migrate — Docker/Podman image that fixes EXIF and preserves album directory structure.
- **alexdachin/gophix** — https://github.com/alexdachin/gophix — Writes EXIF directly when supported, XMP sidecar when not (via ExifTool).
- **mattwilson1024/google-photos-exif** — https://github.com/mattwilson1024/google-photos-exif — Focused on populating `DateTimeOriginal` from JSON sidecars.
- **xob0t/Google-Photos-Toolkit** — https://github.com/xob0t/Google-Photos-Toolkit — Covers the gaps Takeout leaves (shared-with-you photos that weren't saved to library).
- **couzteau/Degoogle-Photos** — https://github.com/couzteau/Degoogle-Photos — EXIF > JSON > filename > mtime priority cascade, MD5 dedup, resumable.
- **theophanemayaud/google-takeout-fix-json-metadata-files** — https://github.com/theophanemayaud/google-takeout-fix-json-metadata-files — Pre-pass that repairs Takeout's own JSON-sidecar naming mess.

### Features to Borrow
- EXIF > JSON > filename > mtime priority cascade for "best guess" date — borrow from `couzteau/Degoogle-Photos`.
- Resumable checkpointing so partial Takeout runs can restart without re-copying — borrow from `couzteau/Degoogle-Photos`.
- `.picasa.ini` ingestion for users with older Picasa backups predating Google Photos — borrow from `immich-go`.
- Burst-photo stacking detection (timestamp + filename pattern) — borrow from `immich-go`.
- XMP sidecar fallback when the target format rejects EXIF (e.g., PNG, HEIC quirks) — borrow from `gophix`.
- Rule-based JSON-to-media matcher (direct-match, base-filename, `.supplemental-metadata.json`, truncated-name) — borrow from `linoleum8612/google_photos_exif_processor`.
- Thunderbird-based Gmail archive migration step documented in the wizard — borrow from the henryko.dev degoogling writeup / widely-used pattern.
- Download "shared-with-me but never saved" photos via the Toolkit side-channel, because Takeout skips them — borrow from `xob0t/Google-Photos-Toolkit`.

### Patterns & Architectures Worth Studying
- `immich-go`'s source-adapter abstraction (`from-google-photos`, `from-immich`, `from-picasa`, `from-icloud`) — good model for DeGoogler to add more sources beyond Takeout.
- `couzteau/Degoogle-Photos` checkpoint design: an index file of `(src-hash, dest-path, status)` rows so the tool is idempotent across runs — directly applicable to the PowerShell toolkit's long-running ops.
- `garzj/google-photos-migrate` containerized distribution — eliminates "which Node/Python/yarn version?" support burden; useful model for DeGoogler's Python/PowerShell components.
