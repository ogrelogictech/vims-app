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
#           eula agreement (inspection agreement; add --es state NH to show only that state's disclosures)
#           agreementedit (Edit agreement; company admins only)
#   --es insp demo-ridgeline   --es section "'Outside Utilities'"   --es photo demo-p0   --es cat "North Side"
#   --es depth high|standard|fast (rewrites that inspection's depth)   --ei step 1-4 (wizard)   --ei coverStep 1-3
#   cover QA: --es cover "'Blue|Holidays|4th of July|Shaded'"  --es inspType Texas|"'4 Point Inspection'"  --ez generate true (builds the PDF, opens the preview)
#   --ez splash true (show the free-look splash)   --ez video true (play the launch video too)
#   trial QA: --ez trialEnded true (the signed-in company's free look ended yesterday, no subscription)
#             --ez resetDeviceTrial true (forget this device's one-free-trial record; works with --es screen login / signup)
```
Debug launches sign in as the demo account when nobody is signed in, and skip the splash video.
Release builds ignore these extras (`BuildConfig.DEBUG`).

## Architecture / package map (`app/src/main/java/com/vims/app/`)

| Package / file | What it holds |
|---|---|
| `VimsApplication.kt` | App start (background, `ready` StateFlow): fonts + icons, `AppContainer` (config, EULA, Room database, repository, services); one-time JSON → Room migration, demo account, restore last session |
| `MainActivity.kt` | SplashScreen API (held until startup is `ready`), edge-to-edge, splash video on cold launch, debug intent parsing, sets `VimsRoot` |
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
- **Required fields** show a red " *" after the label (`FieldLabel(required = true)` / `VField(required = …)`), set
  wherever the field's check rejects an empty value (wizard: `isWizardRequired()` runs the same `wizardCheck`). Longer
  forms (Create account, wizard step 1, Subscribe payment) start with a small "* Required" legend (`RequiredHint`).
- **One field-label style** everywhere (`FieldLabel`: prototype `label` — IBM Plex Sans 12.5sp semibold, ink-2). The
  uppercase mono section labels (`Lbl`) are unchanged. Add inspector and the admin editors now use labeled fields.
- **Sign-in errors land on the right field**: unknown email → Email field ("No account found for that email…"),
  wrong password → Password field only, bad email format → Email field; each clears as soon as that field is edited.
  Create account: Confirm password only says "Re-enter your password" / "Passwords don't match".
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

### App startup (off the main thread)
`VimsApplication.onCreate` does no disk work on the main thread: an application-scoped coroutine on `Dispatchers.IO`
loads fonts/icons, builds `AppContainer` (checklist config, EULA, Room) and runs `AppContainer.start()` (one-time JSON →
Room migration, demo account, platform settings, last-session restore), then flips `VimsApplication.ready` to true.
`MainActivity` keeps the system splash on screen (`setKeepOnScreenCondition`) and creates `AppViewModel` + the Compose UI
only after `ready` — on a normal cold launch and when the activity is recreated after process death. Never read
`VimsApplication.container` before `ready` (it throws). Debug builds enable StrictMode (disk reads/writes on the main thread,
`penaltyLog`): `adb logcat -s StrictMode`; startup logs `VIMS-Startup: ready in N ms`.

### Launch splash
`Theme.VIMS.Starting` (SplashScreen API, light gray `#D4D4D9` matching the video, no icon) → `SplashVideo` plays
`shared/media/vims-splash.mp4` once, muted, **fit inside** (whole frame visible on every aspect ratio, never cropped),
tap to skip, then Sign in (or Home with a saved session). The letterbox is a two-band background whose colors are
sampled from the video's top/bottom edge rows at runtime (`MediaMetadataRetriever`; fallback `#CCD6DF` / `#BDC7D3`, the
Oct 12 video's edges), so the bands blend into the frame. The video file itself is not altered. The video (6.6 s since
Oct 12) ends the splash itself; safety nets: 8 s if it never starts, otherwise its length + 1.5 s (debug builds log
`VIMS-Splash` ready / first frame / done).
With animator duration scale 0 the last frame shows for ~1 s. On emulators only, the platform software H.264 decoder is
preferred (the emulator's "goldfish" decoder renders nothing under software GPU).

### Platform-owner settings (Feedback & support, Report quality copy / BCC)
- These are **VIMS platform** settings (disclosed in the VIMS EULA), not per-company settings.
  They are stored app-level (`PlatformSettings` in the Room `kv` table, defaults from `support.feedbackEmail` and
  `support.reportBcc` in `vims-checklists.json` v1.2 — since v1.9.2 `support@vimsinspect.com` and
  `quality@vimsinspect.com`) and shared by every company on the install.
- Only VIMS platform owners see or edit them: `Session.platformOwner` is set on sign-in / account creation when the
  email is in `support.platformOwners` (data v1.5; trimmed, case-insensitive, several allowed — `PlatformOwners` in
  `data/Repository.kt`) — `TODO(backend)`: the server owns the list. Company admins of other
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
- Loading: `Eula.load()` runs once, during the background app startup when `AppContainer` is created, and always before
  any screen is shown (Application scope, so it is present on a cold start straight into any screen and after process death). It returns a `Result`; a missing/unreadable/invalid
  file is logged (`adb logcat -s VIMS-EULA`) and the viewer and gate show "The license agreement couldn't be loaded"
  with the error instead of a blank card. The build also fails (`verifySharedAssets`, runs before `preBuild`) if
  `../shared/legal/eula.json` or `../shared/icons/icons.json` is missing, since assets come from `../shared`.

### Cancel subscription (EULA 2026-10-28: 4.1 / 12.3 / 12.4)
Plan & billing, active subscriptions only, owner/admins only: **Cancel subscription** (red ghost) → inline confirm → **Keep
subscription** / **Yes, cancel**. Trial shows no cancel button.
- **Monthly:** stays active until the next billing date, no refund; status "Cancelled · active until <date>", **Undo cancellation**.
- **Yearly:** access ends on the cancellation date; the confirm shows the pro-rated refund (yearly total × unused days ÷ days in
  the period, rounded to cents, e.g. $385.00 × 265 ÷ 365 = $279.52) "will be refunded to your card". After cancelling: status
  "Cancelled · ended <date>", "Access ended" + "Pro-rated refund" rows, no Undo, **Subscribe again**; new inspections are gated
  like an ended trial ("Your subscription has ended" / Home "Subscription ended"). Master admins stay exempt.
- Once any cancelled subscription has ended, leftover free-trial days don't reopen access. Subscribing again starts a new period.
- `AccountState.cancelledEpochDay` / `refundAmount` (JSON defaults, old rows decode unchanged). `TODO(backend)`: Square cancel /
  resume and Square refund (`SubscriptionService.cancelSubscription/resumeSubscription/refundUnused`).
- Billing QA (debug): `--es screen billing --es subscribed yearly --ei subscribedDaysAgo 100` (an active subscription started N days ago).

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
- Sign out (Settings, side menu, EULA gate) always asks "Do you really want to sign out?" (Cancel / Sign out); the
  secondary line says how many inspections haven't synced yet (or that inspections stay saved on the device).

### Status colors (one scheme everywhere)
Inspections: Done green · In progress blue · Queued amber · Scheduled gray. Sections (overview, drawer, report contents):
Done green · In progress blue · Not started gray. Sync badge: Synced green · N queued (online) / Offline · N queued amber · Offline gray.
Subscription: Active green · Trial / Cancelled amber.

### Wizard date
New inspection date picker's minimum is today (past days disabled; typed/validated "Choose today or a later date").
When editing an existing inspection whose saved date is in the past, that saved date stays valid (min = saved date).

### Settings footer
No app/data version line in release builds; debug builds show "Debug build · VIMS x.y.z · checklist data vN" at the
bottom of Settings for developers.

### Home side menu
The Home hamburger opens a left drawer (user photo or initials, user name, email, company with logo badge; Inspections, New inspection,
Settings, Company profile, How VIMS works, Help & feedback; admin-only Manage checklist, Inspectors; a **Master admin** group
(Plans & pricing, Report quality copy (BCC), Feedback & support) for VIMS master admins only (v0.22.0); Sign out at the bottom). The company logo also shows in the Home header, Company profile, and the
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
- `LocalSyncService` — "Sync now" just marks everything synced; Phase 1 never calls it (`features.sync = false`). Phase 2: upload inspections/photos/findings/reports and pull
  checklist/plan edits from the Laravel API.
- `DeviceTrial` — one free trial per device is a local record only; the server must enforce it across reinstalls (ANDROID_ID +
  Play Integrity at sign-up / trial start, plus email / card checks).
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

## State rules, state documents, CC inspector (shared data v1.3)

- **State field:** wizard step 1 has a required **State** (from `shared/data/vims-checklists.json` → `states`) right after Inspection address. It is saved on the inspection and shown with the address.
- **`stateRules`** (same JSON; behavior described in its `_about`):
  - **TX:** auto-selects the **Texas** (TREC) inspection type. If the state changes away while the type is still the automatic one, it reverts to Real Estate Sale.
  - **OK:** the `summaryDisclosure` is a permanent entry at the top of the Summary screen and page 1 of the PDF summary.
  - **OR:** the `coverNotice` prints on the PDF cover under the ownership notice, in every layout.
  - **OR / LA `docs`:** the state documents (`shared/legal/state/*.pdf`) are listed in step 1 with **View** and **Send to client**. A required checkbox, "Provided to the client with the inspection agreement," blocks **Next**, and the acknowledgment is stored with a timestamp.
  - **Adding a state:** edit `stateRules` in the shared JSON. No code changes are needed.
- **Emailed reports** go To the client and agent (client only when "Send the report to the real estate agent" is off — see v1.4 below), with **CC to the signed-in inspector** (archive copy) and BCC to the platform report-quality address when that setting is on.
- **EULA** `version` 2026-10-03 adds clause 3.4 (Licensing). Users who accepted an older version see the re-accept gate once.

## VIMS default inspection agreement + send-to-agent (shared data v1.4)

- **Agreement text** comes from `../shared/legal/inspection-agreement.json` (`data/InspectionAgreement.kt`), loaded once
  during background startup next to the EULA (`AppContainer.agreementResult`, errors logged under `VIMS-Agreement` and shown
  in the viewer instead of a blank card). `{companyName}` is replaced with the signed-in company's name at display time.
  `verifySharedAssets` now also requires the file.
- **Company profile → Inspection agreement:** default card "VIMS agreement" / "All 50 states · in use · View" with
  **Upload your own** (PDF/Word picker). After an upload: the file name, "Your agreement · in use · Use VIMS agreement"
  (reverts and deletes the copied file) and **Replace**. Stored on the company profile (`agreementName` / `agreementFile`,
  JSON payload, no schema change); file in `vims/companies/<companyId>/agreement.<ext>`.
- **Viewer** ("Inspection agreement", `AgreementR(state)`): title, header form lines in a boxed mono block, body paragraphs /
  bullets, state disclosures (all 20 from Company profile; only the inspection's state from the wizard, with "Showing <State>
  only…" or "No additional disclosures for <State>."), closing. If the company uses its own file, a note at the top says the
  VIMS text is for reference, with **Open your agreement** (`ACTION_VIEW` via FileProvider, `company_docs` path).
- **Wizard step 1:** "Inspection agreement: View (shows the selected state's section)" under the State notes, and
  **Send the report to the real estate agent** under Real estate agent email (`WizardSelections.sendToAgent`, saved on the
  inspection). Changing the state sets it to `stateRules.<STATE>.agentCopyDefault` (unchecked for NH, checked elsewhere);
  when that default is false the state's note shows under the checkbox instead of under the State field.
- **Email to client:** `EXTRA_EMAIL` = client only when send-to-agent is off (CC inspector and BCC platform unchanged). The
  Report ready note says "Goes to the client only…" or "Goes to the client and the real estate agent."
- Screenshots: `screenshots/qa-12x-*.png`.

## Inspection agreement: Download + company Edit (v0.10.0)

The VIMS agreement stays the default and is never changed; edits only ever apply to that one company's copy.

- **Download (every user):** the viewer's top bar has a download action. It prints exactly what the viewer shows (title,
  form lines, body, the state disclosures shown, closing; company name filled in; viewer-only notes skipped) into a
  paginated US Letter PDF with `PdfDocument` (`report/AgreementPdf.kt`: same fonts as the report, lines split across pages,
  "Company · Inspection Agreement / Page x of n" footer), saved as `cache/agreement/Inspection-Agreement-<Company-Name>.pdf`.
  A chooser offers **Share PDF** (`ACTION_SEND` via FileProvider, `agreement_pdf` cache path) and **Save to device**
  (`ACTION_CREATE_DOCUMENT`). When the company uses an uploaded file the viewer still shows the VIMS text for reference
  (and downloads that), and **Open your agreement** is unchanged.
- **Edit (company admins only — same permission as Upload / Use VIMS agreement, which are now admin-only too):** the card
  shows **Edit**, which opens "Edit agreement" (`AgreementEditR`): one large text field prefilled with the company's edited
  version, or the whole VIMS agreement as plain text (`InspectionAgreement.plainText`: title, paragraphs
  separated by blank lines, bullets "• ", the disclosures heading then one "State name: text" paragraph per state, closing)
  with the company name filled in; the form lines are locked since v0.15.0 (see below). Save checks not blank / at most 100,000 characters; leaving with unsaved changes (header
  back, Cancel, system back) asks "Discard changes?". The draft survives rotation (kept in the ViewModel, not in saved state).
- **Which agreement is in use:** saving an edit clears an uploaded file (and deletes it); uploading a file clears the edit;
  **Use VIMS agreement** clears both (asks first when an edited version would be removed).
- **Card states:** VIMS default → "VIMS agreement" / "All 50 states · in use · View · Edit"; edited → "Edited VIMS
  agreement" / "Your edited version · in use · View · Edit · Use VIMS agreement"; uploaded → as before. Inspectors see View only.
- **Viewer with an edited version:** a note "Your company's edited version of the VIMS agreement." and the edited text
  (`AgreementText.pieces`: a paragraph per blank-line block, "• " lines as bullets). From the wizard with a state selected
  the whole edited text is shown (it can't be filtered by state).
- **Storage — Room v4:** `MIGRATION_3_4` adds two nullable columns to `companies` (`agreementText TEXT`,
  `agreementEditedAt INTEGER`); existing rows keep all data and read as "not edited". They are not part of `profileJson`
  (`CompanyProfile.agreementText/agreementEditedAt` are `@Transient`, filled in by `RoomRepository`); every company write
  updates the profile JSON and these columns in one statement. Schema: `app/schemas/.../4.json`. `TODO(backend)`: sync the
  edited agreement to the server.
- Screenshots: `screenshots/agreement-*.png`.

## Client round Oct 9 (v0.11.0)

- **VIMS owners:** `support.platformOwners` (currently `masteradmin@vimsinspect.com` and `admin@vimsinspect.com`) replaces the hard-coded owner email.
  No password is stored or seeded: the owner taps Create account (or Sign in) with that email and their own password and
  gets Report quality copy + Feedback & support. The demo `jeremy@…` is still the demo company's owner/admin, no longer
  a platform owner.
- **Client email filled the inspection address (fixed):** Compose reports every text field to Android Autofill; on the
  wizard, Google Autofill saw "Client email" (email) and "Inspection address" (street address) and offered the phone
  owner's saved profile — one pick filled both. All wizard fields now opt out (`LocalNoAutofill` →
  `contentDataType = None` in `VInput`), and keyboard **Next** walks the form in order.
- **State type-ahead:** the State field is a real text field (the old read-only dropdown never took focus, so typed
  letters went to the address). Tap it → every state listed (current one as placeholder); type a name or 2-letter code →
  the list filters; tap or **Next** picks (Next then moves to Real estate agent name). Leaving with an exact / single
  match picks it, otherwise the previous state stays. Required check and state rules (TX form, OR/LA documents, NH agent
  copy off) unchanged.
- **Report cover (fixed):** the choice was saved but the PDF only used it for the band color and a small tag (the theme
  never showed; with no photo a "Front of property" placeholder replaced it). `drawCoverArt`: **Framed** = property photo
  in a frame of the cover color with the theme as caption, **Shaded** = photo shaded in the cover color with the theme
  title, **Solid** = the color; no photo → the theme artwork fills the area. Persists with the inspection as before.
- **Concerns:** choosing "Concerns" / "Concern" on a Standard / High Detail item opens the Flag-a-finding sheet titled
  "Concern: <item>" (concern subtitle, category 2 default, quick comment, empty description, same validation). Add finding
  saves "<item>: <description>" for the section (`Finding.item` keeps the item); Cancel just closes; deselecting never
  deletes a finding.
- **Wording:** Fast Entry and the report row say **Items reviewed**.
- **Data v1.5** (water feature multi-select, driveway Slope / Incline / Decline / Cracked / Buckling, bushes order, Pilot
  Light) needs no code: it shows on checklists built from now on. Inspections built earlier keep the checklist snapshot
  taken when they were built (`ChecklistEngine.snapshot`), so they still show the v1.4 questions.
- Screenshots: `screenshots/oct9-*.png`.


## Client cover designs (v0.12.0, data v1.6)

- **PDF cover = the client's design** (Report Cover Pages, Oct 9; `report.html` `coverPage()` is the reference). Laid
  out in inches from `covers.layout`: page box (**Framed** = light fill + 0.75pt black border + soft glow in `deep`, drawn
  as vector layers following the CSS box-shadow profile; **Shaded** = light 0–18% → mid 56% → deep 83–100% vertical
  gradient; **Solid** = `solid` fill), company logo top-left, company block top-right (name, address, phone, email),
  title (Inspection Report / Property Inspection Report for Texas / 4-Point Inspection Report), bold serif field labels
  with values on underlines (empty values print "—"; License # beside Name of Inspector; 4-Point keeps its own rows with
  0.39 / 0.30 in gaps so the block ends above the photo), property photo box (center-crop, 1.25pt border; no photo →
  empty box + "Picture of Property."), the theme artwork (`covers.themeArt`, WebP from `shared/covers`) at its position
  clipped to the page box, then the ownership footer. Fonts: `Typeface.SERIF` (bold) like his Word covers.
- **Footer wrap:** measured from the artwork's opaque pixels in the footer band (not its rect, which has transparent
  margins: Horses' rect starts at 3.46 in, its pixels at 4.2 in), the footer goes on the side with more room (min 3.3 in)
  and is drawn after the art so it is never hidden (Fall, 4th of July). The Oregon `coverNotice` stays under it; when it
  makes the footer taller, the photo box gets shorter.
- **Cover picker:** the preview tile shows the chosen theme's artwork in its corner (Solid shows the color name). Flow and
  persistence unchanged.
- `verifySharedAssets` now also fails the build if a `covers.themeArt` file is missing. The 18 artworks add 1.6 MB of
  assets; a report with theme art is ~0.7–0.9 MB larger (Android's PDF writer stores bitmaps losslessly).
- Theme art note (from the data): Summer, Christmas and Spring contain stock-site watermarks — test builds only.
- Screenshots: `screenshots/oct9-cover-*.png`; sample PDFs regenerated.


## Delete an inspection (v0.13.0)

Client feedback (Oct 11): a tester couldn't find a way to delete current or old inspections to free device storage.
- **Home:** every inspection row has a trailing **⋯** (48dp, "More options for <address>"); long-pressing the row opens
  the same menu — **Save or share report** (only when the report PDF exists; plain share sheet via the FileProvider, no
  client recipients) and **Delete inspection** (red).
- **Inside an inspection:** a red ghost **Delete inspection** button at the bottom of Sections and of Report ready;
  deleting returns to Home with the inspection's back stack cleared.
- **Same confirmation everywhere:** "Delete this inspection?" with the 3–5 year retention reminder; **Save report first**
  (when a report exists — shares it, does not delete), **Delete inspection**, **Cancel**. Toast "Inspection deleted".
- `VimsRepository.deleteInspection(id)`: only the signed-in owner's inspection (memory map + DAO `WHERE id AND userId`);
  runs on the serial writer after queued writes; deletes answers / photos / findings rows (explicitly + FK cascade), the
  photo files and report PDF it references, and `vims/users/<userId>/inspections/<id>/` (paths checked to stay inside
  the user's folder). Other inspections and other users' data are untouched.
- `TODO(backend)`: once the VIMS server is live, reports are retained server-side (reports 3 yrs, agreements 5 yrs), so
  deleting only frees device space.
- Screenshots: `screenshots/oct11-delete-*.png`. Test APK: `../../VIMS-Android-test-v0.13.0-2026-10-11.apk`.

## Indoor Air Quality readings (v0.14.0, data v1.7)

Client update (Oct 12): section 39 Indoor Air Quality uses the new `airReading` item type (Standard `items` and High Detail
`itemsHigh`, after Report Information) plus a section-level `airQuality` block (legend, ratings, column heads, action prefix).
- **Model:** `ItemDef` gains `code` / `unit` / `reference` / `action` (+ `isAirReading`); `SectionDef.airQuality` →
  `AirQualityDef`. Unknown item types still render as a text input (no crash).
- **Answer storage (no Room migration):** under the item's normal key, the 1–6 rating is a single value in
  `SectionAnswers.values` (like `single`) and the optional level is plain decimal text in `SectionAnswers.inputs` (unit not
  stored). Read through `SectionAnswers.airRating(key)` / `airLevel(key)`; a pre-v1.7 value such as "1 Good" / "3 Mild"
  maps to its leading digit, anything else is ignored; a non-numeric level (e.g. ".") is treated as blank.
  Inspections built before v1.7 keep their checklist snapshot (old single-choice IAQ lines) and print as before.
- **Entry UI (`SectionScreen.AirReadingCard`):** question, "Level (<unit>)" decimal-keypad field (optional, must be a
  number ≥ 0 — `Checks.level`), 1–6 rating chips (tap again to deselect), then the reference and
  "Corrective action if needed — <action>" in small secondary text. Fast Entry "Items reviewed" chips unchanged.
- **PDF (`ReportPdfGenerator.airQualityTable`):** when a section has `airQuality`, each run of readings prints as the
  client's table — legend top-right (own line when it can't share the column-head line), "Level Measured" / "Air Quality
  Rating" heads, rows "<code> – <name>" | level + unit on an underline | bold rating, with the reference (left) and the
  corrective action (right) beneath. Unanswered readings print blank like the paper form; a row never splits across pages
  and the column heads repeat under "Indoor Air Quality (cont.)". Report Information (High Detail), Overall condition,
  comments, findings and photos print as usual. Admin "Manage checklist" labels the item "Air reading · level (unit) + 1–6 rating".
- Screenshots: `screenshots/oct12-iaq-*.png` (entry Standard / High Detail / validation / after relaunch; PDF Standard,
  High Detail, and a forced page break with an empty CO row). Test APK: `../../VIMS-Android-test-v0.14.0-2026-10-12.apk`.

## QA round Oct 12 — iOS parity (v0.15.0, data v1.7.1)

- **Date & time fields in checklists:** data v1.7.1 made Indoor Air Quality (High Detail) Date → `date` and Time → `time`,
  Termite "Date of inspection" and Wind Mitigation "Inspection date" → `date`. The checklist renderer already had both
  types (`SectionScreen.ItemCard` → `PickerField` + `pickDate` / `pickTime`, the wizard's own Date / Time pickers — same
  look, no past-date limit in checklists). Tapping one opens the picker directly; `PickerField` now clears focus first, so a
  keyboard left up by a text field above closes (wizard too). Stored as text in the answer like the wizard (`2026-10-14`,
  `10:00`); the PDF prints "Oct 14, 2026" / "10:00 AM". **Inspections built before v1.7.1** (their checklist snapshot still
  says `text`) get the picker too: `ChecklistEngine.upgradePickers` (applied when the repository loads inspections) switches
  a snapshot item from `text` to `date` / `time` when the current data has the same section + question as a picker (iOS reads
  the live data). Nothing else in the snapshot changes; an answer typed earlier ("10/12/2026", "9:30 AM") still shows and
  prints as typed until a date / time is picked.
- **Agreement form block locked:** "Edit agreement" edits only the wording (title, body, state disclosures, closing). The
  form block (`InspectionAgreement.formLines`: Clients Name ____ … ☐ checkbox lines … fees) is shown read-only above the
  field ("Form lines · locked", boxed mono, scrolls inside 150dp; folds away while the keyboard is up, Show closes the
  keyboard) and is not in the editor text. The viewer and the downloaded PDF print the saved wording with the locked block
  boxed after its title (`AgreementText.pieces(text, form)`: a one-line first block is the title; block at the top when
  there is none). No fill-in-the-blank or tappable checkboxes (filling / signing is the deferred e-sign add-on).
  **Edits saved before the lock** contain the form lines after the title: `AgreementText.stripForm` drops a blank-line block
  whose lines are at least half form lines (even with a few lines changed) and any other line that is exactly a form line,
  so the viewer / PDF show the block once and the editor opens without it (stored text is rewritten on the next save).
- **Quick-comment dropdowns** (photo markup Comment, Flag a finding / Concern Quick comment — shared `SelectBox`): every
  comment shows in full, wrapped (menu as wide as the field, at least 260dp; the chosen comment in the field wraps instead
  of an ellipsis). Opening it clears focus (keyboard down).
- **Splash video** (Oct 12, 6.6 s, 720×1280): the old 7 s safety timer cut the last ~0.5 s on a cold start (the video
  ends ~7.2–7.5 s after launch on the emulator). Now 8 s only if it never starts, else video length + 1.5 s; it plays to the
  end once (`VIMS-Splash: done (video ended)`). Fallback band colors updated to the new video's edges (top / bottom rows
  measured constant across the video); `verifySharedAssets` passes.
- Screenshots: `screenshots/oct12b-*.png` (date / time entry, legacy text answer, IAQ PDF; agreement editor, edited +
  legacy viewer, PDF; quick-comment menus; splash). Test APK: `../../VIMS-Android-test-v0.15.0-2026-10-12.apk`.

## Team QA list Oct 13 (v0.16.0) — rules in `../docs/validation-rules.md`

- **Numbers:** `util/Validation.kt` `Num.parse` reads every number ignoring grouping commas, spaces and a leading `$`
  (`"$450,000"` = 450000) — wizard checks, checklist `num` items, IAQ level, plan prices, report PDF. Valuation and Total
  sq ft store digits and show grouping commas (`GroupedNumberTransform`); the demo seed's `"450,000"` passes Next.
- **Number limits** (`Limits`): `Counter` takes `min` / `max` and disables − / + at the ends (wizard room counts and unit
  mix 0–20, Inspector seats 1–50 and never below the inspectors on the license; Add inspector stops at 50). Typed values
  above the max show "Enter a number up to <max>" (sq ft 100,000, valuation 100,000,000, lot size 10,000, checklist `num`
  99,999, room counts "Number of kitchens / bathrooms / bedrooms / stories …" 20, IAQ level 99,999).
- **Checklist `num` items:** digits + one `.` (typed or pasted; commas / `$` dropped), decimal keypad, inline error as soon
  as the value is above the max; 0 is allowed. Text items ("System number") stay free text.
- **No auto-selection:** `Components.FieldText` (used by `VInput`, the price fields, checklist question fields, markup
  inputs) holds a `TextFieldValue`: focus from Next / code puts the cursor at the END, a tap where tapped, never
  select-all; unfocused it rests at 0 so a long single-line value shows its start; a filter that drops characters keeps
  the cursor in place.
- **Edit agreement = block editor:** the agreement as the viewer's blocks (title, paragraphs, bullets, heading, one block
  per state disclosure, closing). The form fields and every block containing `___` or ☐ are locked (read-only, "Locked"
  tag, no delete); every other block is its own multi-line field with Delete (confirmation; not the title) and + (add a
  paragraph below); "Add paragraph" at the end. Blank blocks block Save (highlighted, scrolled to). Stored in the same
  `companies.agreementText` column as JSON `{"format":"vims-agreement-blocks","v":1,"blocks":[{t,text,state?,lead,locked}]}`
  (`data/InspectionAgreement.kt` `AgreementBlocks`; no Room migration). Plain-text edits saved before v0.16.0 still load
  (split as the viewer showed them; blocks with blanks / checkboxes become locked) and are rewritten as JSON on the next
  save. Viewer + PDF render the blocks with the form block after the title; Use VIMS agreement resets.
- **Manage checklist:** trash asks "Delete this item?" / "<question> and its options will be removed from new
  inspections." (headers: "Delete this header?"). There is no section delete on Android.
- **How VIMS works:** support@ogrelogic.com is a link (ACTION_SENDTO `mailto:`); with no email app the address is copied
  and a toast says so.
- **Plans & pricing:** Delete on each plan (confirmation; hidden when only one plan is left; Additional inspector has
  none). A deleted selected plan falls back to the first remaining one. Persisted in the company's account JSON.
- **Billing ZIP / postal code:** letters, digits, space, `-`, uppercase, max 10; valid 3–10 characters; text keyboard
  with caps.
- **Ownership:** only the current owner (from the inspectors list) can transfer it; they see Make owner on every other
  inspector (admin or not, including a previous owner). Confirmation: "Make <name> the owner? … You'll stay an admin. Only
  the new owner can transfer ownership again." A non-owner admin sees "Only the owner can transfer ownership." under the
  owner row; nobody can reclaim it themselves (no controls on your own row).
- Screenshots: `screenshots/oct13-*.png`. Test APK: `../../VIMS-Android-test-v0.16.0-2026-10-13.apk`.

## Client requests Oct 16 (v0.17.0)

- **One finding line everywhere:** the Summary screen and the report's Summary of Findings both read **Section** — custom
  comment — quick comment (empty parts left out, no dangling dash). The PDF keeps its per-category numbering, the app its
  colored dots; the per-section "Findings" block in the PDF uses the same custom — quick text.
  `Finding.custom` / `Finding.quick` are stored separately from now on (Flag a finding from a photo, the Concern sheet);
  `Finding.text` still holds the combined line, and findings saved before the split (no `custom` / `quick`) show their
  stored `text` (`Finding.body`). Findings are stored as JSON (`findings.json` column), so no Room migration.
  Flag a finding: the quick-comment dropdown keeps its own choice (with "No quick comment" to clear it) instead of
  overwriting the Description; Description (custom comment) is required only when no quick comment is picked. From a
  photo it opens pre-filled with the photo's custom and quick comments. Concern findings: custom = "<item>: <description>",
  or "<item>" when no description was typed.
- **Photo markup:** no "Comment" label; the quick-comment dropdown takes the full row (Draw / Stamp labels stay).
- **Report preview fast scroll:** a thumb on the right edge follows normal scrolling; dragging it jumps through the report
  with a "Page X of N" bubble. Only the thumb takes touches (pages still scroll under the rest of the edge) and it sits
  below the top bar. Checked on the phone and at 1600×2560 / 320 dpi, portrait and landscape.
- **Cover footer:** "This inspection report is the property of <Company name>." — the name comes from the signed-in
  inspector's Company profile (`{companyName}` in the cover layout) and is underlined in the PDF; the footer still wraps
  beside the theme art.
- Screenshots: `screenshots/oct16-*.png` (`oct16-summary-vs-pdf.png` = Summary screen next to the PDF summary page).
  Test APK: `../../VIMS-Android-test-v0.17.0-2026-10-16.apk`.

## QA round Oct 14 + client requests Oct 17 + shared v1.9 (v0.18.0)

QA list (Oct 14):
- **No auto-select on focus:** every field goes through `FieldText`; a whole-text selection that arrives within 0.6 s of
  focus without typing (some keyboards / Tab traversal) is dropped, so the cursor stays at the end. The wizard's State
  field no longer clears itself on focus: it keeps the state's name (cursor at the end) and opens the full list; typing
  narrows it.
- **Company code:** typed as shown, "VIS-4827": uppercase, the "-" is inserted after the 3rd letter (Backspace removes it),
  digits only after it, no suggestions; the keyboard switches to the number pad once the letters are in. Pastes such as
  "vis4827" / "VIS 4827" become "VIS-4827".
- **Temperature (°F):** one "." and an optional leading "-", decimal keypad; −60 to 140 (72.5, −4.5).
- **Make owner / Make admin:** the session role now always follows the company's inspectors list (on load / restore and
  after every inspectors change), so a transfer or admin change takes effect at once and survives a restart (demo rows
  are matched by email). Make owner keeps its confirmation.
- **Remove inspector:** "Remove <name>?" confirmation (owner / admins only; never the owner or yourself).
- **Company profile:** read-only for plain inspectors (details as rows, logo shown, agreement View / Open only; the
  view model also refuses saves, logo and agreement changes from non-admins).
- **Subscription:** the card is remembered as brand + last 4 + expiry only (`AccountState.card` / `CardOnFile`, a stand-in
  for Square's card on file — TODO(backend): Square Cards API); the number and CVC are never stored. Updating shows
  "Visa •••• 4242 (exp 08/28) — Use this card" / "Use a different card"; an expired card asks for a new one.
- **Uploaded agreement:** opens in a viewer app ("Open" on the agreement card) via FileProvider with the real MIME type;
  the stored file's extension comes from the picked document's MIME type (Drive files may have no extension); images are
  accepted too; no viewer → toast.
- **Plans & pricing:** the short description is multi-line (up to 200 characters, line breaks kept) and wraps on the plan
  cards and the subscribe screen.
- **Settings:** the same rows as iOS — Report cover shows the full cover label, Photo size "JPG · ~750 KB"; the version /
  checklist-data line was removed (also in debug builds).
- **Trial dialog:** stays inside the safe area and scrolls, so "Continue to app" is reachable in phone landscape.

Client (Jeremy, Oct 17):
- **Photo source:** Add asks "Photos" (Photo Picker), "Camera" (in-app CameraX) or "Drive" (system document picker, which
  includes Google Drive), images only; a picked image is EXIF-rotated, capped at 2048 px and opens in markup like a capture.
- **Cover picker on one page:** Color, Theme (category), Picture ("No picture" first) and Style (Shaded, Framed, Solid —
  Solid can carry a picture). Covers saved with the old "Solid" category are migrated on load to style Solid + No picture
  (written back). Labels: "Blue · No picture · Solid".
- **Cover footer:** always in `covers.layout.footer.box.left` (bottom-left, never past 4.25 in), or the right box when the
  theme art sits on the left (4th of July); centered in the box, shrinks to fit (incl. a state notice), drawn above the art,
  company name underlined. **2nd address line** starts and ends exactly under the first line's value underline.
- **Split address:** Inspection address (street) → City (required) → State → ZIP code (optional, 12345 or 12345-6789; the
  dash is inserted). Stored as wizard fields "City" / "ZIP code"; cover line 2 / list subtitle / emails read
  "City, ST ZIP". Older inspections keep their combined text and print as before; opening one in the edit wizard fills
  street / City / ZIP from it (saved only on Update checklist). No Room migration.
- **Summary:** long-press asks "Remove this finding?" (Remove / Cancel).
- **visibleIf** (data v1.8, `ChecklistEngine.isVisible`): `{q, atLeast}` and `{q, includes}`; hidden items aren't shown,
  validated or printed (Lead sample locations, Meth "Other area tested", WDI and Wind Mitigation follow-ups). Older
  checklist snapshots don't get the new items; they do get the new photo categories (Meth "Cartridge Result").
- **Section titles:** `title` is shown everywhere (wizard chips, section lists / drawer, headers, PDF, summary, admin):
  "Septic System", "Wood Destroying Organism Inspection"; `name` stays the key. Long titles wrap to 2 header lines.
- **Radon:** the section's `reportNote` paragraphs print after its items and before Overall condition.

Shared v1.9 (client item 13):
- **Wind Mitigation** prints as the 4-page Uniform Mitigation Verification Inspection Form (OIR-B1-1802 Rev. 01/12,
  official wording): owner grid, Q1–Q7 with ☐/☒ boxes and filled values, roof-covering table, Opening Protection Level
  Chart with X marks, qualified-inspector block (signature / date and homeowner lines left blank), every page footer with
  initials, property address, validity note and "Page X of 4" (a counting pass sets N). **Termite** prints as our own
  one-page Wood Destroying Insect Inspection Report (NPMA-33 is not reproduced). Photos follow on the section's photo page.
  Only inspections built from v1.9 data use the forms; older Wind Mitigation / Termite snapshots keep the checklist page.
- **Prefill** on first open (until the section is started): client, street, city, zip, client phone / email, license type
  ("Home Inspector"), inspector initials (from the Company profile's lead inspector). Typed values are never overwritten.
- **Splash:** `vims-splash-wide.mp4` when the screen is wider than tall, else the portrait video; both play their full
  10 s (`verifySharedAssets` checks both files).
- Debug: `--es insp latest` opens the most recent inspection; `filesDir/debug-answers.txt` lines
  `Section::Question=value` (`Section::!done`) are applied on a debug launch (copy in with `adb shell run-as`).
- Screenshots: `screenshots/oct21-*.png`; `screenshots/sample-report-wind-mitigation-wdi.pdf`.
  Test APK: `../../VIMS-Android-test-v0.18.0-2026-10-21.apk`.

## Team QA list Oct 22 + shared v1.9.1 (v0.19.0) — rules in `../docs/validation-rules.md` "Team QA Oct 22"

- **Auto-sync:** with Settings → "Auto-sync when online" ON, queued inspections sync by themselves — when the device comes back
  online (`ConnectivityManager` default-network callback; `ACCESS_NETWORK_STATE` is the only new permission, still no
  `INTERNET`), when the app returns to the foreground (`MainActivity.onResume`), after sign-in, and ~1.5 s after a save
  (section Save, Build / Update checklist, report generated, markup saved, finding added) — `AppViewModel.requestAutoSync`.
  OFF = manual only ("N inspections waiting · tap Sync now"). Still the local stub (`LocalSyncService`, `TODO(backend)`); the
  count drops to 0 and the header pill reads "N queued" online, "Offline · N queued" offline, "Synced" / "Offline" when
  nothing waits. Sync now while offline says the inspections stay queued.
- **Keyboard:** a tap anywhere outside the active text field closes the keyboard on every screen and inside dialogs
  (`ui/components/KeyboardDismiss.kt`: the root and `ConfirmDialog` watch taps in `PointerEventPass.Initial` without consuming
  them, so buttons / chips / rows still work and drags past the touch slop — scrolling — never count). Text fields register
  their bounds (`Modifier.keepsKeyboard()`), so tapping a field or moving to another one keeps the keyboard up.
- **Numbers while typing** (`Filters.number(v, decimals, max)`, stateless — characters past the max are dropped from the end):
  Temperature digits / one "." / optional leading "-", 1 decimal, max 5 characters (−60 – 140 on Next); Total sq ft whole
  numbers (number pad); Valuation (decimal keypad now) and Lot size at most 2 decimals; checklist `num` items at most 2 decimals,
  `decimals: n` overrides (Radon "Measured level (pCi/L)" 1, max 999.9), `integer: true` → number pad, digits only (Septic
  "System number" 1 – 99, counts, years). Whole-number fields (Total sq ft, `integer` items — `WholeNumberInput`): a "."
  typed or pasted and everything after it is discarded ("2450.5" → "2450", never "24505"); digits typed right after a rejected
  "." aren't accepted either, with a "Whole numbers only" hint, until a character is deleted or the field is left. An older answer that breaks a rule shows the error inline ("Enter a whole number",
  "Use at most 1 decimal place").
- **Old checklist snapshots** (`ChecklistEngine.upgradePickers` on load, matched by section + question): text → `num` (Radon level,
  Septic System number) and the current `integer` / `decimals` flags; Meth Test (High Detail) "Test date and time" + "AM/PM" →
  "Test date" (date picker) + "Test time" (time picker). `upgradeAnswers` moves the old text: "10/12/2026 9:30" + PM → Oct 12, 2026
  / 9:30 PM (also "Oct 12, 2026 2 pm", ISO); text that can't be read as a date stays in Test date as typed.
- **New Inspection:** nothing preselected (data v1.9.1 chip defaults / `defaults.inspType` / `loan` are null —
  `WizardDefaults` fields are nullable now, otherwise the JSON wouldn't load). Type of inspection is required: red " *" on its
  label, Next shows "Select the type of inspection" and scrolls to it. Checklist depth still comes from Settings; date / time
  default to now; room counts keep their numbers; TX still auto-selects Texas (leaving TX clears the automatic type).
- **Delete / remove confirmations** — short, explicit buttons: inspection "Delete this inspection?" / "This removes the checklist,
  photos and report for <address> from this device. Some states require keeping reports for 3–5 years." with Save report first
  (only when a report exists) · Delete · Cancel; plan "Delete the “<plan>” plan?" / "It will no longer be offered on the
  Subscription screen." (+ "Your company will move to <next plan>." for the current plan) · Cancel / Delete; same style for
  finding, inspector, checklist item / header, agreement block and account. `ConfirmDialog` scrolls when taller than the screen.
- **Responsive** (checked at 360 dp × font 1.3, the normal phone and 1600×2560 / 320 dpi): the checklist badge row stacks the
  hint under a long form badge (Texas TREC…) instead of a one-word column; the header title moves under the buttons when two
  lines can't hold it ("Wood Destroying Organism Inspection", "Texas — III. Heating, Ventilation and Air Conditioning
  Systems"); Home rows put the status pill under the subtitle when narrow (no more "210 Wi…" / "Standal-one"); `BinfoRow`
  keeps its label readable beside a long value (Payment "Square · Visa •••• 4242 (exp 08/28)"); Power / Gas / Water rows put
  the label above the chips when it wouldn't fit on one line (`InlineOrStacked`); paired fields (wizard Date / Time, Year /
  Total sq ft, Valuation / Lot size, Company License # / Phone) stack when a half would be narrower than 150 dp × font scale
  (`FieldPair`); Subscribe plan cards show the price under the plan name on small screens.
- Screenshots: `screenshots/oct22-*.png`. Test APK: `../../VIMS-Android-test-v0.19.0-2026-10-22.apk`.

## Client Oct 22 + shared v1.9.2 (v0.20.0)

- **vimsinspect.com emails:** defaults are now Feedback & support `support@vimsinspect.com` and Report quality copy (BCC)
  `quality@vimsinspect.com`; `support.platformOwners` = `masteradmin@vimsinspect.com` + `admin@vimsinspect.com` (both get the
  VIMS owner settings). `SupportDef` reads the new `support.replacedDefaults` and `support.domainEmails` (informational).
- **Migration on launch** (`RoomRepository.loadPlatform` → `PlatformSettings.replacingOldDefaults`): a stored Feedback or BCC
  address that still equals an old default in `support.replacedDefaults` (`VIMSInspect@Gmail.com`,
  `jeremy@visionpropertyinspections.com`; trimmed, case-insensitive) becomes the current default and is written back; an
  address the owner typed in is kept, the BCC On/Off is untouched. Fresh installs get the new defaults.
- How VIMS works no longer falls back to a hard-coded address: a blank Feedback email falls back to `support.feedbackEmail`.
- **Phase 2 — Plumbing** (Pre-Dry Wall 4-way): "Shower pan filled for testing" and "Shower pan leaking" (Yes / No) before
  Comments, from the data; printed in the report like every other item. Inspections built before v1.9.2 keep their saved
  checklist (no new items) and open / print as before.
- **Covers:** Holidays + Halloween (Fall picture and rect, `themeArt`); Seasonal unchanged.
- Screenshots: `screenshots/oct22-client-*.png`. Test APK: `../../VIMS-Android-test-v0.20.0-2026-10-22.apk`.

## Client Oct 23–25 + shared v1.10.0 (v0.21.0)

- **Covers:** new Spring, Christmas and Fall art; Halloween has its own `covers/halloween.webp`; Holidays gains **Cinco de Mayo**
  (`covers/cinco-de-mayo.webp`). All data-driven (`covers.categories` / `themeArt`), packaged from `shared/` and checked by
  `verifySharedAssets`; the PDF draws each picture into its rect (rects now match each picture's aspect ratio).
- **Type of inspection:** "Code" is gone from new inspections (`wizard.retiredInspectionTypes`); an inspection saved as Code still
  opens, prints "Code", and its edit wizard shows Code selected (`WizardDef.typeOptions`). Tapping the selected type again
  deselects it; Next then shows "Select the type of inspection" (still required).
- **Areas locked** (`wizard.areasLockedTypes`: Phase 1, Phase 2, Tests Only, 4 Point): step 3 shows the exterior, interior room and
  utility options disabled (dimmed, not tappable, disabled semantics) under one note ("…aren't used for a Tests Only inspection");
  Bedrooms / Bathrooms / Hallways stay editable. Another type unlocks them with the earlier choices intact; while locked they
  add no sections (`ChecklistEngine.buildGroups`).
- **Tests Only** = Inspection Info + Testing (the tests chosen in step 4, + admin-added Testing sections) + Summary.
  `checklistBuilder.phaseTypes` groups are now read like the standard layout (`sections`, `optional`, `order`, `always`, `then`, `sub`).
- **No sync in Phase 1** (`features.sync`, default false when missing): no sync pill in any header (the "Offline · 3 queued" badge),
  no Settings "Sync" section / Sync now, no automatic sync or connectivity watch, Home's second tile shows "In progress", a "Queued"
  inspection reads "Scheduled", and How VIMS works / report ready / generate report / sign-out texts no longer mention syncing or
  uploading. The sync code stays behind the flag for Phase 2 (`AppViewModel.syncEnabled`, `NetState.shown`, `Features.sync`).
- **How VIMS works:** support address = the platform Feedback & support email, `support@vimsinspect.com` (old defaults migrated on
  launch since v0.20.0; checked on an install upgraded v0.19.0 → v0.20.0 → v0.21.0).
- **New checklist items reach older inspections:** on load, questions added to a section since the inspection's snapshot are merged
  in (data order, answers kept, nothing removed) — e.g. Phase 2 Plumbing "Shower pan filled for testing" / "Shower pan leaking" on
  inspections built before v1.9.2. Only for purely additive data changes and sections the company admin hasn't edited
  (`ChecklistEngine.mergeAdded`); restructured sections (Termite / Wind Mitigation before their v1.9 forms) keep their snapshot.
- **Free trial:** after the 30-day free look with no active subscription, every way into a new inspection (Home +, New inspection,
  side menu, the wizard itself, Build checklist — debug deep links included) shows the "Your free trial has ended" Subscribe prompt;
  existing inspections open, generate and share / re-send as before. **One free trial per device:** the first company created on
  the device records the trial start in app-level `SharedPreferences` `vims_device` (outside every account / company; upgrades take
  the earliest non-demo company's start). Later companies start with the trial used (`AccountState.trialUsedOnDevice`, Subscribe
  shown). The file stays in Auto Backup on purpose: a restore can only bring back "trial used", never a new trial.
  `TODO(backend)`: server enforcement via ANDROID_ID + Play Integrity. Testers: `--ez resetDeviceTrial true` (debug builds).
- **Inspection agreement** 2026-10-25 (final): "☐ Wind Mitigation Inspection $____" on the Boiler System line; agent name and agent
  email on separate lines. Companies with an edited or uploaded agreement keep theirs (the locked form block is always the VIMS one).
- Screenshots: `screenshots/oct25-*.png` (phone 1080×2400 and tablet 1600×2560). Test APK: `../../VIMS-Android-test-v0.21.0-2026-10-25.apk`.

## Client Oct 28 + shared v1.11.0 (v0.22.0)

- **Master admin** (`support.platformOwners`: masteradmin@ and admin@vimsinspect.com, trimmed + case-insensitive, exact addresses
  only — masteradmin@vimsinspection.com is not one): a clearly labeled **Master admin** group in the side menu and a **Master admin**
  section in Settings (Plans & pricing, Report quality copy (BCC), Feedback & support), plus a **Master admin** badge on the
  Settings account card and the side-menu header. Company admins keep Manage checklist and Inspectors; Plans & pricing is gone from
  the company Admin group and the screen itself shows "Only a VIMS master admin…" to anyone else (like the other owner screens).
  - What was wrong on Android: the owner flag *was* set (checked on v0.21.0: a fresh masteradmin sign-up got it), but the owner
    tools were two unlabeled rows inside the company "Admin" group of Settings — nothing in the side menu, no badge — so a master
    admin looked exactly like any company admin; and **Plans & pricing was company data** (`AccountState.plans` in the companies
    row): every company admin could edit it, and a master admin's edits only changed his own company's prices.
  - Plans and prices are now **platform-level** (`PlatformSettings.plans` / `extraInspectorMonthly` / `extraInspectorYearly` in the
    `kv` table, null = the shipped `subscription` defaults; `Pricing`): one set for every company, written only by a master admin
    (`updatePlatform` ignores anyone else). The legacy per-company copy in `AccountState.plans` is no longer read, so upgraded
    companies get the v1.11 prices. `TODO(backend)`: the server owns plans and prices.
  - The flag is set by `LocalAuthService` on every session it hands out (Create account, Sign in, Join company) and re-checked by
    `RoomRepository.activate` (also session restore at launch); debug builds log `VIMS-Session: activate … masterAdmin=…`.
    Verified: v0.21.0 sign-up → upgrade → restored session is master admin; Create account " Masteradmin@VIMSInspect.com ";
    Sign in "MasterAdmin@VIMSINSPECT.COM"; Join company " Admin@VimsInspect.COM " (plain inspector + master admin).
- **Restore checklist to original** (Manage checklist, company admins): edited VIMS sections show an **Edited** tag and
  company-added ones **Added**; Edit section has **Restore original** (or **Remove section** for an added one) and Manage checklist
  ends with **Restore entire checklist to original** — each with a confirmation saying it removes the company's changes. Restoring
  drops the company's overrides / added sections and the VIMS default from the shared JSON is used again for new inspections.
  Inspections already started keep their saved checklist; restored sections are remembered (`ChecklistEdits.restored`) so the
  data-added-items merge never puts back an item the company had removed into a started inspection. Saving a section unchanged no
  longer counts as an edit.
- **Pricing (data v1.11):** App only $34.95/mo or $385/yr; additional inspector $24.95/mo or $275/yr; Pay per report $5 (no
  yearly); Portal + App $74.95/mo or $825/yr with `comingSoon` → "Coming soon" label, dimmed, not selectable. New optional keys
  `priceYearly`, `comingSoon`, `extraInspectorYearly`, `billingPeriods` decode with defaults; `AccountState.billingPeriod`
  (default monthly). Subscribe: **Monthly / Yearly** toggle, prices and totals per period ("Yearly total $660.00/yr"), extra
  inspectors at the company's period; the plan / period choice is saved with Start / Update subscription. Confirmation, Billing
  ("Billing period", "Yearly total", next billing a year out), Settings "Plan & billing" and Inspectors show the period. Plans &
  pricing (master admin) edits monthly and yearly prices (and the additional-inspector rates). Billing stays the local stub
  (`TODO(backend)` Square).
- Screenshots: `screenshots/oct28-*.png` (phone 1080×2400 and tablet 1600×2560). Test APK: `../../VIMS-Android-test-v0.22.0-2026-10-28.apk`.

## Master admins exempt from trial / subscription (v0.22.1)

- A VIMS master admin's session (`support.platformOwners`) never shows the free-look splash, the trial-ended / "Free look already
  used on this device" / Subscribe prompts, and can always start new inspections (`hasAccess(…, masterAdmin = true)`; Home +,
  New inspection, side menu, wizard and Build checklist). Home shows "Master admin · no subscription needed" instead of the trial
  banner, Settings "Plan & billing" says the same, and Billing shows Status "Master admin" / "No subscription needed" (no plan,
  no Subscribe) unless the company already has an active subscription. Subscribe stays reachable and says no subscription is needed.
- A master admin's Create account neither records the device's one free trial nor starts as "trial already used"
  (`LocalAuthService.createAccount`), and the v0.21.0 upgrade backfill skips companies owned by a master admin. A device trial that
  an owner company already recorded on v0.21.0 / v0.22.0 stays recorded (it can't be told apart from a deleted real company).
  `TODO(backend)`: the server grants the exemption with the session's master-admin flag.
- Non-owners are unchanged. Verified: trial-used device → Create account masteradmin@vimsinspect.com → no prompt, inspection built;
  a normal company afterwards still gets "Free look already used"; fresh install → owner sign-up leaves `vims_device` empty (also
  after a relaunch) and the next normal company gets the full 30 days. Screenshots `screenshots/oct28-v0221-*.png`. Test APK:
  `../../VIMS-Android-test-v0.22.1-2026-10-28.apk`.

## Client Oct 28, 2nd round + shared v1.11.1 / EULA 2026-10-28 (v0.23.0)

- **Manage checklist:** the Restore block is now at the TOP (under the hint, above Add section) with the client's wording —
  **Restore all checklists** (whole checklist, same confirm as before) and **Restore selected checklists** (each section is one
  checklist): a picker listing only Edited / Added sections with checkboxes (52dp rows) and **Select all**, then one confirm naming
  them ("Restore 2 checklists?"; added sections are named as removed). One batch write + one toast (`AppViewModel.restoreSections`).
  Both buttons dimmed/disabled with "Your checklist matches the VIMS original — nothing to restore." Per-section Restore original
  unchanged. Company admins and master admins alike.
- **Plans & pricing:** the Additional inspector card says "Applies to every plan, so it can't be deleted." (no Delete, by design).
- **EULA** `shared/legal/eula.json` 2026-10-28 (Revised October 28, 2026; 3.5, "Notices to Us:" address) is rendered from data as
  before; the version bump shows the "Updated license agreement" gate once to every signed-in user (verified by upgrading v0.22.1 in
  place: gate → I agree → no gate after relaunch). Settings → Legal shows "Revised October 28, 2026".
- **Cancellation** per EULA 4.1 / 12.3 / 12.4 — see "Cancel subscription" above.
- Screenshots `screenshots/oct28b-*.png`. Test APK `../../VIMS-Android-test-v0.23.0-2026-10-28.apk` (debug-signed like v0.22.1, installs over it).

## Client Oct 29 + shared v1.12.0 (v0.24.0)

- **Checklist data v1.12.0:** Exterior Walls (High Detail) "Water Pressure rating" Good / Low / High; Outside Utilities
  "Compressor size (home sq ft)" (`renamedFrom` "Compressor size (sq ft)"); Garage + Attic "Receptacles" + Non GFCI; Garage, Attic
  and Kitchen "GFCI receptacles (count)" / "Standard receptacles (count)" (`num`, `integer`, number pad). Printed like any answer.
- **Started inspections** (`ChecklistEngine.upgradePickers` → `carry`, in memory on load): a line still carrying a renamed item's
  old label takes the new one, so `mergeAdded` still sees an additive change and new items (the counts) join the snapshot as
  before; single / multi lines whose options only grew get the new options (not in company-edited sections); the room-count flags
  are copied on. `upgradeAnswers` copies an answer saved under the old label's key ("header|Compressor size (sq ft)") to the new key
  unless that already has one; the old key is left in place. **Company overrides** (`upgradeEdits`, on load): renamed labels + the
  flags; the company's own options and item list are kept (new data items reach an edited section only via Restore original).
- **`optionsFromCount`** (Bathroom No. / Bedroom No.): options 1..n from the inspection's live room count (min 1; the static list
  when the count is missing); a saved answer outside 1..n (count lowered later) stays listed. **`defaultFromRoomNumber`**: on opening
  "Bathroom 2" the item is written "2" if it has never been answered (no key — a deselected answer stays cleared), the section
  isn't Done and 2 is an option (`AppViewModel.prefillSection`, like the v1.9 `prefill`). Status is not touched: progress counts
  sections saved with Save / Save & next, so a pre-answer never makes a section In progress or Done; the report prints Done
  sections only.
- **Camera zoom:** pinch on the preview + chips 0.5x (when the lens goes below 1x) / 1x / 2x / 5x (or the max when below 5x) via
  `cameraControl.setZoomRatio` within `zoomState`; current ratio shown above the chips. **Markup zoom:** two fingers pinch / pan
  (1x–5x), one finger draws / stamps as before (a stroke started before the second finger lands is dropped; stamps are placed on
  release); "4.0x Fit" pill resets. Marks stay in image coordinates, so the saved markup is unchanged by zoom. No double-tap zoom in
  markup (one finger draws there; there's no separate plain photo viewer).
- **Save & next / Save & return icon:** plain right arrow (`save-return-svg`, inline fallback updated).
- Verified by installing over v0.23.0 with existing data (renamed answer 2400 kept, Low + High, Garage/Kitchen counts merged,
  company override renamed, Bathroom 1's own answer kept). Screenshots `screenshots/oct29-*.png`. Test APK
  `../../VIMS-Android-test-v0.24.0-2026-10-29.apk` (debug-signed like v0.23.0, installs over it).

## Client Oct 30 + shared v1.13.0 (v0.25.0)

- **`countChoice`** (combined Receptacles, 28 items in 25 High Detail sections): None on the first row; GFCI and Standard each
  on their own row, button left, "# of receptacles" box right (number pad, whole numbers 0–999, optional, "Whole numbers only"
  like `integer` fields; TalkBack "Number of GFCI receptacles"). Rules in `CountChoice` (Models.kt), same as the prototype: None
  clears the others and every count; GFCI / Standard toggle and combine; deselecting one clears its count; typing a count clears
  None and a count above 0 selects its option. **Stored like `airReading`, no Room schema change:** `values[key]` = selected
  options (button order), `inputs[key]` = counts as a JSON object (`{"GFCI":4,"Standard":6}`). Answered = at least one selected;
  `visibleIf {includes}` reads `values` so it matches selected options. Report: "GFCI (4), Standard (6)", "GFCI" or "None".
- **`replaces`, started inspections:** a saved list that still has any replaced label as a non-countChoice line (old "Receptacles"
  single, "GFCI" Yes/No, Oct 29 count fields — matched by label + type, since the new item is often also "Receptacles") never gets
  the new item (`ChecklistEngine.hasReplacedItems` guard in `mergeAdded`). Such a list is brought up to date against the frozen
  v1.12.0 list of that section (`assets/legacy/checklists-v1.12.0-receptacles.json`, `ChecklistLoader.loadLegacy`) instead of
  v1.13.0, so it shows exactly what v0.24.0 showed — including the Oct 29 counts / "Non GFCI" that v0.24.0 merged in memory into
  snapshots taken before v1.12 — and every answer typed then stays visible and printed. New inspections get the new item.
- **`replaces`, company overrides** (`ChecklistEngine.replaceItems`, in `upgradeEdits` on load): the old lines under the same
  sub-header are swapped for the new item at the first one's position; the company's other edits (renames, order, removals) are
  kept. Manage checklist shows the item's options read-only ("GFCI + count"); rename / move / delete work like any item; Restore
  original works as before.
- **Report quality copy (client Oct 30):** no `EXTRA_BCC` on the report email any more (the phone's mail app showed the Bcc line
  to the inspector); the state-document email never had one. The master-admin setting (On/Off + address) stays; its text says the
  VIMS server sends a separate copy. `TODO(backend)` in `shareReport`: until the server send exists no quality copy is sent.
- Verified by installing over v0.24.0 with an in-progress High Detail inspection holding old receptacle answers (Attic snapshot
  from before v1.12 with "Non GFCI" + counts 2 / 7, Garage GFCI + 4 / 6, Kitchen 5 / 3, Landscaping, Bathroom 1): all kept, no
  duplicate item; a new inspection shows the combined item. Screenshots `screenshots/oct30-*`. Test APK
  `../../VIMS-Android-test-v0.25.0-2026-10-30.apk` (debug-signed like v0.24.0, installs over it).
