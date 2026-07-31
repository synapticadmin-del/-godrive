# Dynamic Bidding & Price Negotiation Model (نظام التفاوض والمزايدة)

## 1. Overview (نظرة عامة)
The GoDrive platform implements a **Dynamic Bidding Model** (InDrive style) enabling interactive fare negotiation between Riders and Captains:
- **Rider**: Proposes an initial fare price (`offered_price`) when creating a trip request.
- **Captain**: Views nearby ride requests in a real-time feed with pickup distance, trip distance, rider name, rider photo, and offered price. Captain can instantly accept or submit a counter-offer (`counter_price`).
- **Rider**: Reviews incoming driver bids in real-time, selects the best offer based on rating/price/vehicle, and locks the agreement.
- **Admin**: Monitors active bids, agreed prices, and platform commission.

---

## 2. Database Schema (`migrations/0004_bidding_system.sql`)

### Table: `trip_bids`
| Column | Type | Description |
|---|---|---|
| `id` | TEXT PRIMARY KEY | Unique bid identifier (`bid_xxx`) |
| `trip_id` | TEXT FK | Reference to `trips.id` |
| `captain_id` | TEXT FK | Reference to `users.id` (Captain) |
| `counter_price` | REAL | Proposed price by captain (in EGP) |
| `status` | TEXT | `pending`, `accepted`, `rejected`, `cancelled` |
| `created_at` | TIMESTAMP | ISO creation timestamp |

### Table: `trips` (Added Columns)
| Column | Type | Description |
|---|---|---|
| `offered_price` | REAL | Initial fare offered by rider |
| `accepted_price` | REAL | Final agreed fare between rider & captain |
| `bidding_mode` | INTEGER | `1` if open for driver bids, `0` otherwise |

---

## 3. API Endpoints Reference

### 1. `POST /trips/` (Rider Create Trip with Custom Fare)
- **Header**: `Authorization: Bearer <rider_token>`
- **Payload**:
```json
{
  "pickupLat": 30.0444,
  "pickupLng": 31.2357,
  "pickupAddress": "المعادي، القاهرة",
  "dropoffLat": 30.0123,
  "dropoffLng": 31.4321,
  "dropoffAddress": "التجمع الخامس، القاهرة",
  "offeredPrice": 120.0,
  "paymentMethod": "cash"
}
```

### 2. `GET /captain/nearby-requests` (Captain Live Feed)
- **Header**: `Authorization: Bearer <captain_token>`
- **Query Params**: `lat`, `lng`, `radius=15`
- **Response**:
```json
{
  "requests": [
    {
      "id": "trip_xxx",
      "rider_id": "usr_xxx",
      "rider_name": "محمد أحمد",
      "rider_avatar": "https://api.dicebear.com/7.x/bottts/svg?seed=usr_xxx",
      "pickup_address": "المعادي، القاهرة",
      "dropoff_address": "التجمع الخامس، القاهرة",
      "distance_km": 14.2,
      "offered_price": 120.0,
      "captain_to_pickup_km": 1.4,
      "created_at": "2026-07-25T06:40:00Z"
    }
  ]
}
```

### 3. `POST /trips/:id/bid` (Captain Counter-Offer or Instant Accept)
- **Header**: `Authorization: Bearer <captain_token>`
- **Payload**:
```json
{
  "counterPrice": 135.0
}
```

### 4. `GET /trips/:id/bids` (Rider Fetch Active Bids)
- **Header**: `Authorization: Bearer <rider_token>`
- **Response**: List of incoming captain bids with ratings, car model, plate, and proposed price.
```json
{
  "bids": [
    {
      "id": "bid_xxx",
      "trip_id": "trip_xxx",
      "captain_id": "usr_xxx",
      "counter_price": 135.0,
      "status": "pending",
      "created_at": "2026-07-31T06:40:00Z",
      "captain_name": "محمود سيد",
      "captain_phone": "+201000000000",
      "captain_avatar_url": "/user/avatar/usr_xxx/a1b2c3.jpg",
      "vehicle_make": "Hyundai",
      "vehicle_model": "Elantra",
      "vehicle_plate": "ط ن ر 4821",
      "vehicle_color": "أبيض",
      "rating_avg": 4.87,
      "rating_count": 312,
      "captain_lat": 30.0511,
      "captain_lng": 31.2299,
      "captain_seen_at": "2026-07-31T06:39:57Z",
      "eta_min": 6,
      "eta_source": "osrm"
    }
  ]
}
```

**`captain_avatar_url`** is the API-relative path held in `users.avatar_url`, the
same shape `GET /auth/me` returns. Prefix it with the API base URL and send the
bearer token — `GET /user/avatar/*` is authenticated, and is deliberately readable
by any signed-in user so a rider can see who is coming to collect them. `null`
when the captain has set no photo; clients fall back to initials.

**`eta_min`** is driving minutes from the captain's last known position to the
pickup, over the street network. Every bid on a trip is resolved in a single OSRM
`table` request, and the answer is cached in KV for 60s per trip/captain pair —
the rider's panel polls this endpoint every 5s, so without the cache a single
negotiation would fire twelve OSRM requests a minute for a number that barely
moves.

**`eta_source`** is `osrm` for a routed answer, or `haversine` when OSRM could not
be reached (or could not snap that particular captain to a road). Clients should
mark a `haversine` value as approximate rather than presenting it as a real
arrival time.

Both ETA fields are **absent** when the trip has no pickup coordinates, when the
captain has no stored position, or when that position is more than 10 minutes
stale — an ETA derived from an abandoned GPS fix is fiction, not an estimate.

### 5. `POST /trips/:id/accept-bid` (Rider Accept Captain Bid)
- **Header**: `Authorization: Bearer <rider_token>`
- **Payload**:
```json
{
  "bidId": "bid_xxx"
}
```

---

## 4. Frontend & Mobile Integration Status

1. **Captain App (`apps/captain`)**:
   - Model: `lib/models/ride_request_model.dart`
   - Screen: `lib/screens/home/nearby_requests_screen.dart` (Includes quick increment chips `+5`, `+10`, `+20`, `+30`, custom price input, and instant accept).
2. **Rider App (`apps/rider`)**:
   - Sheet: `lib/screens/ride/captain_bids_sheet.dart` (Real-time captain bids list & accept button).
3. **Admin Dashboard (`apps/admin`)**:
   - Page: `src/pages/TripsPage.tsx` (Audits offered prices vs accepted prices).
