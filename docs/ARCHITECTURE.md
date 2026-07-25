# Synaptic Go — Architecture

## High-level

```text
Flutter Rider ──┐
                ├── HTTPS/WSS ──► api.synapticstudio.tech (Workers)
Flutter Captain ┘                      │
                                       ├── D1 (source of truth)
                                       ├── KV (sessions/cache)
                                       ├── R2 (files)
                                       ├── Queue (async jobs)
                                       ├── TripRoom DO (per trip)
                                       └── GeoCell DO (per geohash cell)

Admin Dashboard ── HTTPS ──► same API (admin routes)
                   static ──► admin.synapticstudio.tech (Pages)
```

## Durable Objects

### TripRoom (`trip:{tripId}`)
- Holds live trip state
- WebSocket fans out captain location to rider
- Status transitions with validation
- Hibernates when trip ends and sockets close

### GeoCell (`cell:{city}:{geohash}`)
- Captains currently online in a geographic cell
- Used for nearest-driver matching
- Heartbeat cleans stale captains

## Data model (D1)

- `users` — all accounts
- `captains` — vehicle, online status, approval
- `trips` — lifecycle + fare + geo points
- `trip_events` — audit trail
- `ratings` — post-trip
- `pricing_rules` — city pricing
- `otp_codes` — short-lived login codes
- `sessions` — optional server-side revoke list

## Trip state machine

```text
searching
  → offered (candidates notified)
  → assigned (captain accepted)
  → arrived (captain at pickup)
  → in_progress (trip started)
  → completed
  → cancelled (from searching/offered/assigned/arrived)
```

## Location policy (cost guardrails)

| Mode | Interval |
|------|----------|
| Captain online idle | heartbeat 30–60s |
| Captain on active trip | every 4–5s OR 25–40m movement |
| Persist path sample to D1 | every 30–60s only |
| After complete | close WS immediately |

## Matching flow

1. Rider creates trip → D1 row `searching`
2. API computes geohash of pickup
3. Query GeoCell DO (+ neighbors) for online captains
4. Sort by haversine distance
5. Offer top N captains
6. First accept wins → TripRoom + `assigned`

## Security

- JWT on protected routes
- Role checks for captain/admin
- CORS allowlist: admin domain + localhost + app origins
- Turnstile later on public auth forms
- Secrets via `wrangler secret` only

## Pricing formula

```text
fare = base_fare
     + distance_km * per_km
     + duration_min * per_min
     + booking_fee
```

Default Egypt city rule is seedable via migration.
