# Improvements Log — Synaptic Go

## v0.3.0 (Batch 1 + 2 + Admin pages)

### API Security & Core
- ✅ Zod validation on all major endpoints (`src/lib/schemas.ts`)
- ✅ KV rate limiting: global 120/min, OTP 5/min, create-trip 10/min, location 30/min
- ✅ JWT access tokens (15m) + refresh tokens (30d) with rotation
- ✅ Endpoints: `POST /auth/refresh`, `POST /auth/logout`
- ✅ Structured error codes: `VALIDATION_ERROR`, `RATE_LIMITED`, `INVALID_TOKEN`, …

### Database (migration 0002)
- ✅ `refresh_tokens`, `trip_path_points`, `driver_documents`, `audit_log`
- ✅ `promo_codes`, `trip_promo`, `saved_places`, `vehicle_types`
- ✅ `payment_methods`, `referrals`, `user_credits`
- ✅ trips columns: `promo_code`, `discount`, `vehicle_type_id`, `route_geometry`

### Routing & Geocoding
- ✅ OSRM real driving routes (`src/lib/routing.ts`) with haversine fallback
- ✅ Reverse geocode + search via Nominatim, KV cache 30d/7d
- ✅ `GET /geocode/reverse`, `GET /geocode/search`

### Realtime
- ✅ Rider: WebSocket trip room (`lib/services/trip_ws.dart`) replaces 4s polling
- ✅ Captain: offers inbox WS (`CaptainInbox` DO + `offers_ws.dart`)
- ✅ Trip path sampling every 30s on captain location
- ✅ `GET /trips/:id/path`
- ✅ Push `trip.offer` to nearby captains on trip create

### Admin
- ✅ Live map page (Leaflet CDN)
- ✅ Audit log page
- ✅ Analytics page (daily GMV bars, top captains, completion rate)
- ✅ Settings page (promo codes CRUD)

### Promos
- ✅ `POST /promos/validate`, `GET/POST /promos`, deactivate

## v0.4.0 (Full Features, Screens & Verification Integration)

### API Backend (`apps/api`)
- ✅ User profile & saved places: `GET/PATCH /user/profile`, `GET/POST/DELETE /user/saved-places`
- ✅ Driver document verification: `GET/POST /captain/documents`, `GET /admin/documents`, `POST /admin/documents/:id/review`
- ✅ Payment integration: `POST /payments/paymob/intention`, `POST /payments/paymob/webhook`
- ✅ Captain earnings & history: `GET /captain/earnings`

### Admin Dashboard (`apps/admin`)
- ✅ Driver Document Verification page (`CaptainVerificationPage.tsx`) for reviewing licenses & IDs
- ✅ Sidebar navigation update with verification badge
- ✅ Enhanced UI contrast & accessibility standards (WCAG AAA)

### Rider Flutter App (`apps/rider`)
- ✅ Complete Profile Screen (`profile_screen.dart`) with credit balance & logout
- ✅ Saved Places Screen (`saved_places_screen.dart`) for home, work, and favorites
- ✅ Trip History Screen (`history_screen.dart`) with status badges & fare details
- ✅ Promo Code application sheet & validation UI

### Captain Flutter App (`apps/captain`)
- ✅ Document Upload Screen (`document_upload_screen.dart`) for license, ID, and vehicle registration
- ✅ Earnings & Stats Screen (`earnings_screen.dart`) with net earnings, platform commission & payout dates
- ✅ Quick action links on home screen & clickable approval verification banner

## URLs
- API: https://api.synapticstudio.tech
- API fallback: https://synaptic-go-api.lolelarap.workers.dev
- Admin: https://synaptic-go-admin.pages.dev

