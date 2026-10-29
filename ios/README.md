# VIMS — iOS app (native SwiftUI)

Native **iOS** build of VIMS Phase 1 (Vision Inspection Management Solutions), built screen-for-screen and
behavior-for-behavior against the client-approved prototype (`../index.html`, `../report.html`, `../screens/`).
Swift 5 language mode · SwiftUI + Observation · iOS 17.0+ · iPhone + iPad · Apple frameworks only (no packages).
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

`-screen` accepts: `login signup forgot join home splash wizard editWizard sections section drawer photos markup flag summary
report reportReady settings company instructions manage editSection plans inspectors subscribe subscribed billing
feedback reportBcc eula signupEula deleteAccount phase1 phase2 agreement agreementEditor`. Extras: `-step N` (wizard 1–4), `-depth high|standard|fast`,
`-section NAME`, `-inspection PREFIX|TYPE` (e.g. `Texas`, `"4 Point Inspection"`), `-generate` (with
`-screen reportReady`: regenerate the PDF first), `-group NAME` (Manage checklist), `-overview` (phase screens),
`-trialDaysLeft N`, `-resetData` (wipes the SwiftData store + files and recreates the demo account),
`-skipLogin` (signs in as the demo account), `-signInAs EMAIL`, `-mailSelfTest`, `-noSplash`, `-video` / `-noVideo` (the launch
video is skipped by default whenever `-screen` is given), `-validate` (submits the screen's form once so its
validation errors show), `-eulaVersion V` (pretend eula.json has version V → re-acceptance gate), `-eulaGate`
(show the gate even with `-screen`, which otherwise skips it), `-eulaStatus` (print each account's accepted
version), `-eulaSection N|footer` (viewer scroll), `-prefill EMAIL [-code CODE] [-agree]` (valid Create account /
Join details), `-activeSub` (mark the subscription active), `-profilePhotoSample` (profile photo from an
inspection photo), `-confirmDelete` (with `-screen deleteAccount`: type DELETE and submit), `-prefill EMAIL -password PW -validate`
on `-screen login` (try that sign-in), `-confirm PW` (signup confirm value), `-iaq fill|blank|legacy|overflow` (adds
Indoor Air Quality to the chosen inspection and marks it done: sample readings / no readings / pre-v1.7 answers /
long Report Information so the readings table breaks across pages).
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
  subtitle, contextual Photos / Sections / Home actions right, plus the offline/sync badge when `features.sync` is on —
  off in Phase 1, see "Client round Oct 23–25"). Edge-swipe back is
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
  **aspect-fit** (the whole 9:16 frame incl. the tagline is visible on every phone), tap to skip. The letterbox
  bands above/below are the video's own top/bottom edge colors, sampled from a frame at launch (defaults measured
  from the current file), so the frame blends in; on iPad (wider than 9:16, either orientation) the bands sit left and
  right of the frame, each a top-to-bottom gradient of that edge's colors. It always plays to the end (the safety
  timeout is the video's length + 3 s). With Reduce Motion on it shows the last frame for ~1 s.
- **Company identity vs. personal photo.** `CompanyLogoBadge` shows the company's logo (or initials) only in
  company contexts: Company profile and the PDF cover / page headers. Company profile → Upload/Change logo offers
  Take photo, Choose from library and Remove logo (`PhotoSourceDialog`; with no camera, Take photo opens the
  library). The **account avatar is the user's own profile photo** (`UserAvatar`, initials if none): tap it on
  the Settings account card → Take photo / Choose from library / Remove photo. Stored per user
  (`UserRecord.photoFile` → `users/<id>/profile-….jpg`, 512 px square JPEG) and shown in the Settings account
  card, the side-menu header and the Inspectors rows. TODO(backend): upload to the user's server profile.
- **EULA** (`shared/legal/eula.json`, bundled via the `SharedLegal` synchronized group; `Data/Legal/EULA.swift`,
  `Views/Legal/LegalViews.swift`). The text is rendered verbatim, never hardcoded. Create account and Join a
  company both require the checkbox "I have read and agree to the VIMS End User License Agreement, which governs
  the free trial and subscription." (the agreement name opens the viewer); submitting without it shows an inline
  error. The accepted `version` + `acceptedAt` are stored on the user (`UserRecord.eulaVersion/eulaAcceptedAt`;
  TODO(backend): send to the server). Whenever the signed-in user's accepted version differs from eula.json
  (a revised file, or an account from before this feature) a full-screen gate ("Updated license agreement" /
  "License agreement") shows the text with **I agree** and **Sign out**. Viewer: Settings → Legal → End User
  License Agreement ("Revised <revised>") — title, revised date, intro, numbered headings in brand-deep, all 14
  sections, footer.
- **Cancel subscription** (Plan & billing, active subscription, owner/admin only; the trial shows no button):
  (since 0.23.0 monthly only; a yearly plan ends on cancellation with a pro-rated refund, see the 0.23.0 notes)
  red "Cancel subscription" → inline confirm card (active until the next billing date, no refunds or prorated
  charges, download within 30 days) with Keep subscription / **Yes, cancel** → status "Cancelled · active until
  <date>", explanatory card and **Undo cancellation**. Stored as `SubscriptionState.cancelledAt`.
  TODO(backend): Square subscription cancel / resume (`SubscriptionService.cancelSubscription/resumeSubscription`).
- **Delete account** (App Store 5.1.1(v)): Settings → Account → Delete account (red) → a screen listing what is
  deleted (the account, the user's inspections with photos and reports on this device; for a sole owner also the
  company, with the subscription cancelled) and a "Type DELETE to confirm" field. An owner with other users on the
  company is blocked with "Make another admin the owner first" (Inspectors now has **Make owner** for admins,
  visible to the owner). A non-owner is removed from the company. Ends on Sign in. TODO(backend): server
  deletion request (within 10 working days per the EULA).
- **Sign out** always asks "Do you really want to sign out?" (Cancel / Sign out) — Settings, side menu and the
  EULA gate.
- **Form labels & required fields.** Every field label uses `FieldLabel` (IBM Plex Sans 13 semibold, ink-2); the
  uppercase mono section labels are unchanged. Fields whose validation rule is `.req` pass `required: true` and
  show a red " *" (wizard fields derive it from `WizardRules`); placeholder-only admin fields show the "*" inside
  the box. Create account, wizard step 1 and Subscribe show a "* Required" hint.
- **Sign-in errors** land on the right field: unknown email → Email ("No account found…"), wrong password →
  Password, bad format → that field; each clears when edited. Confirm password only checks "Passwords don't match".
- The app/data version line in Settings is shown in DEBUG builds only.
- **Status colors** (one palette, always with a label): inspections Done green / In progress blue / Queued amber /
  Scheduled gray; checklist sections Done green / In progress blue / Not started gray (pills in Sections
  overview and the drawer); sync badge Synced green / queued amber / Offline gray; subscription Active green /
  Trial and Cancelled amber.
- **Inspection date.** The wizard's date picker starts at today; editing an existing inspection allows its saved
  (possibly past) date.
- **VIMS platform-owner settings** (data v1.2). The feedback email and the **Report quality copy (BCC)**
  (`support.reportBcc` default) are platform-level, not per company: stored once in SwiftData
  (`PlatformRecord` → `PlatformSettings`) and editable only by the platform owner. `Session.isPlatformOwner` is
  true only when the signed-in email is in the shared `support.platformOwners` list (data v1.5; see below —
  TODO(backend): the server sends this flag/role). Only those accounts see Settings → "Master admin" (was "VIMS owner" before Oct 28; Report quality copy (BCC) with subtitle
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
- **Home side menu** (`Views/Home/SideMenu.swift`): hamburger opens a left drawer with the user's profile photo, user,
  email and company; Inspections, New inspection, Settings, Company profile, How VIMS works, Help & feedback;
  master-admin-only Plans & pricing, Report quality copy (BCC), Feedback & support (client Oct 28); company-admin-only
  Manage checklist, Inspectors; Sign out. Scrim tap or swipe left closes it.
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
    Standard items with a "Detail / measurement" box; Fast Entry shows "Items reviewed" chips. Answers are keyed
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

## iPad

Universal app (`TARGETED_DEVICE_FAMILY = 1,2`). iPhone stays portrait-only; iPad supports all four orientations
(`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`), so it qualifies for multitasking / windowed apps. The iPhone
layout is unchanged; iPad-only behavior lives in `Views/Shell/Adaptive.swift`:

- **Readable column.** In regular width, `Screen`'s scrolling content (and the wizard, sign-in, EULA gate, markup tool
  panel) is a centered column, 740 pt max (560 pt for sign-in / create account / join / reset password). Headers and
  bars stay full width. The Photos screen uses 1100 pt and shows each photo slot as a card, 2–3 across.
- **Landscape (wide windows, Oct 12).** When the window is at least 1100 pt wide (11"/13" and mini in landscape) the
  column grows to 80 % of the window, capped at 1080 pt (forms 680, documents 900; `PadLayout.columnWidth`, window
  width from `measuresWindowWidth()` at the root, `WideLayout` to ask), and screens use two columns where it helps:
  sign-in is a blue brand panel beside the form; the EULA gate keeps the agreement at a reading width with I agree /
  Sign out in a side panel; Home lists inspections beside the counts and actions; the wizard puts fields two per row
  (Client name | phone, email | address, State | agent name, agent email | license #, Date | Time, the two notes) and
  step 2's numbers four per row; Sections shows the groups beside progress and the report buttons; checklist lines
  sit two per row (each row as tall as its taller card; header bands and air readings stay full width); Summary shows
  the three categories side by side; Generate report puts the cover beside the contents; Settings and Inspectors
  split into two columns. Portrait (≤ 1032 pt) and iPhone are unchanged.
- **Documents full screen.** Report preview, the generated PDF and state documents open as a full-screen cover
  (`documentCover`) instead of a form sheet; pages fit the width (re-fitted on rotation) and pinch-zoom to 5×.
- **Pickers.** The quick-comment list (photo markup, flag a finding) is a popover hanging off its field on iPad and a
  titled sheet on iPhone; both show every comment in full, wrapped, with a checkmark on the current one. The State
  picker is a form-sized sheet on iPad (Cancel, focused search field, list — 6 rows above the landscape keyboard on
  13", 8+ in portrait), the full-height sheet on iPhone. Confirmation dialogs (Add a photo,
  delete inspection, profile photo, remove section, use VIMS agreement) are attached to their control so the iPad
  popover points at it. Flag a finding is one full-height form sheet; the photo library picker is page-sized.
- **Share sheets.** Every `UIActivityViewController` goes through `ShareSheet.present(_:from:)` with a
  `PopoverAnchor` on the tapped button (report email fallback, state-document send fallback, agreement download), so
  it never presents without a popover source (which crashes on iPad). Mail composer and `ShareLink` are system-managed.
- **Camera.** No camera (iPad simulator) → Add opens the photo library; the profile photo / logo dialog says so.
- DEBUG review flags: `-openPicker` (wizard), `-openComment` (markup), `-openPreview` / `-openShare` (reportReady,
  agreement). `-landscape` / `-portrait` request a rotation, but iPadOS 26's windowed mode refuses programmatic
  rotation. Use the **VIMSUITests** target instead (below), which rotates the device for real.
  Screenshots: `screenshots/ipad/{mini,13in}-*.png`, `screenshots/oct12-ipad-*.png`.
- **Review screenshots in any orientation** (`VIMSUITests/ReviewScreenshots.swift`, shared scheme `VIMS`): a UI test
  that reads a JSON plan, launches the app with DEBUG arguments per shot, sets `XCUIDevice.shared.orientation`,
  optionally taps / types, and writes `<out>/<name>.png` (also attached to the result):

  ```bash
  # plan.json: {"out": "/abs/dir", "shots": [{"name": "13in-land-home", "orientation": "landscape",
  #             "args": ["-skipLogin", "-screen", "home", "-noSplash"], "wait": 2.5, "steps": [{"tapAt": [0.5, 0.3]}]}]}
  xcodebuild -project VIMS.xcodeproj -scheme VIMS -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
    -derivedDataPath build/DerivedData build-for-testing
  TEST_RUNNER_VIMS_SHOT_PLAN=/abs/plan.json xcodebuild -project VIMS.xcodeproj -scheme VIMS \
    -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build/DerivedData \
    test-without-building -only-testing:VIMSUITests/ReviewScreenshots/testPlan
  ```

  Without the variable the test is skipped. Steps: `tap` (label / identifier), `tapAt` ([x, y] fractions), `type`,
  `swipeUp` / `swipeDown`, `wait`, `shot`.

## Inspection agreement: download + company edit

- **Download** (every user): the share button in the viewer's header renders exactly what the viewer shows (title, form
  lines, body, the disclosures shown, closing; `{companyName}` filled — or the company's edited text) into a paginated
  US Letter PDF, `Inspection-Agreement-<Company-Name>.pdf`, footer "<Company> · Inspection Agreement · Page x of n"
  (`Report/AgreementPDF.swift`, content model `Data/Legal/AgreementContent.swift`), and opens the share sheet
  ("Share agreement": Save to Files, Mail, AirDrop, Print). An uploaded agreement keeps its Quick Look share.
- **Edit** — *replaced by the block editor on Oct 13, see "QA round Oct 13" below; the original plain-text design follows.*
  (company admins, same permission as upload): the card's **Edit** opens "Edit agreement"
  (`AgreementEditorView`, route `.agreementEditor`): the agreement's **form block is locked** (Oct 12) — shown read-only
  above the editor, boxed like the viewer ("Form fields · Locked") — and a plain-text editor prefilled with the VIMS
  agreement's wording (title, blank-line paragraphs, "• " bullets, the disclosures heading then "State: text" per state, closing; company
  name filled) or the company's earlier edit. Save validates (not blank, ≤ 100,000 characters, counter shown; "No
  changes to save" when unchanged); back / Cancel with changes asks "Discard changes?". Stored on the company as
  `CompanyProfile.agreementText` + `agreementEditedAt` (SwiftData, with the rest of the profile; TODO(backend) sync).
  The VIMS agreement itself never changes.
- **Which agreement is in use** (`AppStore.agreementInUse`): saving an edit replaces an uploaded file; uploading clears
  the edit; **Use VIMS agreement** clears both (asks "Use the VIMS agreement?" first when an edit would be deleted).
  Card: "VIMS agreement · All 50 states · in use · View · Edit" / "Edited VIMS agreement · Your edited version · in
  use · View · Edit · Use VIMS agreement" / uploaded as before. Non-admins see View only (no Edit / Upload).
- **Viewer** with an edited version: "Your company's edited version of the VIMS agreement.", then the text (a paragraph
  per blank-line block, "• " lines as bullets, a short first line as the title). From the wizard it shows the full
  edited text (it can't be filtered by state), and the wizard line reads "View (your company's edited version)".
- DEBUG: `-screen agreementEditor [-validate]`, `-editedAgreement`, `-legacyEditedAgreement`, `-agreementStatus`,
  `-agreementScroll card` (Company profile).
  Screenshots: `screenshots/32-*.png` – `36-*.png`.

## Folder map

```
ios/
  VIMS.xcodeproj           file-system-synchronized groups: VIMS/, ../shared/data, ../shared/fonts,
                           ../shared/media (splash video), ../shared/icons (README.md excluded),
                           ../shared/legal, ../shared/covers (report cover theme artwork)
  VIMS-Info.plist          partial Info.plist merged into the generated one (white status bar text, launch color)
  VIMS/
    App/        VIMSApp.swift (entry, RootView, routes), AppStore.swift (state + actions), DebugLaunch.swift
    Data/       ChecklistConfig.swift (JSON models + loader), Models.swift (domain), Checklist.swift
                (catalog + builder + answer keys), Repository.swift (Repository protocol, SwiftDataRepository,
                FileStore, image cache), DemoSeed.swift
      Store/    Records.swift (SwiftData models + password hashing), Bootstrap.swift (demo account, new
                company, one-time JSON migration), DeviceTrial.swift (one free trial per device, Keychain)
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
| `SubscriptionService` | `LocalSubscriptionService` | the form validates the card (Luhn, expiry, CVC, name, ZIP) and the stub simulates Square success; stores only a "Visa ····4242" label, never card data. The card form is a placeholder until Square's card-entry SDK replaces it; cancel / undo cancellation are stubbed too |
| `SyncService` | `LocalSyncService` | Phase 2 only: with `features.sync` false (data v1.10) it never runs and no sync UI shows. With it on, "Sync now" marks pending inspections synced; auto-sync toggle is stored only |

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

## State rules, state documents, CC inspector (shared data v1.3)

- **State field:** wizard step 1 has a required **State** (from `shared/data/vims-checklists.json` → `states`) right after Inspection address. It is saved on the inspection and shown with the address.
- **`stateRules`** (same JSON; behavior described in its `_about`):
  - **TX:** auto-selects the **Texas** (TREC) inspection type. If the state changes away while the type is still the automatic one, it reverts to Real Estate Sale.
  - **OK:** the `summaryDisclosure` is a permanent entry at the top of the Summary screen and page 1 of the PDF summary.
  - **OR:** the `coverNotice` prints on the PDF cover under the ownership notice, in every layout.
  - **OR / LA `docs`:** the state documents (`shared/legal/state/*.pdf`) are listed in step 1 with **View** and **Send to client**. A required checkbox, "Provided to the client with the inspection agreement," blocks **Next**, and the acknowledgment is stored with a timestamp.
  - **Adding a state:** edit `stateRules` in the shared JSON. No code changes are needed.
- **Emailed reports** go To the client and agent, with **CC to the signed-in inspector** (archive copy) and BCC to the platform report-quality address when that setting is on.
- **EULA** `version` 2026-10-03 adds clause 3.4 (Licensing). Users who accepted an older version see the re-accept gate once.

## Inspection agreement + send-to-agent (shared data v1.4)

- **VIMS default agreement** (`shared/legal/inspection-agreement.json`, bundled by the `SharedLegal` group; `Data/Legal/InspectionAgreement.swift`). Rendered verbatim; `{companyName}` is filled with the signed-in company's name. No in-app e-signature in Phase 1.
- **Company profile → Inspection agreement:** "VIMS agreement · All 50 states · in use · View" with **Upload your own** (file importer, PDF/Word). After an upload the card shows the file name, "Your agreement · in use · **Use VIMS agreement**" (reverts and deletes the stored file) and **Replace**. Stored per company (`CompanyProfile.agreementFile/agreementName`, `companies/<id>/`).
- **Viewer** (`Views/Legal/AgreementViews.swift`, route `.agreement(state:)`, title "Inspection agreement"): title, header form lines in a boxed mono block, body paragraphs/bullets, "State Specific required disclosures." and closing. From Company profile it lists all 20 states; from the wizard only the inspection's state, with "Showing <State> only. The full agreement lists 20 states." or "No additional disclosures for <State>." When the company uses its own file, a note says so (VIMS text shown for reference) with **Open your agreement** (Quick Look).
- **Wizard step 1:** "Inspection agreement: View (shows the selected state's section)" under the State notes, and **Send the report to the real estate agent** under Real estate agent email (on by default; reset to `stateRules[state].agentCopyDefault` when the state changes — off for NH, whose note shows under it). Stored as `Inspection.sendToAgent` (nil on older inspections = on).
- **Emailed reports:** with send-to-agent off, To = client only (CC inspector and platform BCC unchanged); the Report ready note says "client only".
- DEBUG: `-screen agreement [-agreementState XX] [-agreementScroll disclosures]`, `-ownAgreement NAME` (bundled NAME.pdf through the same upload path), `-useVimsAgreement`, `-agreementStatus`, `-wizScroll sendToAgent|agreementLine`; `-mailSelfTest` also prints the NH/UT recipient check. Screenshots: `screenshots/qa-12x-*.png`.

## Client round Oct 9 (shared data v1.5)

- **VIMS owners** — `PlatformOwner` (Data/Models.swift) reads `support.platformOwners` (currently
  `masteradmin@vimsinspect.com` and `admin@vimsinspect.com`, data v1.9.2), trimmed and case-insensitive; several addresses are allowed so the client always
  has two system admins. No password is stored or seeded: the owner creates an account (or signs in) with that email
  and their own password, and Settings then shows "VIMS owner" (Report quality copy, Feedback & support). The demo
  account jeremy@visionpropertyinspections.com is still the demo company's owner/admin but no longer a platform owner.
  TODO(backend): the server owns the list.
- **Concerns dialog** — on a Standard / High Detail checklist, newly selecting an item's "Concerns" / "Concern" opens
  the Flag-a-finding sheet titled "Concern: <item>" (same categories, quick comment, validation and iPad sizing).
  Add finding saves "<item>: <description>" for the section (`Finding.item` keeps the item), so it shows in Summary and
  the PDF; Cancel just closes (the option stays selected); deselecting never deletes a finding. Hidden, like the
  flag button, on layouts without a Summary (4 Point).
- **Wizard Return / Next** — step text fields chain with Next / Done. Return on Inspection address drops its keyboard
  and opens the State picker with its search field focused (iPhone sheet / iPad popover); typing a name or a 2-letter
  code ranks that state first and Return picks it; a pick moves on to the agent name. Required State + state rules
  unchanged. Typing the client email never touches the address (each field has its own binding).
- **Report cover** — fixed a stale binding: picking a theme category wrote the category, then its first image from an
  old snapshot, reverting the category. The picker now writes one value and reads the live inspection; the PDF cover
  and the saved inspection use the chosen color / theme / style.
- **Wording** — Fast Entry and the report row say "Items reviewed" (stored as `SectionAnswers.present`).
- **Data v1.5** (no code change): Water Feature multi-select (Landscaping / Condo High Detail), Driveway / Parking Lot
  "Slope" + "Incline / Decline" + "Cracked / Buckling", Bushes order, Water Heater "Pilot Light".
- Screenshots: `screenshots/oct9-*`.

### Report covers from the client's designs (shared data v1.6)

- **PDF cover** (`Writer.cover()` in `Report/ReportRenderer.swift`) follows `covers.layout` (inches on US Letter) and
  `report.html` `coverPage()`: page box with **Framed** (light fill, 0.75pt black border, soft `deep` glow),
  **Shaded** (light 0–18% → mid 56% → deep 83–100%, top to bottom) or **Solid** fill; logo top-left; company block
  top-right; title (Inspection Report / Property Inspection Report / 4-Point Inspection Report); bold Times New Roman
  labels with values on underlines (4-Point keeps its own rows, with slightly tighter gaps so they end above the
  photo); the property photo aspect-filled in a 1.25pt box, or an empty box with "Picture of Property."; the
  ownership footer (+ the Oregon `coverNotice`). The theme artwork (`covers.themeArt`, `shared/covers/*.webp`, a
  new synchronized group `SharedCovers`) is drawn at its rect over the page and photo, clipped to the page box.
  The footer wraps beside the art's **visible pixels** in the footer band (the larger free side), and its text is
  drawn in front so wide art (Fall) never hides it, as on the client's Fall and 4th of July covers.
- **Cover picker**: the preview swatch shows the chosen artwork in its corner (bottom-left for left-hand art such as
  4th of July), like the prototype's `.coverprev`; Theme → Image options show a small thumbnail of each artwork.
- DEBUG: `-cover "Color|Category|Option|Style"` sets the inspection's cover (e.g. with `-screen reportReady -generate`).
- Screenshots: `screenshots/oct9-cover-*.png` (client Word cover / prototype / iOS PDF page 1 side by side;
  picker; iPad preview). Summer, Christmas and Spring artwork still carry stock-site watermarks (`themeArtNote`).

## Deleting inspections (client feedback Oct 11)

A tester couldn't find a way to delete current or old inspections to free device storage (only a hidden long-press
menu existed). Now (`Views/Inspection/DeleteInspection.swift`):

- **Home**: every inspection row has a visible **⋯** button (44 pt, VoiceOver "More options for <address>") with
  **Save or share report** (only when the report PDF exists → share sheet with "Inspection Report - <address>.pdf":
  Save to Files, Mail, AirDrop…) and **Delete inspection**. Long-press on the row shows the same items.
- **Inside an inspection**: a red ghost **Delete inspection** button at the bottom of the Sections overview (under
  Generate report) and on Report ready (under Back to inspections). Deleting from inside returns to Home first.
- **One confirmation everywhere** (centered alert since team QA Oct 22): "Delete this inspection?" — "This removes the
  checklist, photos and report for <address> from this device. Some states require keeping reports for 3–5 years."
  **Save report first** (only with a report; opens the share sheet and keeps the inspection), **Delete**
  (destructive), **Cancel**. Toast "Inspection deleted".
- `AppStore.deleteInspection` removes the record, the photos folder, the report PDF and the share-sheet copy, and
  cancels any pending debounced save (which could otherwise write the record back). Only the signed-in owner's
  inspections are listed and the repository re-checks the owner. TODO(backend): once the VIMS server is live,
  reports are retained server-side (reports 3 years, agreements 5 years), so deleting only frees device space.
- Screenshots: `screenshots/oct11-delete-*.png` (iPhone 17 01–10, 19; iPad mini 11–18).

## Indoor Air Quality readings (client update Oct 12, shared data v1.7)

- **Data**: new item type `airReading` (`ItemDef` gains `code`, `unit`, `reference`, `action`; `ItemKind.airReading`)
  and the section-level `airQuality` block (`AirQualityDef`: legend, ratings, column heads, action prefix).
- **Answer**: the optional "Level measured" lives in `SectionAnswers.text[key]`, the 1–6 rating in `choices[key]`
  (no schema change, older saves decode as before). Pre-v1.7 IAQ answers (single choice "1 Good" / "2"… under the
  old question keys) are moved onto the matching reading's rating by pollutant code when the section is opened or
  the report is built (`SectionAnswers.migratingLegacyAirRatings`); anything that doesn't map is left alone.
- **Entry** (`AirReadingInput` in `SectionEntryView.swift`): question, decimal-keypad "Level (unit)" field with the
  unit pill (optional; validated on Save as a number, 0 or more — new `FieldKind.reading`), "Air quality rating"
  with six 44 pt rating buttons (tap again to deselect; the caption shows e.g. "· 3 Mild"), then the reference
  and "Corrective action if needed — …" in small secondary text. iPhone stacks level over rating; iPad puts them
  side by side. Fast Entry's "Items reviewed" chips list the readings as before. Manage checklist labels these
  items "Air reading".
- **PDF** (`AirQualityTable` + `Writer.airQuality` in `ReportRenderer.swift`, report.html page 7): legend top-right,
  "Level Measured" / "Air Quality Rating" heads, one row per reading — "**CODE** – name" | level + unit on an
  underline (blank underline when not measured) | bold rating (blank when none) — with the reference (left) and
  corrective action (right) under it. Every reading prints, filled or not, like the client's form. High Detail's
  Report Information lines print above the table. Rows never split; after a page break the column heads repeat.
  Overall condition, comments, findings and the photo pages follow as usual. Fast Entry keeps its "Items reviewed" line.
- Screenshots: `screenshots/oct12-iaq-*.png` (1–2 iPhone entry, 3 Standard PDF page, 4 High Detail PDF page,
  5 table across a page break, 6 PDF from migrated pre-v1.7 answers, 7 migrated entry + Fast Entry,
  8 iPad High Detail entry, 9 level validation).

## QA round Oct 12 (iPad Pro 13" + iPhone 17)

1. **iPad landscape.** Wide windows get a wider column and two-column layouts (see iPad → Landscape). Portrait,
   iPad mini portrait and iPhone are unchanged. Verified with the new UI-test screenshot harness in real landscape
   on the 13" and the mini.
2. **State picker on iPad** is a form-sized sheet (`presentationSizing(.form)` on iOS 18+, the default iPad form
   sheet on iOS 17) with its own Cancel / title bar, focused search field and the list; with the keyboard up the
   13" shows the search field and 6 states in landscape, 8+ in portrait. iPhone unchanged.
3. **Quick comments show in full.** `QuickCommentMenu` (photo markup "Comment", Flag a finding / Concern "Quick
   comment") opens a list of all eight comments, wrapped, checkmark on the current one: a titled sheet on iPhone
   (the system menu truncated "Item to monitor, if condition deteriorates contact a qualified profe…"), the popover
   on iPad. Picking fills the field as before; the field itself now wraps a long pick (up to 3 lines).
4. **Date / time checklist items** (shared v1.7.1: IAQ High Detail Date → `date`, Time → `time`; Termite "Date of
   inspection" and Wind Mitigation "Inspection date" → `date`). `ItemKind.date/.time` render `OptionalDateField`:
   the value in the same gray pill as the wizard's Date / Time; one tap anywhere on the field opens the calendar
   (or the time wheels) in a popover anchored to the field — no keyboard — and fills today / now like the wizard;
   × clears. Stored like the wizard ("yyyy-MM-dd", "HH:mm"); the PDF prints "October 12, 2026" / "10:15 AM".
   Answers typed when these were text fields ("October 12, 2026", "10/12/26", "10:15 AM"…) are still read
   (`Fmt.answerDate` / `answerTime`), and anything unreadable prints as typed.
5. **Inspection agreement form block locked.** "Edit agreement" shows the agreement's form lines (`formLines`:
   Clients Name ____, Phone #, …, the ☐ lines, fees) read-only above the editor; only the wording (title, body, state
   disclosures, closing) is editable. `AgreementContent.edited(_:company:form:)` always puts the locked block right
   after the title, so the viewer and the PDF show it unchanged. Text saved before the lock that still holds form
   lines (possibly with field names deleted) is cleaned on display, in the PDF and in the editor
   (`AgreementContent.strippingFormLines`), so the block never shows twice. No fill-in or tappable boxes (e-sign
   add-on, deferred).
6. **Updated splash video** (6.6 s, 720×1280, 50 fps): plays to its end (verified: ended at 6.58 of 6.58 s on
   iPhone 17 and iPad Pro 13"; the old fixed 8 s safety timer was replaced by the video's length + 3 s, since the
   first frame can take ~1 s on a cold launch), fits, and the edge bands blend: above/below on iPhone, left/right
   (gradient) on iPad in both orientations. Default edge colors re-measured from the new file.

Screenshots: `screenshots/oct12-*.png` — `ipad-01…18` 13" (landscape 01–13, portrait 14–18), `ipad-19…26` iPad mini
(landscape 19–22, portrait 23–26), `state-01…04`, `comment-01…04`, `date-01…05` (05 = the IAQ PDF page),
`agreement-01…04` (04 = the PDF from a pre-lock edit, form block once), `iphone-01…04` (unchanged iPhone screens),
`splash-01…04`.

## QA round Oct 13 (team QA, iPhone 17)

- **Numbers** (`Validation.swift`, docs "Number limits"): one parser, `Validator.number`, reads every number ignoring grouping
  commas, spaces and a leading `$` (valuation, sq ft, lot size, `num` items, IAQ levels, plan prices, the PDF's Property
  Information). Root cause of "450,000 → Enter a number greater than 0": the demo seed stores `"450,000"` and the check
  used `Double(v)`. `FieldKind.number(NumberLimits)` replaces `.decimal` / `.reading`: sq ft 1 – 100,000 and valuation
  1 – 100,000,000 (both may show commas), lot size 0.01 – 10,000, checklist `num` items 0 – 99,999 (counts — "Number of …"
  room counts only: kitchens / bathrooms / half baths / bedrooms / stories / hallways / rooms / living / family / dining / garages,
  Android's regex — 0 – 20), IAQ level 0 – 99,999. Typing filters to digits + one `.`; a value above the max
  shows "Enter a number up to <max>" immediately (`FormErrors.liveLimit`, no submit needed). Steppers use
  `StepperLimits`: room counts and unit mix 0 – 20, Inspector seats 1 – 50 and never below the current team (people with an
  email; − only removes open seats added with +); − / + are disabled (not just dimmed) at the
  ends. Text items such as "System number" stay free text.
- **No auto-selection** (`TextSelection` in `FilteredTextField.swift`, installed at launch): when any UITextField /
  UITextView (incl. SwiftUI TextField / TextEditor) begins editing with its whole text selected, the selection collapses
  to a caret at the end; a tap keeps its tap point. The iOS code had no select-all of its own; this guards the
  programmatic-focus / Return-chain paths app-wide.
- **Edit agreement = block editor** (`AgreementEditorView`, `AgreementContent` + `EditedAgreement`): the agreement is listed
  as the viewer's blocks (title, form, paragraphs, bullets, disclosures heading, each state's disclosure, closing). The
  form block and every block containing `___` blanks or ☐ boxes ("THIS AGREEMENT is entered into on ____ …", agent / client
  name and signature lines, "NO Report to Real Estate Agent ☐") are **Locked** (read-only, tag, no delete). Every other
  block is a multi-line text box with **+** (add a paragraph after it; after the title it lands below the form) and trash
  (asks "Delete this paragraph?"; the title has none — it can't be deleted); **Add paragraph** at the end. Save refuses
  blank blocks (each highlighted: "Enter a title" / "Enter text or delete this block"), checks ≤ 100,000 characters, and
  stores JSON
  `{"format":"vims-agreement-blocks","v":1,"blocks":[{"t":"title|p|li|h|state","text":…,"state":…,"lead":…,"locked":…}]}` (Android's schema) in
  `CompanyProfile.agreementText` (the form block isn't stored: its lines come from the VIMS agreement, always under the title). Plain-text
  edits saved by earlier builds still load (parsed into blocks, old form lines dropped). Viewer and PDF render the stored
  blocks; Use VIMS agreement still resets. No fill-in / tappable checkboxes (deferred e-sign add-on).
- **Manage checklist:** the item trash asks "Delete this item?" / "“<question>” and its options will be removed from new
  inspections." (Delete / Cancel), anchored to the button on iPad. Removing a custom section already asked.
- **How VIMS works:** "Need a hand? Contact VIMS support" and the support address as a link — the platform owner's Feedback &
  support email (`PlatformSettings.feedbackEmail`, default `support.feedbackEmail` = support@vimsinspect.com since data
  v1.9.2; blank falls back to that default). Mail composer when Mail is set up, else `mailto:`, else the address is copied with a
  toast; long-press → Copy email address.
- **Plans & pricing:** trash on each plan card → "Delete this plan?" (anchored on iPad). The last plan can't be deleted;
  a company on the deleted plan moves to the first remaining one (`AppStore.deletePlan`, stored with the subscription
  like a price edit). "Additional inspector" is a rate setting and has no delete.
- **Billing ZIP / postal code:** letters, digits, space, `-`, uppercased, max 10; valid at 3 – 10 characters (84015,
  84015-1234, K1A 0B1, SW1A 1AA); default keyboard.
- **Ownership:** only the current owner can transfer it — "Make owner" on every other teammate with an email (incl. the
  previous owner), after "Make <name> the owner? You'll stay an admin. Only the new owner can transfer ownership again."
  The new owner becomes an admin. Your own row has no Make admin / Remove / Make owner. A non-owner admin sees "Only the owner can transfer ownership." on the owner's row and
  has no way to take ownership.
- DEBUG: `-screen editWizard [-step N]` (the wizard editing an existing inspection), `-teamAccount EMAIL` (a second
  account, Sam Rivera / inspect2026, on the demo company; then `-signInAs EMAIL`), `-agreementScroll first|last|N` in the
  agreement editor, `-editedAgreement` now saves the block format. UI-test plans gained `tapField` (a text field by label
  or placeholder). Screenshots: `screenshots/oct13-*.png` (iPhone 17; `oct13-ipad-*` on iPad Pro 13", portrait).

## Client round Oct 16 (finding line, photo markup, report scroll bar, cover footer)

- **One finding line everywhere:** the Summary screen and the PDF's Summary of Findings both read
  **Section** — custom comment — quick comment (empty parts dropped, no dangling dashes); the PDF keeps its per-category
  numbering, the app its colored dots. The per-section "Findings" block in the PDF uses the same "custom — quick" wording.
  `Finding` gained optional `custom` / `quick` (stored apart from now on, plus the combined `text`); findings saved
  before Oct 16 have neither and show their stored `text` unchanged (`Finding.lineParts` / `detail`). TODO(backend): sync both fields.
- **Flag a finding / Concern / photo flag** (`FindingSheet`, `AppStore.addFinding(custom:quick:…)`): picking a quick
  comment no longer overwrites the Description; the dropdown keeps its own value and starts with "No quick comment".
  The Description is required only when no quick comment is picked ("Describe the finding or pick a quick comment.").
  Concern findings: custom = "<item>: <description>", or "<item>" alone (so "**Section** — <item> — <quick>"). From a
  photo, the sheet is prefilled with the photo's quick and custom comments (a saved "quick — custom" photo comment is
  split back into the two fields; a description that repeats the quick comment is not stored twice).
- **Photo markup:** no "Comment" label; the quick-comment dropdown takes the full row ("Draw" / "Stamp" labels stay).
- **Report preview scroll bar** (`Views/Inspection/PDFScrubber.swift`, used by both the Generate-report preview and
  the generated-PDF preview): a draggable blue thumb on the right edge, below the top bar; only the thumb takes
  touches (normal scrolling everywhere else), a "Page X of N" bubble shows while dragging or scrolling and fades 1.2 s
  after, the thumb dims when idle. Follows pinch-zoom, rotation and iPad window resizes; VoiceOver: adjustable, one
  page per swipe.
- **Cover footer:** "This inspection report is the property of <Company name>." with the name underlined; the name is
  the signed-in company's Company profile name (`state.company.name` → `ReportData.companyName`, `{companyName}` in the
  JSON template — nothing hard-coded). Still wraps beside the theme art.
- DEBUG: `-sampleFindings` (the client's Oct 16 examples through `addFinding`, plus one pre-Oct 16 finding; prints
  FINDINGTEST lines), `-photoComment TEXT` (markup / flag prefill), `-companyName NAME` (rename the company),
  `-scrubTo F` (with `-openPreview`: scroll to fraction F and hold the dragged look).
- Screenshots: `screenshots/oct16-*.png` — 01 Summary screen vs PDF summary page, 02–05 markup / flag sheet, 06–08
  iPhone scroll bar (held, dragged, idle), 09–10 iPad Pro 13" portrait / landscape, 11–12 cover footer (demo company /
  renamed company).

## QA list Oct 14 + client round Oct 17 (shared data v1.8 / v1.9, built Oct 21)

**QA (team, Oct 14)**

1. **No auto-selection on focus.** The app's single-line field is now `CaretTextField`: a select-all UIKit issues while giving it
   focus (hardware-keyboard Tab, Return-chain / programmatic focus) becomes a caret at the end; a Select All the user picks later
   still works. The app-wide `TextSelection` guard (SwiftUI `TextField` / `TextEditor`, every UITextField / UITextView) now
   re-checks 0.12 s and 0.3 s after focus too, since UIKit can apply the selection after the begin-editing callback.
2. **Join a company → Company code** accepts the full code: typing the 3rd letter inserts the "-" (backspace removes it),
   letters uppercase, digits after the dash (max 4), paste "vis-4827" / "VIS4827" works → `VIS-4827`.
3. **Temperature (°F)**: optional leading "-" and one decimal point (one digit after it) — `72.5`, `-4.5`; −60 … 140.
4. **Make owner / Make admin**: the signed-in user's inspector row wasn't recognized (the demo company's rows were seeded with
   their own ids, so `isCompanyOwner` was false and Make owner never showed / did nothing). `AppStore.loadSession` now gives the
   user's row (matched by email) the user's id once and saves it; owner detection also falls back to the email. Make owner
   (after its confirmation) and Make admin write the team in one change and save immediately (`saveAppStateNow`); both survive
   a relaunch. Only admins can toggle admin / remove; nobody can change the owner's row or their own.
5. **Company profile is read-only for non-admins**: a note ("Only your company admin can edit…"), the logo, the details as text,
   the agreement card with View / Open only — no Upload logo, fields, Save or agreement edit. The store refuses logo /
   agreement / profile writes from non-admins too (TODO(backend): enforce on the server).
6. **Subscription remembers the card**: only a display reference is stored — `SubscriptionState.cardOnFile`
   (`CardOnFile`: brand, last 4, expiry month / year, `squareCardID` placeholder — TODO(backend): Square Cards API customer card
   id). The card number and CVC are never stored. On update: "Use this card — Visa •••• 4242 (exp 08/28)" (default) or "Use a
   different card" (shows the card form). An expired card isn't offered. Plan & billing → Payment shows the same line.
7. **Remove inspector asks first**: "Remove <name>?" — what they lose — Remove / Cancel.
8. **Uploaded agreement opens**: the agreement card had no link for an uploaded file. It now shows **Open** (everyone; Quick
   Look for PDF, Word and images) beside Use VIMS agreement (admins); upload also accepts images.
9. **Plan descriptions are multi-line**: each plan card has a wrapping description box (saved with Save), the add-plan form too
   (200 characters, line breaks kept); the Subscription screen wraps them.
10. (Android only.)
11. **Trial "days left" dialog** scrolls inside the screen when it doesn't fit (large text, small windows) so its buttons are
    never cut off; it stays centered when it fits.

**Client (Jeremy, Oct 17)**

1. **Photo source**: the Add tile opens a menu — **Photo Library**, **Camera**, **Files / Drive** (document picker: iCloud
   Drive, Google Drive and other providers; images only, read with a coordinated security-scoped read), with icons like
   Jeremy's reference. The picked image goes straight into markup as before. On iPad the menu hangs off the tile.
2+3. **Cover picker is one page**: preview, **Color**, **Theme** (category), **Picture** ("No picture" first, then the
   category's pictures with thumbnails) and **Style** (Shaded, Framed, Solid — the JSON order). Solid is a style and can carry
   a picture (drawn over the solid fill). A cover saved with the old "Solid" category decodes as style Solid + No picture
   (`CoverChoice` migration; the picker lists the first category's pictures). "No picture" is stored as an empty `option`.
4. **Summary → long-press → Remove finding** asks "Remove this finding?" (the finding line, Remove / Cancel).
5. **Cover footer box** (`covers.layout.footer.box`): the ownership notice sits in the same box on every cover — bottom-left
   (0.55–4.25 in, never past the center line), the right-hand box when the picture is on the left (4th of July); centered in
   the box, drawn above the art, company name underlined; a long company name steps the size down (to 9 pt) to stay inside.
6. **Address of Inspection, 2nd line**: its underline starts and ends exactly under the first line's value underline.
7. **Address split**: wizard step 1 is Inspection address (street, "Street address") → **City** (required) → State → **ZIP
   code** (optional; digits, "-" inserted after 5 → `84015` / `84015-1234`, validated) → the state's notes. City / ZIP code are
   inserted by the app until the shared JSON lists them (`WizardRules.step1`), stored in the inspection's `fields`
   ("City", "ZIP code"). Cover line 2 = "City, ST ZIP"; list subtitle "City, ST"; emails "street, City, ST ZIP".
   Existing inspections are split once at sign-in (`Inspection.splitLegacyAddress`: "1428 Ridgeline Dr, Ogden, UT 84403" →
   street / Ogden / UT / 84403, unit suffixes kept); text that doesn't read cleanly stays as it was and still shows.
8. **`visibleIf`** (generic, `ItemVisibility`): `{q, atLeast: n}` and `{q, includes: option}` on any item; hidden items are not
   shown, validated or printed (their answers are kept). Lead shows "Sample N location" for N ≤ Samples taken.
9. Meth Test photo category **Cartridge Result** (data) shows.
10. Meth Test **Other** + "Other area tested" (visibleIf includes Other).
11/14. **Section titles** (`title`): "Septic System", "Wood Destroying Organism Inspection" — wizard chips, Sections list,
    drawer, section / photo headers, Summary, report contents, PDF section bands / photo pages / Summary of Findings, Manage
    checklist. `name` stays the stored key (`ChecklistCatalog.title`).
12. **`reportNote`** (generic): Radon's two paragraphs print under the measured level, above Overall condition.
13. **Form reports** (data v1.9 `formReports`, `Report/FormReports.swift`): Wind Mitigation and Termite use the same form item
    list on every depth (no Overall condition). On first open, `prefill` items take the inspection / company values (owner
    name, street, city, ZIP, phone, email, license type "Home Inspector", inspector initials); never-opened forms print those
    values too.
    - **Wind Mitigation → OIR-B1-1802 (Rev. 01/12)**, 4 pages like the official form: header, Inspection Date, Owner
      Information grid, NOTE, Q1–Q7 with every official answer in full and ☐/☒ boxes (filled values underlined), the 2.1
      roof-covering table, the Opening Protection Level Chart with X marks (D shaded for glazed openings), A–X with .1–.3, the
      qualified-inspector block (license checkboxes, printed name; signature / date / homeowner lines blank) and the statutory
      text; every page footer "Inspectors Initials … Property Address …", the validity note and "OIR-B1-1802 (Rev. 01/12)
      Adopted by Rule 69O-170.0155 · Page X of 4" (second render pass knows the total).
    - **Termite → Wood Destroying Insect Inspection Report**: VIMS's own one-page layout (Sections I–V, ☐/☒ A/B with the 1–3
      descriptions, previous treatment, recommendations, obstructions table, comments / attachments, blank seller and buyer
      signature lines, one neutral line). Not a copy of NPMA-33 (copyrighted; no NPMA wording or marks).
    - Each form's photos print on a pictures page right after it.
- **Splash** (team Oct 14): `vims-splash.mp4` (720×1280) when the window is taller than wide, `vims-splash-wide.mp4` (1280×720)
  when wider (iPad landscape); chosen once at launch; 10 s, timeout = length + 3 s (`SPLASHTEST ended after 10.46 s, at 10.00 of 10.00 s`).
- DEBUG: `-oct17 fill|blank` (adds Radon, Meth Test, Termite, Lead, Septic, Wind Mitigation, marked done; `fill` answers them and
  gives the forms a photo, `blank` leaves the forms unopened). UI-test plans gained `longPressAt`.
- Screenshots `screenshots/oct21-*.png` (iPhone 17; `oct21-ipad-*` iPad Pro 13"): `a01`–`a11` QA items, `b01`–`b12` client
  items, `c1-wind-page1…4-vs-official` (our PDF beside the client's OIR-B1-1802), `c1-wdi-report-vs-npma33-reference`,
  `c1-*-pictures-page`, `c1-wind-page1-prefill-only`, `c2` wide splash.

## Team QA Oct 22 (shared data v1.9.1)

- **Auto-sync** (`AppStore.requestAutoSync`): with Settings → "Auto-sync when online" on, queued inspections sync by
  themselves — when the connection comes back, when the app comes to the foreground, when auto-sync is switched on /
  a session loads, and 3 s after a save or report (the delay restarts on every edit). Quiet (no toast); the header pill
  and "N inspections waiting" drop to Synced / "Everything is synced". An inspection edited during an upload stays
  queued and goes again. Off = **Sync now** only. TODO(backend): `SyncService` is still the local stub.
- **Numbers while typing** (`FieldKind.filter` + `FilteredTextField`): a character a numeric field can't take is simply
  not accepted. Temperature: digits, one ".", optional leading "-", 1 decimal, max 5 characters (−60–140 on Next as
  before). Total sq ft: whole numbers, number pad, grouping commas ("2,450"). Valuation: 2 decimals, grouping commas.
  Lot size: 2 decimals. Checklist `num` items: 2 decimals unless `decimals` (Radon "Measured level (pCi/L)": 1,
  0–999.9) or `integer: true` (counts, years, Septic "System number" 1–99 → number pad). Integer digits are capped at
  the max's length. **Whole-number fields**: a typed or pasted "." and everything after it is discarded (paste
  "2450.5" → "2450"; "2450" + "." + "5" stays "2450", never "24505"), with a brief "Whole numbers only" under the field.
- **Keyboard**: a tap anywhere outside the active field closes it, on every screen (`KeyboardDismiss`: one
  non-cancelling tap recognizer per window — scrolling, buttons and chips still work; a tapped button both acts and
  closes the keyboard).
- **Confirmations** are centered alerts with a short title and message and explicit buttons (iOS 26 turned
  `confirmationDialog` into a cramped popover without Cancel): inspection (above), plan ("Delete the “<plan>” plan?" /
  "It will no longer be offered on the Subscription screen." + "Your company will move to <next plan>." for the current
  plan), finding, inspector, checklist item / header, custom section, agreement block, revert to the VIMS agreement,
  discard agreement edits, Make owner, and a final "Delete your account?" after typing DELETE. (Photo × delete stays
  one tap, as in the prototype.)
- **Responsive**: the form badge row (Wind Mitigation "Uniform Mitigation Verification Inspection Form", WDI, Texas,
  4-Point) puts the hint beside the badge only when it gets ≥ 180 pt, else under it; the badge wraps on the narrowest
  phones (`BadgeHintLayout`). Header titles wrap to 3 lines (and shrink slightly) instead of truncating ("Wood
  Destroying Organism Inspection", Texas sections). Home rows on < 380 pt windows (SE / mini) put the status pill under
  the address; titles take 2 lines. Inspector emails shrink to fit. Audited on iPhone SE (3rd gen), iPhone 17,
  17 Pro Max and iPad Pro 13".
- **Data v1.9.1**: `wizard.defaults.inspType/loan` and the chip defaults are null (decoded as optional) — nothing is
  preselected on New Inspection except Checklist depth (from Settings), date/time (now), counts and Property type.
  **Type of inspection is required**: red "*", "Select the type of inspection" under the chips, scrolls there (TX
  still auto-selects Texas). Demo seed inspections keep sample chip answers (`DemoSeed.sampleChoices`).
  Meth Test (High Detail) "Test date" / "Test time" are date / time pickers; an old "Test date and time" text (+ AM/PM
  chips) moves onto them when the section opens and in the report (`SectionAnswers.migratingSplitDateTime`), else the
  old text is kept as the date answer.
- DEBUG: `-offlineFor N` (offline for N s, then reconnects), `-markQueued`, `-autoSync on|off`, `-methLegacy [TEXT]`
  (with `-oct17`), `-confirmAlert` (Delete account: type DELETE → the final alert).
- Screenshots `screenshots/oct22-<device>-*.png` (`iphoneSE`, `iphone17`, `iphone17ProMax`, `ipad13`).

## Client round Oct 22 (shared data v1.9.2)

- **vimsinspect.com addresses**: defaults `support.feedbackEmail` = support@vimsinspect.com, `support.reportBcc.email` =
  quality@vimsinspect.com, `support.platformOwners` = masteradmin@ + admin@vimsinspect.com (both get "VIMS owner").
  `support.replacedDefaults` / `domainEmails` decode as optional. On launch `PlatformSettings.migrateReplacedDefaults`
  replaces a stored Feedback or BCC address that still equals an old shipped default (trimmed, case-insensitive) with
  the current default; an address the owner typed is kept. Help & feedback, Settings → Send feedback and How VIMS works
  use `AppStore.supportEmail` (blank → the JSON default). No old address is hard-coded.
- **Phase 2 — Plumbing** (Pre-Drywall 4-way) gains "Shower pan filled for testing" and "Shower pan leaking" (Yes / No)
  before Comments, from the JSON; saved Phase 2 inspections open unchanged (answers are keyed by question).
- **Covers**: Holidays gains Halloween (the Fall art and rect); Seasonal is unchanged.
- DEBUG: `-seedPlatform "FB|BCC"` (store those addresses as an older build would; the migration runs on the next
  launch), `-platformStatus` (PLATFORMTEST lines), `-section NAME` with `-screen phase1|phase2` (e.g. `Plumbing`).
  Screenshots `screenshots/oct22b-*.png` (`oct22b-pdf-*` are pages of the generated PDF).

## Client round Oct 23–25 (shared data v1.10.0)

- **Covers**: new Spring, Christmas and Fall art, `halloween.webp` for Halloween and Holidays → **Cinco de Mayo**
  (`cinco-de-mayo.webp`). `SharedCovers` is a synchronized group, so new files are bundled automatically (checked in the
  built .app). The art is drawn at its JSON rect, which now matches each image's aspect ratio and stays right of center,
  clear of the footer box. Picker thumbnails and the PDF cover verified (`oct25-13-pdf-covers-*`, `oct25-ipad-04-*`).
- **Type of inspection**: `wizard.retiredInspectionTypes` ("Code") is not offered for new inspections; an inspection saved
  with it keeps the chip while edited and still opens, lists and prints its type. Tapping the selected chip again
  deselects it; Next then shows "Select the type of inspection" (still required).
- **Areas locked** (`wizard.areasLockedTypes`: Phase 1, Phase 2, Tests Only, 4 Point): step 3 shows one note ("Not used for
  a Tests Only inspection" / "Not used for a 4 Point Inspection") and the exterior, interior room and utility chips
  disabled (dimmed, not tappable, VoiceOver "dimmed" + the note as hint); Bedrooms / Bathrooms / Hallways stay editable.
  The choices are kept, so another type unlocks them as they were. The builder ignores them for these types.
- **Builder**: phase layouts use the same entry forms as `standardLayout` (`link`, `sections`, `always`, `optional`,
  `order`, `sub`). **Tests Only** = Inspection Info + Testing (the tests chosen in step 4, plus admin custom Testing
  sections) + Summary.
- **No sync in Phase 1** (`features.sync`, decoded as optional, false when absent): no header sync pill, no Settings →
  Sync section, no "Waiting to sync" tile (Home shows "In progress"), no "Queued" status (a generated report is Done ·
  "Report ready"), no offline/sync banner or wording (Report ready, sign-out alert "Your inspections stay saved on this
  device.", How VIMS works, Delete account). `requestAutoSync` / `syncNow` / `performSync` return immediately. Turning
  the flag on restores the Oct 22 behavior unchanged.
- **How VIMS works**: "Everything saves on your device … not copied to a server"; the support link is
  `AppStore.supportEmail` (support@vimsinspect.com, also after upgrading from a build that stored VIMSInspect@Gmail.com).
- **Admin-edited sections** now remember the JSON items they were saved against (`SectionDef.baseItems`), so items the
  JSON adds later (e.g. Phase 2 Plumbing's shower pan items) still show in an edited section. Edits saved before this
  build have no record and are used as saved (re-save the section in Manage checklist to pick new items up).
- **Free trial**: with the trial over and no active subscription, every New inspection (Home +, Home button, side menu,
  and the wizard route itself) shows "Your free trial has ended" (Not now / Subscribe); the wizard refuses to build a new
  checklist. Existing inspections still open, edit and share / re-send their reports. Home: "Free trial ended ·
  Subscribe"; the sign-in splash, Plan & billing and Subscription say so too.
- **One free trial per device** (`Data/Store/DeviceTrial.swift`): the first Create account on a device records its
  trial start in the Keychain (`AfterFirstUnlockThisDeviceOnly`, survives reinstalling the app). A later company created
  on the same device starts with the trial used ("This device has already used its 30-day free trial.",
  `SubscriptionState.deviceTrialUsed`). Builds before this backfill the record once from the companies on the device.
  The demo account's trial clock is kept there too, so reinstalling or re-seeding never restarts it (Release has no
  launch-argument paths at all). TODO(backend): the server enforces this with Apple DeviceCheck.
- **Inspection agreement** v2026-10-25 (Wind Mitigation Inspection service line, agent name / email on separate lines)
  shows in the viewer, editor and PDF straight from the JSON; a company's edited or uploaded agreement is kept (the
  locked form block always comes from the current VIMS agreement).
- DEBUG: `-resetDeviceTrial` (clear the Keychain trial records), `-deviceTrialStatus` (DEVICETRIAL lines), `-wizType TYPE`
  (wizard draft type), `-depth` now also applies to `-screen phase1|phase2`, `-showerPan` (with `-screen phase2`: answer
  and finish Plumbing's shower pan items), `-staleOverride NAME [-legacyOverride]` (CHECKLISTTEST), `-inspection Code`
  (a retired-type inspection). `-resetData` also restarts the demo's trial clock.
- Screenshots `screenshots/oct25-*.png` (iPhone 17, upgraded from 8bcc54f: 01–18; `oct25-ipad-*` iPad Pro 13", fresh).

## Client Oct 28 (shared v1.11.0)

- **Master admin** (`support.platformOwners`: masteradmin@ + admin@vimsinspect.com, trimmed, case-insensitive; another
  domain such as vimsinspection.com is not an owner). Owners get a "Master admin" badge on the Settings account card and
  the side-menu header, and a clearly labeled **Master admin** section in both the side menu and Settings (right under
  the account): Plans & pricing, Report quality copy (BCC), Feedback & support. **Plans & pricing is master admin only**:
  removed from the company Admin group, and the route shows "Not available" for anyone else (like the BCC / feedback
  screens). Company admins keep Manage checklist and Inspectors; a master admin who joined a company as an inspector
  sees the Master admin section without the company Admin group.
  *What was wrong on iOS:* the owner flag itself was already set correctly — checked on the 31068ba build with
  " Masteradmin@VIMSInspect.com " through Create account and at session restore (`isPlatformOwner=true`). The owner
  screens were the problem: two rows labeled "VIMS owner" at the very bottom of Settings (below the fold), nothing in the
  side menu, no badge, while Plans & pricing showed for every company admin — so a master admin looked exactly like any
  company admin (`screenshots/oct28-00-before-31068ba-owner-settings.png`). Also `-signInAs` now trims its email.
- **VIMS plans & prices are VIMS-wide** (`PlatformSettings.plans / extraInspectorMonthly / extraInspectorYearly`, stored
  once in SwiftData; nil = the shared JSON). Older builds kept a per-company copy that company admins could edit;
  `AppStore.applyPlatformPricing()` now mirrors the VIMS plans into the signed-in company on every session load, so
  upgraded companies get the Oct 28 prices; a company whose plan was deleted, or that is on a "Coming soon" plan without
  an active subscription, moves to the first plan it can pick. TODO(backend): server-owned (Square catalog).
- **Pricing (data v1.11)**: App only $34.95/mo or $385/yr; additional inspector $24.95/mo or $275/yr; Pay per report $5
  (no yearly); Portal + App $74.95/mo or $825/yr, `comingSoon` → "Coming soon" pill, dashed dimmed card, not selectable.
  New keys decode as optionals (`PlanDef.priceYearly / comingSoon`, `SubscriptionDef.extraInspectorYearly /
  billingPeriods`, `SubscriptionState.billingPeriod / extraInspectorYearly`). **Subscribe**: Monthly / Yearly segmented
  choice (disabled with "… has no yearly option." for Pay per report); each plan shows the chosen period's price with the
  other underneath; the plan and period are a draft saved by Start / Update subscription; extra inspectors, the total
  ("Monthly total" / "Yearly total") and "auto-renews monthly / yearly" follow the period; the confirmation says "billed
  yearly · $660.00/yr". **Plan & billing**: Plan "App only · $385.00/yr", Billing period, Inspectors "1 × $275.00/yr",
  Yearly total, next billing +1 year. Settings → Plan & billing subtitle "App only · Yearly · $660.00/yr". **Plans &
  pricing** (master admin): Monthly and Yearly price per plan (Yearly blank = monthly only), per-report price for Pay per
  report, Additional inspector monthly + yearly rates, add a plan with an optional yearly price. Billing is still the
  local stub (TODO(backend) Square).
- **Restore checklist to original** (Manage checklist, company admins): a summary card ("2 edited sections and 1 custom
  section you added.") with **Restore entire checklist to original**; each edited VIMS section has an amber **Edited** pill,
  a "Your company changed this section. · Restore original" row under it, and the group header counts "N changed"; Edit
  section shows "Edit section · Edited" and a Restore original button. Every restore asks first (centered alert explaining
  that it removes the company's changes and that inspections already started keep their saved checklist). Restoring
  removes the overrides / custom sections, so new inspections get the JSON defaults. **Inspections already created keep
  their checklist**: before the overrides are removed, every inspection of the company on the device that uses one of those
  sections (the user's and teammates' who signed in here) stores the definitions in `Inspection.savedSections`;
  `AppStore.catalog(for:)` lets them win for that inspection (entry, photos, summary, report), and re-editing it in the wizard
  keeps its restored custom sections. Manage checklist / Edit section routes are admin-only.
- **Master admins need no trial or subscription** (`AppStore.isSubscriptionExempt`; TODO(backend): the server grants
  this with the owner role): no trial splash, no "Your free trial has ended" / "This device has already used its 30-day
  free trial" / Subscribe prompts, New inspection always works (also with the company's trial over); Home shows "Master
  admin · no subscription needed" instead of the trial banner, Settings → Plan & billing and Plan & billing / Subscribe say
  the same instead of a countdown or plan. A master admin's Create account doesn't use up the device's free trial
  (`Bootstrap.newCompany` skips `DeviceTrial` for owners; the one-time backfill ignores companies owned by a master admin),
  so a real company created on that device later still gets its 30 days. Non-owners are unchanged.
  Screenshots `screenshots/oct28b-*.png`; `-deviceTrialStatus` now prints `exempt=`.
- DEBUG: `-ownerStatus` (OWNERTEST), `-pricingStatus` (PRICINGTEST), `-checklistStatus` (CHECKLISTTEST), `-customSection
  "NAME|Group"`, `-confirmRestore NAME|all` (with `-screen manage`), `-period monthly|yearly` / `-plan ID` (with `-screen
  subscribe`).
- Verified on iPhone 17 (iOS 26.5), upgraded in place from a 31068ba build with an edited checklist (Roof, Chimney), a
  custom section, an active monthly subscription and a saved master-admin session, then on a fresh install: Create account
  typed as " Masteradmin@VIMSInspect.com " (badge + Master admin section), sign-in with " MasterAdmin@VIMSInspect.COM ",
  Join with " Admin@VIMSInspect.com " (owner, not company admin), session restore, masteradmin@vimsinspection.com (not
  an owner), a non-owner company admin (no Plans & pricing; route blocked), a master-admin price edit showing up for another
  company, both restores and their effect on existing inspections, Subscribe Monthly / Yearly with 2 inspectors → $660.00/yr.
  Screenshots `screenshots/oct28-*.png`.

### iOS 0.23.0 (24) — client Oct 28, 2nd round (shared v1.11.1, EULA 2026-10-28)

- **Version**: `MARKETING_VERSION` 0.23.0, `CURRENT_PROJECT_VERSION` 24 in every configuration (was 0.1.0 / 1). Bundle
  identifier unchanged (`com.vims.app`).
- **Restore block at the top of Manage checklist** (under the intro hint, above Add section; company admins and master
  admins alike): "Restore checklists" card with **Restore all checklists** (the existing whole-checklist restore and
  confirm, retitled "Restore all checklists to the original?") and **Restore selected checklists** (each section is one
  checklist). Both are disabled with "Your checklist matches the VIMS original, so there is nothing to restore." when
  nothing is edited. The picker sheet (`RestorePickerSheet`) lists only Edited / Added sections with those tags (custom
  sections are now tagged **Added** in the list too), a checkmark toggle per row (52 pt rows) and Select all; "Restore N
  selected" opens one confirm naming the sections ("Restore 2 checklists?" — "“Roof” goes back to the VIMS original.
  “Solar Panels” was added by your company and is removed. …"). `AppStore.restoreSections(_:)` reuses the per-section
  restore (started inspections keep their checklist via `savedSections`; added sections are removed) and shows one toast.
  The per-section Restore original stays.
- **Plans & pricing**: the Additional inspector card says "Applies to every plan, so it can’t be deleted." (no Delete).
- **EULA 2026-10-28** (Revised October 28, 2026): bundled from shared/legal/eula.json through the SharedLegal group; the
  version change shows the "Updated license agreement" gate once to every signed-in user, then not again. 3.5 and the
  section 13 "Notices to Us:" address paragraph render as ordinary paragraphs.
- **Cancellation per EULA 4.1 / 12.3 / 12.4**: monthly — unchanged, active until the next billing date, then stops
  renewing (no refund). Yearly — the confirm says access ends today and shows the pro-rated refund (price paid × days
  remaining ÷ days in the period, rounded to cents, e.g. $660.00 × 200 ÷ 365 = $361.64) that "will be refunded to your
  card"; Yes, cancel sets `active = false` with `SubscriptionState.endedAt / refundAmount / refundDays` (optional, older
  data decodes), and Plan & billing shows "Cancelled · ended <date>", Access ended, Pro-rated refund and an explanatory
  card. New inspections are then gated like an ended trial ("Your subscription has ended" / Home "Subscription ended");
  master admins stay exempt. `paidAmount` is recorded on Start / Update subscription (nil on older data → current total).
  Billing periods now roll forward from `startedAt` (`billingPeriodBounds`), so "Next billing" is never in the past.
  TODO(backend): Square cancel + Square refund (`SubscriptionService.cancelSubscription(period:refund:)`).
- DEBUG: `-pickRestore [-pickAll]`, `-confirmRestore picked|"A,B"`, `-subPeriod monthly|yearly` and
  `-subStartedDaysAgo N` (with `-activeSub`, prints CANCELTEST), `-confirmCancel` (with `-screen billing`).
- Verified on iPhone 17 (iOS 26.5) with real taps through the VIMSUITests plan runner. Screenshots
  `screenshots/oct28c-*.png`.
