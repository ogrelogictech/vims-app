# VIMS — iOS app (native SwiftUI)

Native **iOS** build of VIMS Phase 1 (Vision Inspection Management Solutions), built screen-for-screen and
behavior-for-behavior against the client-approved prototype (`../index.html`, `../report.html`, `../screens/`).
Swift 5 language mode · SwiftUI + Observation · iOS 17.0+ · iPhone only · Apple frameworks only (no packages).
The Android twin lives in `../android/` and is built separately.

## Open, build, run

```bash
open ios/VIMS.xcodeproj          # scheme: VIMS

# command line (from ios/)
xcodebuild -project VIMS.xcodeproj -scheme VIMS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData build

xcrun simctl install "iPhone 17" build/DerivedData/Build/Products/Debug-iphonesimulator/VIMS.app
xcrun simctl launch "iPhone 17" com.vims.app
```

Bundle id `com.vims.app` is a placeholder. First launch creates the demo account (see below); the sign-in screen
is prefilled with it (`jeremy@visionpropertyinspections.com` / `inspect2026`). Other accounts come from
**Create account** (new company) or **Join a company with a code** — each starts with no inspections.

Cold launch plays the splash video, then Sign in (or Home when a session is saved).

### DEBUG screen jumper (review screenshots)

Debug builds accept launch arguments (see `VIMS/App/DebugLaunch.swift`), e.g.

```bash
xcrun simctl launch --terminate-running-process "iPhone 17" com.vims.app -screen summary
xcrun simctl launch --terminate-running-process "iPhone 17" com.vims.app -screen section -depth high
xcrun simctl launch --terminate-running-process "iPhone 17" com.vims.app -resetData -skipLogin -noSplash
```

`-screen` accepts: `login signup forgot join home splash wizard sections section drawer photos markup flag summary
report reportReady settings company instructions manage editSection plans inspectors subscribe subscribed billing
feedback phase1 phase2`. Extras: `-step N` (wizard 1–4 / cover picker 1–3), `-depth high|standard|fast`,
`-section NAME`, `-inspection PREFIX|TYPE` (e.g. `Texas`, `"4 Point Inspection"`), `-generate` (with
`-screen reportReady`: regenerate the PDF first), `-group NAME` (Manage checklist), `-overview` (phase screens),
`-trialDaysLeft N`, `-resetData` (wipes the SwiftData store + files and recreates the demo account),
`-skipLogin` (signs in as the demo account), `-signInAs EMAIL`, `-mailSelfTest`, `-noSplash`, `-video` / `-noVideo` (the launch
video is skipped by default whenever `-screen` is given), `-validate` (submits the screen's form once so its
validation errors show).
None of this is compiled into Release builds. The prototype's yellow review/jump button is intentionally not a
user feature.

## Architecture

```
SwiftUI views ──► AppStore (@Observable, @MainActor)  ──► Repository (SwiftDataRepository + FileStore)
                     │  ├─ ChecklistConfig (shared JSON, loaded at launch)
                     │  ├─ ChecklistCatalog (JSON + admin overrides, checklist builder)
                     │  └─ Services: AuthService · SubscriptionService · SyncService (local stubs)
                     └─ path: [Route]  ──► one NavigationStack (custom blue header, system bar hidden)
```

- **Navigation.** `Route` enum + `NavigationStack(path:)` in `RootView`. Root is Login or Home depending on the
  session. Every screen uses `Screen`, which draws the prototype header (`.apphdr`: back/menu left, title +
  subtitle, contextual Photos / Sections / Home actions right, plus the offline/sync badge). Edge-swipe back is
  kept. The checklist drawer, photo markup viewer (full-screen cover), flag-a-finding bottom sheet, trial
  splash, and toast are overlays/modals.
- **Local database: SwiftData, scoped per user.** `Data/Repository.swift` (`SwiftDataRepository`, behind the
  `Repository` protocol) with the models in `Data/Store/Records.swift`, stored at
  `Library/Application Support/VIMS.store`:
  - `UserRecord` — id, email (unique, lowercased), name, companyID, salted PBKDF2-SHA256 password hash
    (`PasswordHasher`; TODO(backend): the Laravel API owns credentials), per-user settings.
  - `CompanyRecord` — id, join code (unique), profile (details, **logo file**, inspectors & roles, feedback email),
    subscription (plans & prices, per-inspector rate, trial, payment label), checklist customizations.
  - `InspectionRecord` — id, **userID**, companyID, scheduled date, and the inspection payload (wizard values,
    section list, status, answers, photo refs, findings, report info, sync flag).
  - Files live under `Documents/vims/` in owner folders: `users/<userID>/photos/<inspection>/…`,
    `users/<userID>/reports/<inspection>.pdf`, `companies/<companyID>/` (logo, agreement).
  - **Isolation:** after sign-in `AppStore.loadSession` loads only that user's inspections and their company's
    record; every fetch is filtered by `userID`, and a write is refused if the row belongs to someone else.
    Sign-out flushes, then clears everything in memory. Create account = new user + new company (owner/admin,
    fresh free look, no inspections); Join with code = the user is attached to that company (shared profile,
    logo, checklist, plans, inspectors) but still only sees their own inspections.
  - **Migration:** on the first launch of this build, an existing JSON store (`app.json` + `inspections/*.json`)
    is imported once into the demo user/company, its photos/reports/logo are moved into the owner folders, and
    the old files are kept in `Documents/vims/legacy-migrated/` (`Data/Store/Bootstrap.swift`).
  - Writes are debounced and flushed when the app backgrounds. Nothing needs a network.
- **Validation** (`Validation/Validation.swift`, one module implementing `docs/validation-rules.md`):
  `FieldKind` holds the while-typing filters/formatters (no leading or double spaces in any field, no spaces in
  email/password/URL, person-name characters, phone `(801) 555-0134`, join code `VIS-4827`, license/policy,
  digits for years/ZIP, decimals, price with 2 decimals, card grouping incl. Amex + brand, `MM/YY`, CVC 3/4);
  `Validator.error(for:rule:)` holds the on-submit checks (required, email regex, password ≥ 8 + confirm match,
  10-digit phone, join code exists, year 1800–now, > 0 numbers, −60…140 °F, http(s) URL with a host,
  $0.01–$9,999.99, Luhn + expiry not past/≤ 20 years + CVC, unique section/option/plan/inspector email).
  `FormErrors` keeps a form's inline errors: fields show them in c1 red text with a red border, clear them as
  soon as the value is valid, and `Screen(errors:)` scrolls to the first one. Typing goes through
  `FilteredTextField` (UITextField delegate), so formatting is applied per keystroke without dropping input.
  Covered: sign in, create account (Company name + Confirm password), forgot password, join, wizard (each step on
  Next; client name, address, date required), company profile + review URL, add inspector, subscribe card form,
  plan prices, feedback email, checklist editor (section name, questions, options), `num` checklist items.
- **Icons** are the prototype's own set (`shared/icons/icons.json`, 64 × 24-pt stroke paths), rendered by
  `Theme/ProtoIcons.swift` (`ProtoIcon("hdr-back")`, 2-pt round stroke, tinted) — header, group, settings rows,
  buttons, eye, camera, flag, stamps, chevrons. No SF Symbols remain in the UI.
- **Launch splash.** `Views/Shell/VideoSplash.swift` plays `shared/media/vims-splash.mp4` once, muted,
  aspect-fill, tap to skip; with Reduce Motion on it shows the last frame for ~1 s. The launch screen color
  (`LaunchBackground`, from `VIMS-Info.plist`) matches the video's first frame, so there is no white flash.
- **Company identity.** `CompanyLogoBadge` shows the company's uploaded logo (or an initials badge) in Company
  profile, the Settings account card and the Home side menu; the PDF cover and page headers use the same logo
  (initials badge when none).
- **VIMS platform-owner settings** (data v1.2). The feedback email and the **Report quality copy (BCC)**
  (`support.reportBcc` default) are platform-level, not per company: stored once in SwiftData
  (`PlatformRecord` → `PlatformSettings`) and editable only by the platform owner. `Session.isPlatformOwner` is
  true only for `PlatformOwner.email` (jeremy@visionpropertyinspections.com — TODO(backend): the server sends this
  flag/role). Only that account sees Settings → "VIMS owner" (Report quality copy (BCC) with subtitle
  "On · address" / "Off", and Feedback & support); other companies' admins don't, and the routes show "Not
  available" if reached. The BCC screen has the intro text, On/Off, the address (email rule; required while On)
  and Save.
- **Emailing a report** (Report ready → Email to client, `Report/ReportMail.swift`): when Mail is set up,
  `MFMailComposeViewController` opens with To = client email (+ agent email), a subject/body, the PDF attached
  and **BCC = the report-quality address when On** (`ReportMailDraft.make` / `configure`). The BCC address is
  never shown elsewhere in the UI. Without Mail the share sheet opens instead, with a note that a blind copy is
  added when reports are emailed through VIMS. TODO(backend): the server-side send always adds the BCC so it
  can't be removed. The simulator has no Mail account, so the composer wiring is checked with the DEBUG
  `-mailSelfTest` launch argument, which prints the draft (to / bcc / subject / attachment) to the console.
- **Home side menu** (`Views/Home/SideMenu.swift`): hamburger opens a left drawer with the company logo, user,
  email and company; Inspections, New inspection, Settings, Company profile, How VIMS works, Help & feedback;
  admin-only Manage checklist, Plans & pricing, Inspectors; Sign out. Scrim tap or swipe left closes it.
- **Adaptive layout.** Every screen scrolls within the safe areas (no fixed heights), SwiftUI handles keyboard
  avoidance, rows stack their status pill under the text at large Dynamic Type sizes, and Dynamic Type is
  supported up to XXXL. Checked on iPhone SE (3rd gen), iPhone 17 and iPhone 17 Pro Max.
- **Data-driven checklist.** Every section, item, option, photo category, report number, wizard field/chip,
  builder rule, finding category + tagline, quick comment, cover option, and plan comes from
  `shared/data/vims-checklists.json`. Nothing checklist-related is hardcoded.
  - Wizard steps 1–2 render `wizard.step1/step2` in order; steps 3–4 render `exteriorOptions`,
    `roomCounts`, `roomOptions`, `utilityOptions`, `testOptions`. Defaults from `wizard.defaults`;
    `structureSideEffects`, Component sub-chips, Multi-Unit unit mix, and Stories "Other" text box are honored.
  - `ChecklistCatalog.buildGroups` implements `checklistBuilder` (`phaseTypes` for Phase 1 Foundation /
    Phase 2 Pre-Dry Wall; `standardLayout` with `always`, `optional`, `order` tokens `Name?` / `Name×count`,
    the Utility & Function sub-group, and admin custom sections appended to their group).
  - Section entry follows `depthRules`: High Detail uses `itemsHigh`/`photoCategoriesHigh` when present, else
    Standard items with a "Detail / measurement" box; Fast Entry shows "Items present" chips. Answers are keyed
    by sub-header + question so they survive admin reordering.
  - Report order uses each section's `number` (then natural name order, so Bathroom 2 < Bathroom 10).
- **Inspection types with their own forms (data v1.1).** `Texas` (TREC REI 7-6) and `4 Point Inspection` build
  from `checklistBuilder.phaseTypes`. Sections with `"form"` ignore the checklist depth (always `items`), show the
  `formLabels[form]` badge and no Overall condition row; `"photosOnly"` sections (Texas — Pictures, 4-Point —
  Pictures) open straight on their photo screen, whose primary button marks them done and continues to Summary,
  or to the report when the layout has no Summary (4 Point hides "Review summary" and "Flag a finding").
  Step 1 of the wizard has the JSON `Inspector License #` field (prefilled from Company profile → License #) and
  renders `wizard.typeFields` under the type chips (sponsor + sponsor TREC license # for Texas; insured /
  applicant + application / policy # for 4 Point), stored in the inspection's `fields` by `key`.
- **Admin edits** (Manage checklist) are stored as overrides of the JSON section definitions plus custom
  sections per group; they apply to inspections built afterward. Both Standard and High Detail item lists are
  editable.
- **Report PDF.** `Report/ReportRenderer.swift` renders US-Letter pages with `UIGraphicsPDFRenderer`, following
  `report.html`: branded cover (company logo/company block, client, address, date, agent, inspector, property
  photo, chosen cover color/theme/style), Property Information, Beginning Notes, one data page per completed
  section (sub-section bands, answered lines, overall condition, comments, findings), photo pages (category
  captions, comments, concern/category tags), and the categorized Summary of Findings with taglines. Shared via
  `ShareLink`, previewed with PDFKit. Every cover prints "License #" beside the inspector's name. Page structure
  follows `reportLayouts` (`Report/ReportForms.swift`, matching `report.html?type=texas|4point`):
  - **Texas:** cover titled "Property Inspection Report" → TREC form page (client, date, address, inspector + TREC
    license #, sponsor + TREC license #, promulgated text) → one checklist page per system with I / NI / NP / D
    boxes, fields and "Comments:" → Pictures → Summary. Every page after the cover carries the REI 7-6 footer and
    "Page X of Y" (the PDF is rendered twice to know the total).
  - **4 Point:** cover titled "4-Point Inspection Report" (insured / applicant, application / policy #, address,
    actual year built, date inspected, inspector + license #) → gray-banded form boxes with checkboxes for
    Electrical, HVAC, Plumbing, Roof, additional comments and the certification block → Pictures, 6 per page in
    3 columns. No summary.
- **Fonts.** Archivo, IBM Plex Sans, IBM Plex Mono from `shared/fonts`, registered at launch with
  `CTFontManagerRegisterFontsForURL` (named instances of the variable fonts are addressed by PostScript name).
- **Locale.** Money, numbers and dates use `Locale(identifier: "en_US")` explicitly (`Fmt` in `Theme.swift`),
  so an Indian-region simulator/device still shows `$34.95` and `Sep 28, 2026`. Light appearance is forced.

## Folder map

```
ios/
  VIMS.xcodeproj           file-system-synchronized groups: VIMS/, ../shared/data, ../shared/fonts,
                           ../shared/media (splash video), ../shared/icons (README.md excluded)
  VIMS-Info.plist          partial Info.plist merged into the generated one (white status bar text, launch color)
  VIMS/
    App/        VIMSApp.swift (entry, RootView, routes), AppStore.swift (state + actions), DebugLaunch.swift
    Data/       ChecklistConfig.swift (JSON models + loader), Models.swift (domain), Checklist.swift
                (catalog + builder + answer keys), Repository.swift (Repository protocol, SwiftDataRepository,
                FileStore, image cache), DemoSeed.swift
      Store/    Records.swift (SwiftData models + password hashing), Bootstrap.swift (demo account, new
                company, one-time JSON migration)
    Validation/ Validation.swift (rules, filters, FormErrors), FilteredTextField.swift
    Services/   Services.swift (Auth / Subscription / Sync stubs, connectivity)
    Report/     ReportRenderer.swift (report data + standard PDF pages), ReportForms.swift (Texas TREC + 4-Point pages)
    Theme/      Theme.swift (tokens, fonts, formatting), ProtoIcons.swift (prototype icon renderer),
                Components.swift (chips, buttons, cards, fields…)
    Views/      Shell (header/Screen, video splash, logo badge), Auth, Home (list, side menu, trial splash),
                Inspection (wizard, sections,
                section entry, photos + markup, summary, report), Settings (settings, company, help,
                admin: checklist editor, plans, inspectors, subscribe, billing, feedback)
    Assets.xcassets  AppIcon (from vims-logo.png on white), VimsLogo, AccentColor (#2F5EC9), LaunchBackground
  screenshots/  NN-name.png matching ../screens numbering (31-texas-*, 32-fourpoint-* for the v1.1 types);
                pdf/ holds generated sample reports + page renders (pdf-*, texas-*, fourpoint-*);
                qa-*.png are the QA fix-round checks (splash, validation, icons, menu, sizes, logo, isolation)
```

## Backend stubs — `TODO(backend)`

All in `VIMS/Services/Services.swift`, behind protocols so a Laravel implementation can be swapped in:

| Protocol | Stub | Phase 1 behavior |
|---|---|---|
| `AuthService` | `LocalAuthService` | local User table in SwiftData: sign in checks the email + salted PBKDF2 hash; register creates the user (Create account also creates a company; Join attaches to the company with that code); forgot password only checks the email format |
| `SubscriptionService` | `LocalSubscriptionService` | the form validates the card (Luhn, expiry, CVC, name, ZIP) and the stub simulates Square success; stores only a "Visa ····4242" label, never card data. The card form is a placeholder until Square's card-entry SDK replaces it |
| `SyncService` | `LocalSyncService` | "Sync now" marks pending inspections synced; auto-sync toggle is stored only |

Also pending backend work: sending the report/receipts by email server-side, role enforcement (admin screens are
hidden for non-admins in the UI only), and pulling checklist/plan changes from the web portal (Phase 2).

## Demo seed (easy to remove)

`VIMS/Data/DemoSeed.swift` + `Data/Store/Bootstrap.swift` create, on first launch only, the **demo account**
`jeremy@visionpropertyinspections.com` / `inspect2026` and its company "Vision Property Inspections" (code
VIS-4827, VIMS logo, free look with 10 days left) with four inspections owned by that user — 1428 Ridgeline Dr
(in progress, sample findings, placeholder photos), 82 Canyon Crest #4 (report generated, waiting to sync),
210 Willow Park, Lot 17 (scheduled), 640 Harrison Blvd (yesterday, report sent). The demo data belongs only to
that account; new accounts start empty. To ship without it set `DemoSeed.enabled = false` (no demo account,
empty sign-in fields), or delete `DemoSeed.swift` and the `seedDemoAccount` path in `Bootstrap.swift`. Delete
the app (or launch with `-resetData` in Debug) to reseed.

## Not in Phase 1

Client-payment screens (Collect payment / Payment received, prototype screens 31–32) and every "Collect
payment" button are a confirmed add-on and are not built. The report therefore has no invoice page.
