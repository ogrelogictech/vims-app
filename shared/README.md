# shared/

Single source of truth used by **both** native apps. Edit here — never copy checklist content into app code.

- `data/vims-checklists.json` — every checklist section and item (Standard + High Detail), photo categories, report numbering, the new-inspection wizard options, checklist-builder rules, finding categories, quick comments, cover options, and plans. Extracted from the client-approved prototype (`../index.html`, approved Sep 15, 2026).
- `fonts/` — Archivo (headings), IBM Plex Sans (UI), IBM Plex Mono (times/codes/prices). All SIL Open Font License (see `OFL-*.txt`).

How the apps pick these up:
- **Android:** `app/build.gradle.kts` adds `../../shared` as an assets folder → `assets/data/vims-checklists.json`, `assets/fonts/*`.
- **iOS:** the Xcode project syncs `../shared/data` and `../shared/fonts` into the app bundle as resources.
