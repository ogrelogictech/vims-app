# VIMS — Vision Inspection Management Solutions

Offline-first home-inspection platform for **iOS + Android**, with a company web portal to follow (Phase 2).
Client: Vision Property Inspections (Jeremy Heath). Built by OgreLogic.

This repo is the **single source of truth** for the build — we work here in branches/PRs, not over email. The mobile/design team builds in parallel against the approved prototype and spec below.

---

## Live reference prototype (the spec)

**▶ https://vims-app.pages.dev** — the client-approved Phase 1 app (sample data, no install).
Tap the round grid button (bottom-right) to jump to any screen. Report format: **https://vims-app.pages.dev/report.html**

The prototype **is the spec** — build the native apps to match it screen-for-screen and behavior-for-behavior.

## Repo layout

```
/index.html      the entire prototype (self-contained HTML/CSS/JS, no build step) — the reference UI + data model
/report.html     the report / PDF format preview
/vims-logo.png   logo mark (app icon + report cover)
/docs/
   VIMS-Build-Spec.md   screen-by-screen spec, app flow, data model, Phase 1 scope
   design-tokens.md     colors, type, spacing, radii, components
/screens/        PNG of every screen (numbered to match the spec / flow)
/highdetail-data.reference.js   the High Detail checklist dataset (reference)
/.github/workflows/deploy.yml   auto-deploys the prototype to Cloudflare Pages on push to main
/ios/            (mobile team) native SwiftUI app  ← add here
/android/        (mobile team) native Jetpack Compose app  ← add here
```

Native teams: create `/ios` and `/android` (or your own branches) and build alongside the prototype. Open PRs into `main`.

## What to build — Phase 1

Phase 1 is the **mobile app** (offline-first) plus company accounts/subscriptions. Target stack: **SwiftUI (iOS)** and **Jetpack Compose (Android)**, syncing later to a **PHP/Laravel + MySQL** API (Phase 2). See `docs/VIMS-Build-Spec.md` for the full screen list and data model.

**Scope notes:**
- The prototype is Phase 1 UI/UX with **sample data** — "save / sync / generate PDF / charge card" are simulated. Wire them to the backend API as it comes online.
- The **web portal / CRM and real-time sync are Phase 2** — not in this repo/prototype.
- **Client-payment screens (Collect payment / Payment received, screens 31–32) are a confirmed add-on, NOT part of the committed Phase 1 build.** The Square you build in Phase 1 is the *company subscription* billing only.
- "Phase 1 Foundation" / "Phase 2 Pre-Dry Wall" in the app are **inspection types**, not project phases.

## Not in this repo (by design)

Client-confidential material — contracts, signed agreements, client emails, and the raw client source files — is intentionally kept out of this shared repo. Ask OgreLogic if you need anything from those.

## Prototype deploy

Push to `main` → GitHub Actions deploys the prototype to Cloudflare Pages (project `vims-app`). Local preview: `python3 -m http.server 8080` then open `http://localhost:8080`.

## Working agreement
Branch → PR → review. Route client questions through OgreLogic (Mike Johnson / Gaurav Sharma) — do not contact the client directly.
