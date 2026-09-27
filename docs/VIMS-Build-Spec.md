# VIMS — Phase 1 Build Spec (screen-by-screen + flow)

**Status: client-approved final (Sep 15, 2026).** Build to match.
Live prototype: **https://vims-app.pages.dev** · Report format: **https://vims-app.pages.dev/report.html**
Screens referenced below are in `screens/` (numbers match).

---

## App flow (high level)

```
Sign in ─┬─ Create account
         └─ Join a company with a code
   │
   ▼
Home (Inspections list) ── Trial splash (free-look countdown, every sign-in)
   │
   ├─ New inspection  →  4-step wizard
   │     1 Inspection info (client, contacts, loan, type, site conditions)
   │     2 Property details (type, stories, basement, garage, DEPTH: High/Standard/Fast)
   │     3 Areas to inspect (exterior · rooms · utility systems)
   │     4 Secondary testing
   │        └─►  Build checklist
   │
   ▼
Sections overview (grouped, progress)
   │   ├─ Section entry  (dynamic checklist; depth-aware)  ─► Photos ─► Photo markup / Flag finding
   │   └─ (repeat per section; "Save & next section")
   ▼
Summary (findings grouped: Cat 1 Safety / 2 Functional / 3 Items to monitor)
   │      └─ "Save and generate report"
   ▼
Generate report → pick cover (Color → Theme → Style) → Generate PDF → Report ready

Settings ── Plan & billing · Inspectors · Plans & pricing (admin) ·
            Manage checklist (admin) · Company profile · How VIMS works · Sign out
```

**Inspection type drives the checklist.** A normal type (Real Estate Sale, etc.) builds the full home checklist. **Phase 1 Foundation** builds the pre-pour foundation checklist; **Phase 2 Pre-Dry Wall** builds the 4-way pre-drywall checklist (see 28–29).

---

## Screen-by-screen

**01 Login** — VIMS logo, email/password (password reveal eye), Sign in, Create account, Join a company with a code, Forgot password.
**02 Create account** — name, company, email, password.
**03 Join a company** — an inspector joins an existing company with a **company code** (links to that license/billing).
**04 Home** — trial banner (countdown), today's stats, today's inspections (time + address + status pill), Recent, New inspection, Settings. Header hamburger opens nothing on Home (menu is contextual inside an inspection).
**05 Trial splash** — free-look countdown; shows on **every sign-in** during the 30-day free look; stronger red reminder at ≤10 days. Set up subscription / Continue.
**06 New inspection · Info** — client name, **client phone, client email**, inspection address, **agent name, agent email** (used to send the report), date/time, loan type, inspection type (Real Estate Sale, New Construction, Pre-Sale, Component [→Roof/HVAC/Electrical/Plumbing], Code, Tests Only, Phase 1 Foundation, Phase 2 Pre-Dry Wall, New Build Final), property status, weather + temp, power/gas/water on, buyer concerns, hazards.
**07 Property details** — property type + unit mix, year, sq ft, valuation, lot size, construction style, **Stories (Other → comment box)**, **Basement (separate)**, Garage, Car port, **Number of cars (up to "5 or more")**, and **Checklist depth: High Detail / Standard / Fast Entry**.
**08 Areas to inspect** — Exterior areas · room counts + interior rooms · **Utility & systems** (incl. Boiler, Heating Oil Tank, Propane Tank). All toggleable.
**09 Secondary testing** — Radon, Meth, Thermal, Termite, Lead, IAQ, Septic, Sewer Scope, Asbestos, Wind Mitigation → **Build checklist**.
**10 Sections overview** — progress card + grouped accordion (Inspection Info · Property Exterior · Property Interior [+ Utility & Function] · Testing · Summary). Tap a group → tap a section.
**11 Section entry — Standard** — dynamic checklist. **Fast-entry style:** tap chips, scroll, batch save. Overall condition + comments. Buttons: Photos · Save · **Save & next section**. Mode badge top-left.
**12 Section entry — High Detail** — same section, the fuller checklist from the client's High-detail files, grouped by sub-system with headers (shown: Outside Utilities). ~2,600 High-Detail items exist across all sections.
**13 Section entry — Fast Entry** — condensed quick pass: items-present chips + overall condition + notes (no line-by-line).
**14 Photos** — per photo-category tiles (section-specific). Add (capture), delete (×), concern flag badge.
**15 Photo markup** — full-screen photo: **quick-comment dropdown** (8 canned comments), a **custom comment** text box, **draw** (3 pen colors, undo, clear), **stamps** (★ ↑ ↓ ← →), **Save markup** / **Save & return to inspection**, flag button (top-right).
**16 Flag a finding** — bottom sheet: category (1 Safety / 2 Functional / 3 Items to monitor) + quick-comment dropdown + description → adds to Summary.
**17 Summary** — findings auto-grouped by category (counts), each category header carrying a small non-bold guidance tagline (Safety → "Address before closing"; Functional → "Address in the first few months after closing"; Items to monitor → "Monitor and address over time"). "Save and generate report."
**18 Generate report** — report meta card + **cover picker** (Color → Theme → Style, live preview) + report contents in checklist-number order + "Preview report format" (opens report.html) + Generate PDF.
**19 Report ready** — success; Preview PDF / Email to client / Back.
**20 Settings** — Account (+ **Sign out**), Sync, Subscription & licensing (Plan & billing, Inspector accounts), Admin (Manage checklist, Plans & pricing, **Feedback & support** [30]), **Help & feedback** (Send feedback → contact email), Company & help (Company profile, How VIMS works), Defaults (checklist depth, cover, photo size).
**21 Company profile** — upload **company logo** (used on report cover), inspector info, **online review URL**, and **upload your own inspection agreement** (legal varies by state; client signs it before the inspection).
**22 How VIMS works** — instructions / new-account tutorial; notes that all data is saved locally on the device and works offline.
**23 Manage checklist (admin)** — browse/edit sections & items, add options, reorder, **add a new section**. Groups: Exterior · Interior · Utility · Testing · Phase Inspections.
**24 Plans & pricing (admin)** — edit each plan price, the per-inspector rate, and **add a plan**.
**25 Inspectors** — company **join code** (copy/share) + inspector accounts (add/remove; first included, each additional $24.95/mo). **Roles:** the account owner is **Admin** by default (not hard-coded); any inspector can be promoted via **Make admin** / demoted. Admins manage checklists, plans, company profile, and settings (permission enforcement is backend/role-based).
**26 Subscribe** — plans (App only $34.95/mo · Portal + App $64.95/mo · **Pay per report $5.00**), seats, Square payment, 30-day trial.
**27 Billing** — current plan, inspectors, total, next billing.
**28 Phase 1 — Foundation** — pre-pour foundation checklist (Pass/Fail/N/A): foundation type, site, post-tension, plumbing, result. (Shows when inspection type = Phase 1 Foundation.)
**29 Phase 2 — Pre-Dry Wall (4-Way)** — six sections (Exterior, Framing & Interior, Floor System, Plumbing, Electrical, HVAC), Pass/Fail/N/A. (Shows when inspection type = Phase 2 Pre-Dry Wall.)
**30 Feedback & support (admin)** — owner-only screen to set the feedback contact email (the only place it's editable; the Help & feedback section just sends to it).
**31 Collect payment** — take the client's inspection fee: an editable itemized charge (inspection + services, add/remove lines, live total), and a method — **Card** (Square card fields), **Cash**, **Check**, or **Payment link** (Square link the client pays from their phone). Reached from *Generate report* and *Report ready*. (Distinct from the company subscription payment.)
**32 Payment received** — confirmation of the charge with an email-receipt option.

**Note — multi-select fields:** most checklist lines are pick-one, but some are multi-select (choose several) — e.g. HVAC Mechanical → **Intake location** accepts multiple locations. Multi-select chips toggle independently; single-select clear the others.

**Note on a few testing sections (final content):** *Radon* = test performed + date + time + measured level. *Thermal Audit* = an "Areas scanned" list (outside HVAC compressor, front/back of house, living room, kitchen, bathrooms, water heater, inside HVAC unit, electrical panel) each with its own photo slot. *Sewer Scope* = access location & condition, pipe material, camera length, pipe collapsed / tree roots / separations, findings. *Propane Tank* is available under Utility systems.

---

## Data model & behavior notes (see `source/index.html`)

- **Checklist engine is data-driven.** Sections are defined as JS objects (`SEC`): each has an icon, photo categories (`pics`), and `items` (Standard). Most also have `itemsHigh` / `picsHigh` (High Detail). Item types: single-select, multi-select, numeric/measurement, free text, and sub-section headers.
- **Three depth tiers** (`sel.depth`): High Detail → `itemsHigh`; Standard → `items`; Fast Entry → condensed. Set per inspection (step 2) or as a default (Settings).
- **Dynamic assembly:** the selections in the wizard (structure, rooms, areas, tests, inspection type) drive `buildGroups()`, which produces the section list. Rooms are per-count instances (Bathroom 1–3, Bedroom 1–4, Hallway 1–2).
- **Findings** are flagged from photos/sections into 3 categories and auto-populate the Summary and the report summary pages.
- **Report** (report.html) = branded cover (client fields + property photo + cover art) → property information → beginning notes → per-section data pages → photo pages → categorized summary → invoice. ~75–80 pages. Footer carries client name above the address. Sections populate in checklist-number order.
- **Company-level SaaS:** a company subscribes and adds inspector seats via a join code. Plans/prices are admin-editable. 30-day free look with a countdown.
- **Offline-first:** everything is created/saved on-device and syncs when back online (backend in the native build / Phase 2).

## What to build (native)
Reproduce screens 01–29 and the report format in **SwiftUI** and **Jetpack Compose**, matching `design-tokens.md`. Wire to the backend API (auth, inspections, photos, findings, report generation, subscriptions) as it comes online. Keep the data-driven checklist structure so sections/items/depths remain editable (the in-app admin editor mirrors that).
