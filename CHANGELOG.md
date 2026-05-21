# Changelog

All notable user-facing changes to Fitloop are documented here.

## Unreleased

### Added

- Nesting progress bar with phased labels (queued through writing outputs), live percent from CLI `progress.json`, and cancel in the progress panel (`REQ-FIT-JOB-001`).
- Auto-split orphan resolution: split proposals, derived pieces, manual CAD path, and re-nest with updated pieces (`REQ-FIT-SPLIT-001`).
- Composite DXF layers: primary/auxiliary roles, clipped decorations in preview, layer-preserved nested output (`REQ-FIT-DXF-002`).
- **Modo Arquitecto en Pánico** (`:es_panic`) joke locale with EN/ES + panic switcher and full key parity with Spanish (`REQ-FIT-UI-005`).

### Changed

- Ephemeral workspace access without project PIN (ADR-0004).
- Locale switcher uses translated `aria-label` for the EN/ES group in all locales.

### Removed

- Project PIN gate and related UI.
