# VIMS — Design Tokens

Pulled directly from `source/index.html` (`:root` variables). Match these exactly.

## Color

| Token | Hex | Use |
|---|---|---|
| brand | `#2F5EC9` | Primary royal blue — header bar, primary buttons, selected chips, links |
| brand-bright | `#5580E6` | Gradients, progress fills, avatars |
| brand-deep | `#1E3D94` | Pressed state, deep text on tint, appointment time |
| hdr | `#2F5EC9` | App header / status bar background |
| hdr-sub | `#D7E3F7` | Subtitle text on the header |
| ink | `#17222E` | Primary text |
| ink-2 | `#3F4E5E` | Secondary text |
| ink-3 | `#5F6D7D` | Tertiary text / hints |
| line | `#DDE5EE` | Borders |
| line-2 | `#EEF2F7` | Hairline dividers |
| paper | `#FFFFFF` | Cards |
| paper-2 | `#F4F7FA` | Screen background |
| paper-3 | `#E9EEF4` | Inset chips / lead tiles |
| signal | `#E4A11B` | Amber accent (Queued status, "generate summary" button) |
| signal-deep | `#A5730A` | Amber text |
| **review FAB** | `#FFFF61` | The round "jump to screen" button, bottom-right (client-specified) |

### Finding / status categories
| Token | Hex | Meaning |
|---|---|---|
| c1 | `#D0584A` (bg `#FBE9E6`) | **Category 1 — Safety** |
| c2 | `#C98A1A` (bg `#FBF1DD`) | **Category 2 — Functional** |
| c3 | `#2F9E6B` (bg `#E7F4EE`) | **Category 3 — Items to monitor** |
| pass | `#2F9E6B` | Pass (phase inspections) |
| fail | `#D0584A` | Fail |

Status pills: Done = green, In progress = blue, Queued = amber, Scheduled/New = grey.

## Type
- **Display / headings:** Archivo — 600 / 700 / 800
- **UI / body:** IBM Plex Sans — 400 / 500 / 600 / 700
- **Mono (times, codes, labels, prices):** IBM Plex Mono — 400 / 500 / 600
- Section label caps (`.lbl`): 10.5px, uppercase, letter-spacing .12em, ink-3.

## Shape & spacing
- Card radius **14px**; buttons **13px**; chips (pill) **22px**; inputs **11px**; lead tiles **11px**.
- Min tap target **44–52px** (buttons 52px min-height; chips 40px; inputs 48px).
- Screen padding 16px; card padding ~15px.
- Device frame: mobile-first, content column max-width **430px**.

## Core components (all visible in the prototype)
- **Header bar:** left = Back (or hamburger on Home) · center = title + property subtitle · right = contextual actions (Camera → Photos, List → Sections drawer, Home). Blue (`hdr`), white text.
- **Chips:** single-select and multi-select; **tap again to deselect** (single). Selected = brand fill, white text.
- **Segmented control** (`.seg`): overall-condition row.
- **List row** (`.row`): icon/time lead + title + subtitle + status pill + chevron.
- **Grouped accordion** (`.grp`): the sections overview and the checklist drawer.
- **Checklist mode badge** (`.modetile`): one badge per depth — "High Detail checklist" (blue) / "Standard checklist" (grey) / "Fast Entry checklist" (amber) + hint.
- **Sub-section header** (`.lihead`): blue band inside a section (e.g. Electricity, Natural Gas).
- **Photo grid** (`.pgrid`): capture tiles with delete (×) and category flag; **photo viewer** = full-screen image + draw (3 pens) + stamps + quick-comment dropdown + Save markup / Save & return.
- **Finding modal** (bottom sheet): category picker (1/2/3) + quick-comment dropdown + description.
- **Cover picker:** cascading Color → Theme → Style with live preview.
- **Wizard:** 4-step new-inspection (info → property → areas → testing) with a step bar.
- **Trial splash:** free-look countdown, shown at every sign-in during the trial.
- **Toast**, **bottom-sheet modal**, **success screens**.

## Logo
`assets/vims-logo.png` — blue house + green check + tan arc. Used as the app icon and the report-cover mark. Company can upload their own logo (Settings → Company profile) which replaces it on report covers.
