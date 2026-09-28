# VIMS — Android app (Kotlin / Jetpack Compose)

Native Android build of VIMS Phase 1 (Vision Inspection Management Solutions), built screen-for-screen against the
client-approved prototype (`../index.html`, `../report.html`, `../screens/`). The iOS twin lives in `../ios/`.

- Kotlin + Jetpack Compose + Material3 (themed to `../docs/design-tokens.md`, light only)
- Single activity, navigation-compose (type-safe routes), one `AppViewModel` exposing `StateFlow`s
- Offline-first: every piece of data is a JSON file in the app's `filesDir`; no network, no `INTERNET` permission
- Checklist content/config is loaded at runtime from the shared `vims-checklists.json` — nothing is hardcoded

## Build & run

Open the `android/` folder in Android Studio (it uses the Gradle wrapper; AGP 9.4.1, Kotlin 2.4.20, compileSdk 37, minSdk 26).

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
cd android
./gradlew assembleDebug --console=plain
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.vims.app/.MainActivity
```

Sign in with any non-empty email + password (auth is stubbed). The demo seed pre-fills Jeremy Heath's email.

### Debug screen jumper (debug builds only)
`MainActivity` accepts intent extras so any screen can be opened directly (also signs in):

```bash
adb shell am start -S -n com.vims.app/.MainActivity --es screen section --es section Roof
#   screen: login signup forgot join home wizard sections section photos camera markup finding summary report
#           generated pdf settings company instructions admin editsec plans inspectors subscribe substarted billing feedbackadmin
#   --es insp demo-ridgeline   --es section "'Outside Utilities'"   --es photo demo-p0   --es cat "North Side"
#   --es depth high|standard|fast (rewrites that inspection's depth)   --ei step 1-4 (wizard)   --ei coverStep 1-3
#   --ez splash true (show the free-look splash)
```
Release builds ignore these extras (`BuildConfig.DEBUG`).

## Architecture / package map (`app/src/main/java/com/vims/app/`)

| Package / file | What it holds |
|---|---|
| `VimsApplication.kt` | App start: loads fonts, builds `AppContainer` (config, repository, services), bootstraps the company account from JSON, runs the demo seed |
| `MainActivity.kt` | Edge-to-edge setup, debug intent parsing, sets `VimsRoot` |
| `data/ChecklistConfig.kt` | `@Serializable` model of `vims-checklists.json` + `ChecklistLoader` |
| `data/ChecklistEngine.kt` | Effective section defs (JSON + admin edits), checklist generation from wizard selections (`checklistBuilder`: standard layout, Phase 1 Foundation / Phase 2 Pre-Dry Wall, numbered Bathroom/Bedroom/Hallway), depth rules, stable answer keys |
| `data/Models.kt` | Inspection, WizardSelections, SectionAnswers, Photo, Finding, CompanyProfile, AccountState (plans, inspectors, trial), AppSettings, ChecklistEdits |
| `data/Repository.kt` | `VimsRepository` interface + `FileRepository` (in-memory `StateFlow`s, write-through JSON files, ordered background writes, temp-file + rename) |
| `services/Services.kt` | `AuthService`, `SubscriptionService`, `SyncService` interfaces + local stubs (`TODO(backend)`) |
| `report/ReportPdfGenerator.kt` | On-device PDF (`android.graphics.pdf.PdfDocument`) following `report.html` |
| `demo/DemoSeed.kt` | **All demo data** (first launch only) |
| `ui/AppViewModel.kt` | UI state + actions for every screen |
| `ui/VimsNav.kt` | Routes, NavHost, toast host, debug jumper |
| `ui/theme/` | Design tokens (`V`), fonts (`VimsFonts`, text styles `T`), the prototype's stroke icons rebuilt from its SVG paths (`VIcons`) |
| `ui/components/Components.kt` | Header bar, buttons, cards, inputs, chips (single = tap again to deselect), segmented control, pills, rows, counters, banners, success block |
| `ui/screens/` | `AuthScreens` (login, create account, forgot, join) · `HomeScreen` (+ trial splash) · `WizardScreen` · `SectionsScreen` (+ sections drawer) · `SectionScreen` · `PhotosScreens` (photos, CameraX capture, markup viewer, flag-a-finding sheet) · `SummaryScreen` · `ReportScreens` (cover picker, report ready, PDF preview, share) · `SettingsScreens` (settings, company profile, how VIMS works, feedback admin) · `AdminScreens` (manage checklist, edit section, plans & pricing) · `AccountScreens` (inspectors, subscribe, subscription started, billing) |
| `util/` | `Fmt` (Locale.US money/dates/times), `Images` (downsampling, EXIF normalize, thumbnail cache) |

### Shared data & fonts
`app/build.gradle.kts` adds `../../shared` as an assets folder, so the app reads
`assets/data/vims-checklists.json` (via kotlinx.serialization, `ChecklistLoader`) and `assets/fonts/*`
(Archivo / IBM Plex Sans variable fonts with `FontVariation` weights, IBM Plex Mono statics). Edit checklist content in
`../shared/data/vims-checklists.json` only — both apps pick it up.

### Local storage layout (`filesDir/vims/`)
`session.json`, `account.json`, `company.json` (+ `company/logo.png`, `company/agreement.*`), `settings.json`,
`checklist-edits.json`, and per inspection `inspections/<id>/{inspection,answers,photos,findings,checklist}.json`,
`photos/*.jpg`, `report/VIMS-Report-*.pdf`. `checklist.json` is a snapshot of the section definitions taken when the
checklist was built, so admin edits apply to *new* inspections only (as the prototype states).

## Backend stubs — search for `TODO(backend)`
- `LocalAuthService` — any non-empty credentials sign in; create account / join-by-code succeed locally (join → Inspector role).
- `LocalSubscriptionService` — Square subscription is simulated (always succeeds, keeps last 4 digits only). Replace the
  card fields on the Subscribe screen with the Square In-App Payments SDK card entry; never send or store a card number.
- `LocalSyncService` — "Sync now" just marks everything synced. Phase 2: upload inspections/photos/findings/reports and pull
  checklist/plan edits from the Laravel API.
- Role enforcement is UI-only (Admin section hidden for the Inspector role); real enforcement is server-side.

## Removing the demo seed
Delete `app/src/main/java/com/vims/app/demo/DemoSeed.kt` and the single `DemoSeed.seedIfNeeded(...)` line in
`VimsApplication.kt`. The app then starts empty; plans, per-inspector rate, trial length, and the feedback email still come
from `vims-checklists.json`. (The login email prefill reads the owner inspector, so it will simply be blank.)

## Scope notes
- Excluded by agreement: client-payment screens (Collect payment / Payment received) and the report's invoice page;
  the prototype's yellow "jump to screen" review button (a debug-only intent jumper exists instead).
- Screenshots of every screen/state are in `screenshots/` (numbering matches `../screens/`), plus rendered PDF pages and
  a sample generated report.
