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
Requires auth. Returns current user (+ captain profile if any).

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

## Admin

### `GET /admin/stats`
### `GET /admin/captains`
### `POST /admin/captains/:id/approve`
### `POST /admin/captains/:id/suspend`
### `GET /admin/trips`
### `GET /admin/pricing`
### `PUT /admin/pricing/:city`
