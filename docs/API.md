# Synaptic Go — API Reference

Base URL (prod): `https://api.synapticstudio.tech`  
Base URL (local): `http://127.0.0.1:8787`

All JSON. Auth header: `Authorization: Bearer <token>`

## Health

### `GET /health`
```json
{ "ok": true, "service": "synaptic-go-api", "version": "0.1.0" }
```

## Auth

### `POST /auth/request-otp`
```json
{ "email": "user@example.com", "role": "rider" }
```
Roles: `rider` | `captain` | `admin`

### `POST /auth/verify-otp`
```json
{ "email": "user@example.com", "code": "123456" }
```
Returns: `{ token, user }`

### `GET /auth/me`
Requires auth. Returns current user (+ captain profile if any). The captain
object carries `search_radius_km` — the reach the apps and dispatch both
filter on.

## Captain

### `POST /captain/profile`
Create/update captain profile (vehicle info).

### `POST /captain/online`
```json
{ "lat": 30.0444, "lng": 31.2357, "online": true }
```

### `POST /captain/location`
```json
{ "lat": 30.05, "lng": 31.24, "heading": 90, "tripId": "..." }
```

### `POST /captain/search-radius`
```json
{ "radiusKm": 5 }
```
How far out this captain wants work. Accepts 1–100 km (values outside the
range are clamped, not rejected) and returns `{ ok, searchRadiusKm }`.

This is the **single** radius the whole system honours:

- `GET /captain/nearby-requests` uses it when no `?radius=` is supplied
- `GET /captain/offers` filters the pushed queue by it
- `POST /trips` dispatch skips captains whose radius excludes the pickup, so
  an out-of-range trip generates neither an inbox card nor an FCM push

### `GET /captain/nearby-requests?radius=&lat=&lng=`
Open requests in the captain's city, filtered to `radius` km from the captain
(an explicit `?radius=` wins, otherwise the stored `search_radius_km`,
otherwise 15). Returns `{ requests, searchRadiusKm, captainLocation }`; each
request carries `captain_to_pickup_km`.

### `GET /captain/offers`
The pushed offer queue. City-scoped **and** radius-scoped, measured from the
captain's last known position; rows carry `captain_to_pickup_km`. Returns
`{ trips, searchRadiusKm, captainLocation }`. Empty while offline.

### `GET /captain/earnings?from=&to=`
Simple completed-trips summary.

## Trips

### `POST /trips/estimate`
```json
{
  "pickupLat": 30.04, "pickupLng": 31.23,
  "dropoffLat": 30.06, "dropoffLng": 31.25
}
```

### `POST /trips`
Create trip (rider). Same body + optional addresses.

### `GET /trips/:id`
Trip details.

### `GET /trips`
List my trips.

### `POST /trips/:id/cancel`
```json
{ "reason": "changed mind" }
```

### `POST /trips/:id/accept` (captain)
### `POST /trips/:id/arrived` (captain)
### `POST /trips/:id/start` (captain)
### `POST /trips/:id/complete` (captain)

### `POST /trips/:id/bid` (captain)
```json
{ "counterPrice": 65 }
```
A price edit. Does **not** assign the trip — the rider still chooses.

### `POST /trips/:id/accept-bid` (rider)
```json
{ "bidId": "bid_..." }
```
Assigns the trip at the bid price. The winning captain is notified on three
channels: the trip room broadcast, an FCM push, and a `trip.assigned` event on
their offers inbox socket — the last is what moves the captain app straight to
the map to drive the trip.

### `POST /trips/:id/rate`
```json
{ "score": 5, "comment": "great" }
```

## Realtime

### `GET /ws/trips/:id`
WebSocket upgrade. Send auth as query `?token=` or first message.

Server events:
- `trip.updated`
- `location.captain`
- `trip.offer` (captain)
- `error`

### `GET /ws/captain/offers`
The captain's own inbox. Auth as the first message
(`{"type":"auth","token":"<jwt>"}`).

Server events:
- `trip.offer` — a new request inside the captain's radius
- `offer.withdrawn` / `trip.cancelled` — the request is gone
- `trip.assigned` — this captain won the trip (`reason: "bid.accepted"` when
  the rider accepted a price edit)

## Admin

### `GET /admin/stats`
### `GET /admin/captains`
### `POST /admin/captains/:id/approve`
### `POST /admin/captains/:id/suspend`
### `GET /admin/trips`
### `GET /admin/pricing`
### `PUT /admin/pricing/:city`
