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

Bundle id `com.vims.app` is a placeholder. First launch seeds demo data (see below); the sign-in screen is
prefilled with the demo owner, and any non-empty email/password signs in.

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
`-trialDaysLeft N`, `-resetData`, `-skipLogin`, `-noSplash`.
None of this is compiled into Release builds. The prototype's yellow review/jump button is intentionally not a
user feature.

## Architecture

```
SwiftUI views ──► AppStore (@Observable, @MainActor)  ──► Repository (FileRepository: JSON + image files)
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
- **Offline-first persistence.** `FileRepository` writes Codable JSON under `Documents/vims/`:
  `app.json` (session, company profile, inspectors, subscription + plans, checklist overrides, settings),
  `inspections/<uuid>.json` (wizard values, generated section list, status, answers, photo refs, findings,
  cover, report info, sync flag), `photos/<inspection>/<photo>.jpg` (+ `-orig.jpg` once marked up),
  `reports/<inspection>.pdf`, `company/` (logo, agreement). Writes are debounced and flushed when the app
  backgrounds. Nothing needs a network.
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
  VIMS.xcodeproj           file-system-synchronized groups: VIMS/, ../shared/data, ../shared/fonts
  VIMS-Info.plist          partial Info.plist merged into the generated one (white status bar text)
  VIMS/
    App/        VIMSApp.swift (entry, RootView, routes), AppStore.swift (state + actions), DebugLaunch.swift
    Data/       ChecklistConfig.swift (JSON models + loader), Models.swift (domain), Checklist.swift
                (catalog + builder + answer keys), Repository.swift (file persistence, image cache), DemoSeed.swift
    Services/   Services.swift (Auth / Subscription / Sync stubs, connectivity)
    Report/     ReportRenderer.swift (report data + standard PDF pages), ReportForms.swift (Texas TREC + 4-Point pages)
    Theme/      Theme.swift (tokens, fonts, formatting, icons), Components.swift (chips, buttons, cards, fields…)
    Views/      Shell (header/Screen), Auth, Home (list + trial splash), Inspection (wizard, sections,
                section entry, photos + markup, summary, report), Settings (settings, company, help,
                admin: checklist editor, plans, inspectors, subscribe, billing, feedback)
    Assets.xcassets  AppIcon (from vims-logo.png on white), VimsLogo, AccentColor (#2F5EC9)
  screenshots/  NN-name.png matching ../screens numbering (31-texas-*, 32-fourpoint-* for the v1.1 types);
                pdf/ holds generated sample reports + page renders (pdf-*, texas-*, fourpoint-*)
```

## Backend stubs — `TODO(backend)`

All in `VIMS/Services/Services.swift`, behind protocols so a Laravel implementation can be swapped in:

| Protocol | Stub | Phase 1 behavior |
|---|---|---|
| `AuthService` | `LocalAuthService` | any non-empty credentials sign in (matches a known inspector by email, else the owner); create account starts a new company on a fresh free look; join validates the code against the local company code |
| `SubscriptionService` | `LocalSubscriptionService` | light card validation, simulated Square success; stores only a "Visa ····4242" label, never card data |
| `SyncService` | `LocalSyncService` | "Sync now" marks pending inspections synced; auto-sync toggle is stored only |

Also pending backend work: sending the report/receipts by email server-side, role enforcement (admin screens are
hidden for non-admins in the UI only), and pulling checklist/plan changes from the web portal (Phase 2).

## Demo seed (easy to remove)

`VIMS/Data/DemoSeed.swift` creates, on first launch only: company "Vision Property Inspections" (code
VIS-4827, owner Jeremy Heath), a free look with 10 days left (urgent splash), and four inspections —
1428 Ridgeline Dr (in progress, prototype statuses, sample findings, placeholder photos), 82 Canyon Crest #4
(report generated, waiting to sync), 210 Willow Park, Lot 17 (scheduled), 640 Harrison Blvd (yesterday,
report sent). To ship without it set `DemoSeed.enabled = false` (clean company, no inspections, empty sign-in
fields), or delete the file and replace `DemoSeed.make(...)` in `AppStore.init` with
`(DemoSeed.emptyState(config:), [])` moved to a new file. Delete the app (or launch with `-resetData` in Debug)
to reseed.

## Not in Phase 1

Client-payment screens (Collect payment / Payment received, prototype screens 31–32) and every "Collect
payment" button are a confirmed add-on and are not built. The report therefore has no invoice page.
