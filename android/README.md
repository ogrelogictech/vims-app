# VIMS — Android app (native Kotlin / Jetpack Compose)

The native **Android** build of VIMS Phase 1. **Native Kotlin with Jetpack Compose — not Flutter, not React Native, not a shared cross-platform codebase.** The iOS app is built separately in `/ios` with Swift/SwiftUI.

## Build against
- **Live prototype (the spec):** https://vims-app.pages.dev — build screen-for-screen and behavior-for-behavior to match it.
- **Spec & flow:** [`../docs/VIMS-Build-Spec.md`](../docs/VIMS-Build-Spec.md)
- **Design tokens** (colors, type, spacing, radii, components): [`../docs/design-tokens.md`](../docs/design-tokens.md)
- **Screens:** [`../screens/`](../screens) (numbered to match the spec)
- **Reference UI + data model:** [`../index.html`](../index.html) — the whole prototype in one file; read it for exact checklist data, depth tiers, and interactions.

## Stack
- **Kotlin + Jetpack Compose**, offline-first (local store, e.g. Room), targeting current Android.
- Syncs to the **PHP/Laravel + MySQL** API as it comes online (Phase 2).

## Scope reminders
- Phase 1 = the app + company accounts/subscriptions (Square for the **company subscription** only).
- **Client-payment screens (Collect payment / Payment received) are a confirmed add-on — not part of the committed Phase 1 build.**
- Web portal/CRM + real-time sync are Phase 2 (separate).

## Working agreement
Branch → PR into `main`. Route client questions through OgreLogic — do not contact the client directly.
