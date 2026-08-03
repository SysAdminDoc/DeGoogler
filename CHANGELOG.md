# Changelog

All notable changes to DeGoogler will be documented in this file.

## Unreleased

- Added: PowerShell Takeout converters for Keep Markdown, Fit Apple Health/TCX, Maps GeoJSON/GPX/KML, and Chat/Hangouts JSON exports.
- Added: Atomic progress checkpoints for long-running Takeout, Photos, and MBOX operations.
- Added: A non-UI toolkit core module and smoke tests for deterministic converter verification.
- Added: Bundled ExifTool 13.59 with its required support directory for offline photo metadata repair.
- Added: Photo metadata cascade, supplemental/truncated sidecar matching, Picasa `.ini` support, burst detection, and XMP fallback sidecars.
- Added: AES-GCM connected-service storage for the Browser Assistant, with migration from the previous local JSON format.
- Added: Shared migration-plan synchronization between the Web App and Browser Assistant plus toolkit plan validation.
- Added: `degoogler://` toolkit deep links and per-user protocol registration for opening a selected tool with a local path.
- Added: GitHub Pages deployment workflow and reproducible release-bundle builder with SHA-256 manifests.
- Added: Toolkit release-update checker and prompt that downloads only bundles verified against a published SHA-256 manifest.
- Added: Offline Web App progress dashboard with weekly migration snapshots and priority-category completion bars.
- Added: Reverse-mode email migration checklist for tracked and manually added services.
- Added: Web App localization selector with English, Spanish, German, and French shell/tracker translations.

## [v0.0.1] - %Y->- (HEAD -> main, origin/main, origin/HEAD)

- Added: Add @updateURL and @downloadURL to userscripts
- Added: Add documentation link to README
- Added: Add files via upload
- Added: Add files via upload
- Added: Add files via upload
- Changed: Update README.md
- Added: Add files via upload
- Added: Add files via upload
- Added: Add files via upload
