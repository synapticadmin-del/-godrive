---
document: privacy_policy
version: "2026-08-01"
language: en
authoritative: false
status: pending-counsel-review
---

# Privacy Policy — Synaptic Go (GoDrive)

**Version:** 2026-08-01

English translation of `privacy-policy.ar.md`. The Arabic text is authoritative;
where the two differ, Arabic governs.

This policy describes the data the product actually collects, where it is stored,
who it is shared with, and how long it is kept. It was written by reading the
code, not by reading the product description.

> **Note for counsel:** the controller details in §1 are placeholders
> (`TODO(legal)`) and must be completed before either store listing goes live.

---

## 1. Who we are

Synaptic Go ("we") operates the GoDrive rider and captain apps and the booking
service behind them, in the Arab Republic of Egypt.

- **Controller:** `TODO(legal): registered legal entity`
- **Registered address:** `TODO(legal)`
- **Privacy contact:** `TODO(legal): privacy@…`

## 2. What we collect

**Account.** Email (required — it is the login identifier), name, phone number,
profile photo if you upload one, and role (rider or captain).

**Location.** For riders: pickup and drop-off points and their addresses, plus any
places you save yourself (home, work). For captains: current position while you
are online, and the route of a trip recorded at intervals while it runs. Location
is collected in the course of using the service and for its purposes — matching,
pricing, in-trip tracking and safety.

**Trips and payments.** Trip history, status and fares, payment method, wallet
movements, ratings and comments, in-trip chat messages, and SOS reports including
the location at the time they were raised.

**Captains, additionally.** Full legal name as printed on the national ID, date of
birth, national ID number, driving licence details and expiry, vehicle details, and
images of the documents required for approval. **This is a sensitive category.** It
is collected only from captains and only to verify eligibility to drive.

**Device.** Push notification token, platform, and the IP address and client details
attached to requests — used to deliver notifications and to prevent abuse.

## 3. Why we process it

| Purpose | Data | Basis |
|---|---|---|
| Providing the service (booking, matching, fulfilment) | account, location, trip | performance of a contract |
| Payments and accounting | payments, wallet, trips | contract + legal obligation |
| Safety and incident investigation | location, trip, SOS, chat | legitimate interest + legal obligation |
| Captain approval | documents, identity | legal obligation + contract |
| Operational notifications | device token | performance of a contract |
| Fraud and abuse prevention | IP, request metadata | legitimate interest |

## 4. Consent

Consent is recorded **server-side**, not merely in the app. Each record carries the
document (privacy policy or terms), the version, the timestamp and the source.

The record is **append-only**: withdrawing consent writes a new row, and no earlier
row is ever updated or deleted. That is deliberate — the consent history *is* the
evidence, and editing it destroys the evidence.

You can read your own consent history at any time from the app, or via
`GET /user/consent`.

## 5. Where data is stored

Infrastructure runs on **Cloudflare** (D1 databases, R2 object storage, KV, Workers).
Because that network is distributed, data may be processed outside the Arab Republic
of Egypt. Document images are stored in R2 and are reachable only by staff authorised
to review approvals.

## 6. Who we share with

Only what is necessary, and with these categories:

- **The other party to your trip.** A rider sees the captain's first name, photo,
  vehicle details and position during the trip; a captain sees the rider's first name,
  pickup and drop-off.
- **A payment provider**, to process electronic payments.
- **A notification provider**, to deliver push notifications to your device.
- **Mapping, routing and geocoding providers**, to compute distance, duration and route.
- **Competent authorities**, on a valid legal request.

**We do not sell your data and we do not use it for third-party advertising.**

> **Explicit disclosure.** The routing service configured in the production
> environment today is a public demonstration server (`router.project-osrm.org`),
> and pickup and drop-off coordinates are sent to it. There is no data-processing
> agreement with that server. This is being corrected under launch-gate item 11, and
> this paragraph will be updated when routing moves to a contracted provider.

## 7. Retention

| Data | Period |
|---|---|
| Account and profile | until deletion |
| Trips and financial records | 10 years (tax and accounting obligation), attached to an anonymous id after deletion |
| Captain documents (images, identity) | until deletion or the end of the relationship, whichever is sooner |
| Safety (SOS) reports and chat | 3 years |
| Consent records | 10 years — they evidence that processing was lawful |
| Detailed trip path | see `data-retention-and-erasure.md` |

## 8. Your rights

You have the right to **access**, **correct**, **export**, **delete**, and to
**withdraw consent**.

- **Export** — in-app (Settings → Privacy & data → Export my data) or
  `GET /user/export`. You receive a JSON file containing everything we hold about
  you, except credentials (password hash, stored card tokens, device push tokens).
  Those are keys, not personal data, and putting them in a re-sendable file is
  itself a security risk.
- **Correction** — the profile screen, or `PATCH /user/profile`.
- **Deletion** — in-app, or from a public page that does not require installing the
  app: `/user/deletion-request`. Full detail in `account-deletion.md`.

What is **not** deleted, and why: financial records (tax obligation), consent records
(evidence of lawfulness), and safety reports and trips shared with another party. All
of these are detached from your identity and remain attached to an anonymous id.

## 9. Children

The service is not directed at anyone under 18 and we do not knowingly collect their data.

## 10. Changes

Any material change raises the version number and we ask for consent again. Your
previous consent remains recorded against the version you actually agreed to.

## 11. Contact and complaints

`TODO(legal): contact address`. You also have the right to complain to the competent
personal-data protection authority under Law 151 of 2018.
