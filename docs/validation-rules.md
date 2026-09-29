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
| Total sq ft, valuation, lot size, amps, `num` checklist items | Digits + one `.` | > 0 if entered |
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
| Billing ZIP | Digits only | 5 digits |
