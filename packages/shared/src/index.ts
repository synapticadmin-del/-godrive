export type UserRole = "rider" | "captain" | "admin";

export type TripStatus =
  | "searching"
  | "offered"
  | "assigned"
  | "arrived"
  | "in_progress"
  | "completed"
  | "cancelled";

export interface LatLng {
  lat: number;
  lng: number;
}

export interface PricingRule {
  city: string;
  currency: string;
  baseFare: number;
  perKm: number;
  perMin: number;
  bookingFee: number;
  minFare: number;
  commissionRate: number;
}

export interface FareEstimate {
  distanceKm: number;
  durationMin: number;
  currency: string;
  baseFare: number;
  distanceFare: number;
  timeFare: number;
  bookingFee: number;
  total: number;
  commission: number;
}

export const TRIP_TRANSITIONS: Record<TripStatus, TripStatus[]> = {
  searching: ["offered", "assigned", "cancelled"],
  offered: ["assigned", "searching", "cancelled"],
  assigned: ["arrived", "cancelled"],
  arrived: ["in_progress", "cancelled"],
  in_progress: ["completed", "cancelled"],
  completed: [],
  cancelled: [],
};

export function canTransition(from: TripStatus, to: TripStatus): boolean {
  return TRIP_TRANSITIONS[from]?.includes(to) ?? false;
}

/** Haversine distance in kilometers */
export function haversineKm(a: LatLng, b: LatLng): number {
  const R = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

/** Rough ETA: assume average city speed 25 km/h */
export function estimateDurationMin(distanceKm: number, avgSpeedKmh = 25): number {
  if (distanceKm <= 0) return 1;
  return Math.max(1, Math.round((distanceKm / avgSpeedKmh) * 60));
}

export interface FareOptions {
  surgeMultiplier?: number;
  vehicleMultiplier?: number;
  discount?: number;
}

export function calculateFare(
  distanceKm: number,
  durationMin: number,
  rule: PricingRule,
  options: FareOptions = {},
): FareEstimate {
  // Guard: clamp non-finite / negative inputs to 0 so a bad distance or
  // duration can never produce a negative fare. Public API is unchanged.
  distanceKm = Number.isFinite(distanceKm) ? Math.max(0, distanceKm) : 0;
  durationMin = Number.isFinite(durationMin) ? Math.max(0, durationMin) : 0;

  const surge = options.surgeMultiplier && options.surgeMultiplier > 0 ? options.surgeMultiplier : 1.0;
  const vehicleMult = options.vehicleMultiplier && options.vehicleMultiplier > 0 ? options.vehicleMultiplier : 1.0;
  const discount = options.discount && options.discount > 0 ? options.discount : 0;

  const distanceFare = distanceKm * rule.perKm * vehicleMult;
  const timeFare = durationMin * rule.perMin * vehicleMult;
  const baseFare = rule.baseFare * vehicleMult;

  const rawUnsurged = baseFare + distanceFare + timeFare + rule.bookingFee;
  const rawSurged = rawUnsurged * surge;
  const finalBeforeDiscount = Math.max(rule.minFare, round2(rawSurged));
  const total = Math.max(0, round2(finalBeforeDiscount - discount));
  const commission = round2(total * rule.commissionRate);

  return {
    distanceKm: round2(distanceKm),
    durationMin,
    currency: rule.currency,
    baseFare: round2(baseFare),
    distanceFare: round2(distanceFare),
    timeFare: round2(timeFare),
    bookingFee: rule.bookingFee,
    total,
    commission,
  };
}

export function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * Encode lat/lng to geohash (precision 1–12).
 * Used for GeoCell matching.
 */
export function encodeGeohash(lat: number, lng: number, precision = 6): string {
  const base32 = "0123456789bcdefghjkmnpqrstuvwxyz";
  let idx = 0;
  let bit = 0;
  let evenBit = true;
  let geohash = "";

  let latMin = -90,
    latMax = 90;
  let lngMin = -180,
    lngMax = 180;

  while (geohash.length < precision) {
    if (evenBit) {
      const mid = (lngMin + lngMax) / 2;
      if (lng >= mid) {
        idx = idx * 2 + 1;
        lngMin = mid;
      } else {
        idx = idx * 2;
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        idx = idx * 2 + 1;
        latMin = mid;
      } else {
        idx = idx * 2;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    if (++bit === 5) {
      geohash += base32[idx];
      bit = 0;
      idx = 0;
    }
  }
  return geohash;
}

/**
 * Height (lat span) and width (lng span) of a geohash cell at [precision],
 * in degrees. Derived from the bit-interleaving scheme itself, so it holds at
 * any latitude and any precision — no trig needed.
 *
 * Nearby-captain search uses this to probe cell boundaries rather than a
 * fixed degree step: a fixed step that is smaller than the cell can miss a
 * neighbour cell entirely, which is exactly the bug the neighbourhood search
 * was meant to kill.
 */
export function geohashCellSpan(precision = 6): { latSpan: number; lngSpan: number } {
  let evenBit = true;
  let latBits = 0;
  let lngBits = 0;
  for (let i = 0; i < precision * 5; i++) {
    if (evenBit) lngBits++;
    else latBits++;
    evenBit = !evenBit;
  }
  return { latSpan: 180 / 2 ** latBits, lngSpan: 360 / 2 ** lngBits };
}

export const DEFAULT_PRICING: PricingRule = {
  city: "cairo",
  currency: "EGP",
  baseFare: 12,
  perKm: 4.5,
  perMin: 0.5,
  bookingFee: 3,
  minFare: 25,
  commissionRate: 0.2,
};
