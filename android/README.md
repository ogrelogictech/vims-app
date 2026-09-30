# VIMS — Android app (Kotlin / Jetpack Compose)

Native Android build of VIMS Phase 1 (Vision Inspection Management Solutions), built screen-for-screen against the
client-approved prototype (`../index.html`, `../report.html`, `../screens/`). The iOS twin lives in `../ios/`.

- Kotlin + Jetpack Compose + Material3 (themed to `../docs/design-tokens.md`, light only)
- Single activity, navigation-compose (type-safe routes), one `AppViewModel` exposing `StateFlow`s
- Offline-first local database: **Room (SQLite)**, scoped per user / per company; no network, no `INTERNET` permission
  (MySQL is the Phase 2 *server* database behind the Laravel API — it can't run on a phone; Room is the on-device store)
- Splash video on cold launch, reusable input validation, the prototype's own icon set (`shared/icons`)
- Checklist content/config is loaded at runtime from the shared `vims-checklists.json` — nothing is hardcoded

## Build & run

Open the `android/` folder in Android Studio (it uses the Gradle wrapper; AGP 9.4.1, Kotlin 2.4.20, KSP 2.3.12, Room 2.8.5,
Media3 1.11.1, compileSdk 37, minSdk 26).

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
cd android
./gradlew assembleDebug --console=plain
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.vims.app/.MainActivity
```

**Demo account:** `jeremy@visionpropertyinspections.com` / `inspect2026` (owns the sample inspections and the
Vision Property Inspections company, join code `VIS-4827`). Create account makes a brand-new, empty user + company;
Join a company with a code attaches a new user to an existing company. Auth is a local stub (`TODO(backend)`).

### Debug screen jumper (debug builds only)
`MainActivity` accepts intent extras so any screen can be opened directly (also signs in):

```bash
adb shell am start -S -n com.vims.app/.MainActivity --es screen section --es section Roof
#   screen: login signup forgot join home wizard sections section photos camera markup finding summary report
#           generated pdf settings company instructions admin editsec plans inspectors subscribe substarted billing feedbackadmin
#   --es insp demo-ridgeline   --es section "'Outside Utilities'"   --es photo demo-p0   --es cat "North Side"
#   --es depth high|standard|fast (rewrites that inspection's depth)   --ei step 1-4 (wizard)   --ei coverStep 1-3
#   --ez splash true (show the free-look splash)   --ez video true (play the launch video too)
```
Debug launches sign in as the demo account when nobody is signed in, and skip the splash video.
Release builds ignore these extras (`BuildConfig.DEBUG`).

## Architecture / package map (`app/src/main/java/com/vims/app/`)

| Package / file | What it holds |
|---|---|
| `VimsApplication.kt` | App start: fonts + icons, `AppContainer` (config, Room database, repository, services); one-time JSON → Room migration, demo account, restore last session |
| `MainActivity.kt` | SplashScreen API, edge-to-edge, splash video on cold launch, debug intent parsing, sets `VimsRoot` |
| `data/db/VimsDatabase.kt` | Room entities (`users`, `companies`, `inspections`, `section_answers`, `photos`, `findings`, `kv`), DAO, database |
| `data/JsonMigration.kt` | One-time import of the pre-Room JSON store into Room (attached to the demo user/company; files moved to per-user folders) |
| `data/ChecklistConfig.kt` | `@Serializable` model of `vims-checklists.json` + `ChecklistLoader` |
| `data/ChecklistEngine.kt` | Effective section defs (JSON + admin edits), checklist generation from wizard selections (`checklistBuilder`: standard layout, Phase 1 Foundation / Phase 2 Pre-Dry Wall, numbered Bathroom/Bedroom/Hallway), depth rules, stable answer keys |
| `data/Models.kt` | Inspection, WizardSelections, SectionAnswers, Photo, Finding, CompanyProfile, AccountState (plans, inspectors, trial), AppSettings, ChecklistEdits |
| `data/Repository.kt` | `VimsRepository` interface + `RoomRepository` (session-scoped in-memory `StateFlow`s, write-through to Room in order on one background thread) |
| `services/Services.kt` | `AuthService` (local users/companies, salted PBKDF2 hash), `SubscriptionService`, `SyncService` + stubs (`TODO(backend)`) |
| `report/ReportPdfGenerator.kt` | On-device PDF (`android.graphics.pdf.PdfDocument`) following `report.html` |
| `demo/DemoSeed.kt` | **All demo data** (first launch only) |
| `ui/AppViewModel.kt` | UI state + actions for every screen |
| `ui/VimsNav.kt` | Routes, NavHost, toast host, debug jumper |
| `ui/SplashVideo.kt` | Launch video (Media3 ExoPlayer, muted, fit-inside with edge-color letterbox, once, tap to skip; last frame ~1 s when animations are off) |
| `ui/theme/` | Design tokens (`V`), fonts (`VimsFonts`, text styles `T`), icons (`VIcons`: ImageVectors built at startup from `shared/icons/icons.json` — the prototype's own 24×24 stroke paths, stroke 2, round caps/joins, tinted — with the same paths embedded as fallback) |
| `ui/components/Components.kt` | Header bar, buttons, cards, inputs, chips (single = tap again to deselect), segmented control, pills, rows, counters, banners, success block |
| `ui/screens/` | `AuthScreens` (login, create account, forgot, join) · `HomeScreen` (+ trial splash) · `WizardScreen` · `SectionsScreen` (+ sections drawer) · `SectionScreen` · `PhotosScreens` (photos, CameraX capture, markup viewer, flag-a-finding sheet) · `SummaryScreen` · `ReportScreens` (cover picker, report ready, PDF preview, share) · `SettingsScreens` (settings, company profile, how VIMS works, feedback admin) · `AdminScreens` (manage checklist, edit section, plans & pricing) · `AccountScreens` (inspectors, subscribe, subscription started, billing) |
| `util/` | `Validation` (filters, checks, on-screen formatters, `FormState`), `PasswordHasher`, `Fmt` (Locale.US money/dates/times), `Images` |

### Shared data & fonts
`app/build.gradle.kts` adds `../../shared` as an assets folder, so the app reads
`assets/data/vims-checklists.json` (via kotlinx.serialization, `ChecklistLoader`) and `assets/fonts/*`
(Archivo / IBM Plex Sans variable fonts with `FontVariation` weights, IBM Plex Mono statics). Edit checklist content in
`../shared/data/vims-checklists.json` only — both apps pick it up.

### Local database & per-user isolation (Room)
- `vims.db` (schema exported to `app/schemas/`). Ownership:
  - **user-owned** (`userId`): inspections, section answers, photos, findings, reports — files in `filesDir/vims/users/<userId>/inspections/<id>/` (`photos/`, `report/`)
  - **company-owned** (`companyId`): company profile + logo (`filesDir/vims/companies/<companyId>/logo.png`), checklist customizations, plans, inspectors, subscription
  - per-user settings (default depth, auto-sync) live on the `users` row
- Payloads are the existing `@Serializable` models stored as JSON columns, indexed by owner; children cascade-delete with their inspection.
- `RoomRepository.activate(session)` loads **only** that user's inspections and that user's company; `activate(null)` (sign-out)
  clears everything from memory. Every query/update is filtered by the owner id, so a second user never sees the first user's data.
- Each inspection keeps a snapshot of its checklist definitions, so admin edits apply to *new* inspections only.
- Users table: UUID id, unique lowercased email, name, companyId, salted PBKDF2 hash (local stub only — `TODO(backend)`).
- Existing JSON data from earlier builds is imported once into Room and attached to the demo account.

### Validation (`util/Validation.kt`, rules from `../docs/validation-rules.md`)
- `Filters` run while typing — every field: no leading space, never two spaces in a row; emails/passwords/URLs strip spaces;
  person names, phone (digits, shown as `(801) 555-0134`), join code (`VIS-4827`), license, policy #, year, decimals,
  temperature, prices (2 decimals), card number (grouped, Amex 4-6-5, brand shown), expiry `MM/YY`, CVC, ZIP.
- `Checks` run on submit: required fields, email format, password rules (8+, confirm), phone 10 digits, join code format +
  company exists, year 1800–now, positive numbers, temperature −60–140, review URL, price 0.01–9,999.99, section name
  unique, questions/options (no duplicates), card Luhn/expiry/CVC/ZIP.
- `FormState` (`rememberForm()`): shows every error inline (c1 red text + red border), scrolls to the first one, and clears
  each error live once the value is valid. Covered: sign in, create account (with Confirm password + Company name), forgot
  password, join, wizard (per step on Next), company profile, add inspector, subscribe card form, plans & pricing, add plan,
  feedback email, admin section / question / option editor, checklist number items, finding description.

### Launch splash
`Theme.VIMS.Starting` (SplashScreen API, light gray `#D4D4D9` matching the video, no icon) → `SplashVideo` plays
`shared/media/vims-splash.mp4` once, muted, **fit inside** (whole frame visible on every aspect ratio, never cropped),
tap to skip, then Sign in (or Home with a saved session). The letterbox is a two-band background whose colors are
sampled from the video's top/bottom edge rows at runtime (`MediaMetadataRetriever`; fallback `#D2D4DA` / `#C3CAD1`),
so the bands blend into the frame. The video file itself is not altered.
With animator duration scale 0 the last frame shows for ~1 s. On emulators only, the platform software H.264 decoder is
preferred (the emulator's "goldfish" decoder renders nothing under software GPU). Note: the source video's tagline reads
"Vision Ins**j**ection…" — pending a corrected file from the client.

### Platform-owner settings (Feedback & support, Report quality copy / BCC)
- These are **VIMS platform** settings (Jeremy Heath owns VIMS; disclosed in the VIMS EULA), not per-company settings.
  They are stored app-level (`PlatformSettings` in the Room `kv` table, defaults from `support.feedbackEmail` and
  `support.reportBcc` in `vims-checklists.json` v1.2) and shared by every company on the install.
- Only the platform owner sees or edits them: `Session.platformOwner` is set on sign-in for `PlatformOwner.EMAIL`
  (jeremy@visionpropertyinspections.com) — `TODO(backend)`: the flag comes from the server. Company admins of other
  companies don't get the Settings rows, the screens show "Only the VIMS platform owner…", and `updatePlatform` ignores
  non-owner writes.
- "Report quality copy (BCC)": On/Off + BCC address (email validation). Settings row subtitle "On · <address>" / "Off".
- "Email to client" (Report ready) sends `ACTION_SEND` with the PDF (FileProvider), `EXTRA_EMAIL` = client (+ agent),
  subject/body, and `EXTRA_BCC` = the BCC address when On (debug builds log the extras under tag `VIMS-Share`).
  The address is never shown in the app; a short note says a quality copy is blind-copied and some email apps may drop
  it. `TODO(backend)`: the server-side send always adds the BCC so it can't be removed.

### EULA (acceptance, viewer, re-acceptance)
- Text comes verbatim from `../shared/legal/eula.json` (assets `legal/eula.json`, `data/Eula.kt`) — never hardcoded.
- Create account and Join a company both require the checkbox "I have read and agree to the VIMS End User License
  Agreement…" (the name links to the viewer); submitting without it shows an inline error. Acceptance is stored on the
  user row (`users.eulaVersion`, `users.eulaAcceptedAt`; Room schema v2 with a 1→2 migration). `TODO(backend)`: send to the server.
- If eula.json's `version` differs from the signed-in user's accepted version (incl. users who never accepted), a
  full-screen "Updated license agreement" gate shows the text with **I agree** / **Sign out** before the app continues.
  Debug override to test it: `--es eulaVersion 2026-12-01`.
- Viewer: Settings → Legal → End User License Agreement ("Revised <date>"): title, revised date, intro, numbered
  section headings (brand-deep), paragraphs, footer.
- Loading: `Eula.load()` runs once, synchronously, when `AppContainer` is created (Application scope, so it is present on
  a cold start straight into any screen and after process death). It returns a `Result`; a missing/unreadable/invalid
  file is logged (`adb logcat -s VIMS-EULA`) and the viewer and gate show "The license agreement couldn't be loaded"
  with the error instead of a blank card. The build also fails (`verifySharedAssets`, runs before `preBuild`) if
  `../shared/legal/eula.json` or `../shared/icons/icons.json` is missing, since assets come from `../shared`.

### Cancel subscription (EULA 12.3)
Plan & billing, active subscriptions only, owner/admins only: **Cancel subscription** (red ghost) → inline confirm
(active until the end of the period, no refunds/proration, download within 30 days) → **Keep subscription** / **Yes, cancel**.
Cancelled: status "Cancelled · active until <date>", explanation card, **Undo cancellation**. Trial shows no cancel button.
`TODO(backend)`: Square Subscriptions cancel / resume (`SubscriptionService.cancelSubscription/resumeSubscription`).

### Profile photo vs company logo
- **Account picture = the user's own profile photo** (initials fallback). Tap the avatar in Settings → Account →
  Profile photo: Take photo / Choose from gallery / Remove. Stored per user: `vims/users/<userId>/profile.jpg`
  (512 px square, EXIF-rotated) + `users.photoFile` (Room schema v3, migration 2→3). Shown in the Settings account
  card, the side-menu header, and Inspectors rows (matched by email).
- **Company logo** (Company profile): Take photo / Choose from gallery / Remove. It appears on the Home header, PDF
  cover + page headers, and as a small badge next to the company name in the side menu — no longer in the account card.
- Camera capture uses `ActivityResultContracts.TakePicture` into `cacheDir/capture/` via FileProvider (CAMERA
  permission requested on first use); gallery uses the Photo Picker (`ui/components/ImagePick.kt`).

### Delete account / Make owner / Sign out
- Settings → Account → **Delete account** (red): dialog explains what is deleted (account, inspections, photos, reports
  on this device; deletion request to VIMS within 10 working days per the EULA) and requires typing `DELETE`.
  Non-owner: deletes their user row, inspections (cascade), user folder, removes them from the company's inspector list,
  signs out. Owner with other users on the company: blocked — "Make another admin the owner first (Inspectors → Make
  owner)". Sole owner: company row + folder deleted too and the subscription marked cancelled. Returns to Sign in.
  `TODO(backend)`: server-side deletion + Square cancel.
- Inspectors: the owner sees **Make owner** on admin rows (confirm dialog); ownership moves and the old owner stays admin.
- Sign out (Settings, side menu, EULA gate) always asks "Sign out of VIMS?" (Cancel / Sign out).

### Status colors (one scheme everywhere)
Inspections: Done green · In progress blue · Queued amber · Scheduled gray. Sections (overview, drawer, report contents):
Done green · In progress blue · Not started gray. Sync badge: Synced green · Offline · N queued amber · Offline gray.
Subscription: Active green · Trial / Cancelled amber.

### Wizard date
New inspection date picker's minimum is today (past days disabled; typed/validated "Choose today or a later date").
When editing an existing inspection whose saved date is in the past, that saved date stays valid (min = saved date).

### Home side menu
The Home hamburger opens a left drawer (user photo or initials, user name, email, company with logo badge; Inspections, New inspection,
Settings, Company profile, How VIMS works, Help & feedback; admin-only Manage checklist, Plans & pricing, Inspectors;
Sign out at the bottom). The company logo also shows in the Home header, Company profile, and the
PDF cover + page headers; without a logo an initials badge is used everywhere.

## State & insurance forms (Texas TREC, 4 Point) — data v1.1
- Inspection types **Texas** and **4 Point Inspection** build their checklists from `checklistBuilder.phaseTypes`
  (Texas: Inspection Info → 6 TREC systems → Pictures → Summary; 4 Point: Inspection Info → 4 form sections → Pictures, no Summary,
  so "Review summary" is hidden and the flow goes straight to the report).
- Sections with `form` ignore checklist depth (always `items`), show the `formLabels` badge, and have no Overall condition row.
  Sections with `photosOnly` open straight to the photo screen ("Save & continue to summary / report" marks them done).
- Wizard step 1 renders the new **Inspector License #** field (prefilled from Company profile → License #) and the per-type
  `wizard.typeFields` (sponsor / insured + policy #), stored in `WizardSelections.fields` under their `key`.
- The PDF layout comes from `reportLayouts.typeToLayout` (`ChecklistConfig.reportLayout()`): standard, Texas (TREC REI 7-6 page +
  I/NI/NP/D checklist pages + pictures + summary, TREC footer with "Page X of Y") or 4-Point (form pages with gray bands and
  checkboxes, certification block, 3-column picture pages). Every cover prints **License #** beside Name of Inspector.
  Texas and 4-Point PDFs are laid out twice so the footer can print the total page count.

## Backend stubs — search for `TODO(backend)`
- `LocalAuthService` — local users/companies tables with salted PBKDF2 hashes; create account = new user + company (owner);
  join-by-code = new user in that company (Inspector role unless the admin already marked their email as admin).
- `LocalSubscriptionService` — Square subscription is simulated (always succeeds, keeps last 4 digits only). Replace the
  card fields on the Subscribe screen with the Square In-App Payments SDK card entry; never send or store a card number.
- `LocalSyncService` — "Sync now" just marks everything synced. Phase 2: upload inspections/photos/findings/reports and pull
  checklist/plan edits from the Laravel API.
- Role enforcement is UI-only (Admin section hidden for the Inspector role); real enforcement is server-side.

## Removing the demo seed (demo account)
Delete `app/src/main/java/com/vims/app/demo/DemoSeed.kt`, the two `DemoSeed.…` calls in `AppContainer.start()`
(`VimsApplication.kt`) and the debug-only `debugSignIn()` in `AppViewModel`. New accounts already start empty; their plans,
per-inspector rate, trial length, and feedback email come from `vims-checklists.json`.

## Scope notes
- Excluded by agreement: client-payment screens (Collect payment / Payment received) and the report's invoice page;
  the prototype's yellow "jump to screen" review button (a debug-only intent jumper exists instead).
- Screenshots of every screen/state are in `screenshots/` (numbering matches `../screens/`; `31-texas-*`, `32-fourpoint-*`,
  `33-admin-*` for the v1.1 change round), plus rendered PDF pages (`pdf-*`, `pdf-texas-*`, `pdf-fourpoint-*`) and sample reports.
