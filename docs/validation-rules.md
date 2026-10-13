# VIMS — Input validation rules (iOS + Android)

One rule set for both apps. Validate **while typing** (filtering/formatting) and **on submit** (required + format).
Errors show inline under the field (12.5 pt/sp, color `c1` #D0584A, field border turns #D0584A) and clear as soon as the value is valid.
On a button tap with errors: keep the user on the screen, show every error, scroll to the first one. Buttons stay enabled.

## Every text field
- No leading space. **Never two spaces in a row** — collapse to one while typing (pasted text too).
- Trim trailing spaces on submit. Required fields that are only spaces are empty.

## Field rules
| Field | While typing | On submit |
|---|---|---|
| Email (all email fields) | **Spaces removed**; no auto-capitalize/correct | Required where marked; `^[^@\s]+@[^@\s]+\.[^@\s]{2,}$`; max 254 |
| Password | No spaces | Min 8 characters; Create account: must match Confirm password |
| Person name (client, inspector, agent, sponsor, insured) | Letters, spaces, `. ' -` only; max 60 | Required where marked |
| Company name | max 80 | Required on Create account |
| Phone | Digits only, auto-format `(801) 555-0134` | 10 digits (US) if entered |
| Company join code | Uppercase, auto-insert `-` → `VIS-4827` | 3 letters + 4 digits; must match a company |
| Inspection address | max 120 | Required |
| Inspection date / time | picker | Date required (defaults to today) |
| License # (inspector, sponsor) | Letters, digits, space, `-`; max 20 | Optional |
| Application / Policy # | Letters, digits, `-`; max 30 | Optional |
| Year of construction / Actual year built | Digits, max 4 | 1800 – current year |
| Total sq ft, valuation, lot size, amps, `num` checklist items | Digits + one `.` (valuation/sq ft may also show grouping commas `450,000`; commas and a leading `$` are ignored when reading the value, never an error) | > 0 if entered; at most the field's max (see Number limits) |
| Temperature (°F) | Digits, optional leading `-` | −60 – 140 |
| Review URL | No spaces | Must start `https://` or `http://` and have a host |
| Feedback email (admin) | as Email | Required, valid |
| Plan price / per-inspector rate (admin) | Digits + `.`, max 2 decimals | 0.01 – 9,999.99 |
| Admin: section name | max 60 | Required, unique |
| Admin: question text / option | max 120 / max 60 | Required; no duplicate options in one question |
| Add inspector | name + email rules above | Both required; email not already on the team |

## Card entry (Subscribe) — placeholder until Square's card SDK replaces it
| Field | While typing | On submit |
|---|---|---|
| Card number | Digits only, grouped `4242 4242 4242 4242` (Amex `3782 822463 10005`); show brand | 13–19 digits (Amex 15) and passes the **Luhn** check |
| Expiry | Digits, auto-insert `/` → `MM/YY` | Month 01–12; not in the past; at most 20 years ahead |
| CVC | Digits only | 3 digits (Amex 4) |
| Cardholder name | Person-name rule | Required |
| Billing ZIP / postal code | Letters, digits, space, `-`; uppercase; max 10 | 3–10 characters (US `84015` or `84015-1234`, Canada `K1A 0B1`, UK `SW1A 1AA`) |

## Number limits (Oct 13, 2026 — team QA)
Every numeric field and every − / + stepper has a minimum and a maximum. The + button disables at the max, − at the min; typed values above the max show "Enter a number up to <max>".
| Field | Min – Max |
|---|---|
| Inspector seats (Subscription) | 1 – 50 |
| Wizard counts: bedrooms, bathrooms, kitchens, hallways, living/family/dining rooms, garages (cars), any other room/area count | 0 – 20 |
| Stories (custom "Other") | 1 – 10 |
| Year of construction / actual year built | 1800 – current year |
| Total sq ft | 1 – 100,000 |
| Valuation ($) | 1 – 100,000,000 |
| Lot size (acres) | 0.01 – 10,000 |
| Checklist `num` items (counts, sizes, readings, gallons, amps, etc.) | 0 – 99,999 (counts like "Number of kitchens/bathrooms" 0 – 20) |
| Indoor Air Quality level measured | 0 – 99,999 |
| Plan price / per-inspector rate | 0.01 – 9,999.99 |

## Text selection
Focusing a field never auto-selects its existing text: the cursor goes to the end (or where the user tapped). Applies to every form in both apps.

## Checklist `num` items while typing
Only digits and one `.` can be typed (other characters are dropped as typed, pasted text filtered); an inline error appears immediately if the value is above the max. Text items such as "System number" ("e.g. 1 of 2") stay free text with the general text rules.
