# 🚀 GoDrive Monorepo — AI Agent Architecture & Context Guide (`AGENTS.md`)

Welcome AI Agent! This document serves as your **instant global context and indexing guide**. Reading this file gives you a complete, high-level understanding of the architecture, tech stack, database schemas, and codebase layout without scanning thousands of lines of code.

---

## 🛠️ 1. Project Overview & Technology Stack

GoDrive is a modern, high-performance ride-hailing and delivery platform built with a unified Monorepo structure.

- **Apps & Services**:
  - `apps/rider`: Flutter Rider Mobile Application (iOS/Android).
  - `apps/captain`: Flutter Captain/Driver Mobile Application (iOS/Android).
  - `apps/admin`: React 19 + Vite + TailwindCSS Admin Dashboard.
  - `apps/api`: Cloudflare Workers + Hono REST API + Durable Objects (Realtime rooms/geocells) + Cloudflare D1 Database (SQLite).
  - `packages/flutter_shared`: Single source of truth for Design Tokens (`AppTokens`), Theme Extensions (`GoTheme`), Basemaps (`MapTiles`), and shared Flutter UI widgets.

---

## 📂 2. Repository Layout & Component Responsibilities

```
godrive/
├── apps/
│   ├── admin/             # React 19 + Vite + Tailwind Admin Panel (Deploy: Cloudflare Pages)
│   ├── api/               # Hono REST API + Durable Objects + D1 (Deploy: Cloudflare Workers)
│   ├── captain/           # Flutter Captain App (inDrive-style bidding, active trip execution, wallet)
│   └── rider/             # Flutter Rider App (Fare proposal 70-150% band, trip booking, captain bids)
├── packages/
│   └── flutter_shared/    # Shared Flutter UI, Tokens (AppTokens, GoTheme), Widgets, Map Tiles
├── migrations/            # SQL Migration Scripts for Cloudflare D1 (0001 to 0007)
└── AGENTS.md              # Instant AI Architecture & Indexing Guide
```

---

## 🎨 3. Design System & Theme Rules (`packages/flutter_shared`)

1. **Brand Identity**:
   - Primary Brand Color: `#4E842D` (GoDrive Green - WCAG AA compliant on white).
   - Night Mode Action / Lime Fill: `#C1F11D` (Black text on lime ≈ 14:1 contrast).
2. **GoTheme Extension**:
   - Access via `final go = GoTheme.of(context);`.
   - Never branch directly on `Theme.of(context).brightness` in screens — use `go.bg`, `go.panel`, `go.surface`, `go.text`, `go.action`, `go.routeLine`, etc.
3. **Typography**:
   - Uses **Cairo** Google Font for Arabic-first geometric sans-serif text.
   - Large money figures use `AppTokens.money(fontSize: ...)`.

---

## 🗄️ 4. Core Database Schema & Migrations (`migrations/`)

The platform uses **Cloudflare D1 (SQLite)**. Core tables include:
- `users`: `id`, `email`, `phone`, `name`, `role` (`rider`|`captain`|`admin`), `password_hash`, `status`, `wallet_balance_piastres`.
- `captains`: `user_id`, `approval_status`, `vehicle_model`, `license_number`, `last_lat`, `last_lng`.
- `trips`: `id`, `rider_id`, `captain_id`, `status` (`requested`|`accepted`|`in_progress`|`completed`|`cancelled`), `pickup_lat/lng`, `dropoff_lat/lng`, `estimated_fare`, `offered_price`, `final_fare`.
- `trip_bids`: `id`, `trip_id`, `captain_id`, `bid_amount`, `counter_fare`, `status`.
- `otp_codes`: `id`, `email`, `code`, `role`, `expires_at`, `consumed_at`.

---

## 🔐 5. Authentication & API Flow (`apps/api`)

- **Admin Login**: Supports `POST /auth/login` with `email` and `password` (PBKDF2 SHA-256 hash).
- **Rider / Captain Login**: Supports `POST /auth/request-otp` & `POST /auth/verify-otp` via WhatsApp/Email or OTP `123456` in testing mode.
- **Trip Lifecycle**:
  1. Rider creates trip via `POST /trips` (optional `offeredPrice`).
  2. Nearby captains receive FCM realtime push / poll `/trips/nearby`.
  3. Captain submits bid via `POST /trips/:id/bids`.
  4. Rider accepts bid via `POST /trips/:id/bids/:bidId/accept`.

---

## ⚡ 6. Guidelines for AI Agents (Devin, HyperAgent, Cursor)

- **Do Not Guess File Paths**: Refer to the tree above or use precise grep/file lookup.
- **Preserve API Contracts**: Ensure any change to `apps/api/src/routes/` is mirrored in client requests.
- **Clean Git Workflow**: Keep `.gitignore` clean. Never commit `build/`, `dist/`, `.wrangler/`, or `node_modules/`.
- **Run Verification Commands**: Always verify builds or lint after refactoring.
