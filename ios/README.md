# VIMS — iOS app (native SwiftUI)

The native **iOS** build of VIMS Phase 1. **Native Swift / SwiftUI — not Flutter, not React Native, not a shared cross-platform codebase.** The Android app is built separately in `/android` with Kotlin/Jetpack Compose.

## Build against
- **Live prototype (the spec):** https://vims-app.pages.dev — build screen-for-screen and behavior-for-behavior to match it.
- **Spec & flow:** [`../docs/VIMS-Build-Spec.md`](../docs/VIMS-Build-Spec.md)
- **Design tokens** (colors, type, spacing, radii, components): [`../docs/design-tokens.md`](../docs/design-tokens.md)
- **Screens:** [`../screens/`](../screens) (numbered to match the spec)
- **Reference UI + data model:** [`../index.html`](../index.html) — the whole prototype in one file; read it for exact checklist data, depth tiers, and interactions.

## Stack
- **Swift + SwiftUI**, offline-first (local store, e.g. SwiftData/Core Data), targeting current iOS.
- Syncs to the **PHP/Laravel + MySQL** API as it comes online (Phase 2).

## Scope reminders
- Phase 1 = the app + company accounts/subscriptions (Square for the **company subscription** only).
- **Client-payment screens (Collect payment / Payment received) are a confirmed add-on — not part of the committed Phase 1 build.**
- Web portal/CRM + real-time sync are Phase 2 (separate).

## Working agreement
Branch → PR into `main`. Route client questions through OgreLogic — do not contact the client directly.
