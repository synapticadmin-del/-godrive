import type { PricingRule } from "@synaptic-go/shared";
import {
  calculateFare,
  encodeGeohash,
  estimateDurationMin,
  haversineKm,
} from "@synaptic-go/shared";
import type { DbPricing } from "./types";

export function pricingFromRow(row: DbPricing): PricingRule {
  return {
    city: row.city,
    currency: row.currency,
    baseFare: row.base_fare,
    perKm: row.per_km,
    perMin: row.per_min,
    bookingFee: row.booking_fee,
    minFare: row.min_fare,
    commissionRate: row.commission_rate,
  };
}

export function estimateTripFare(
  pickup: { lat: number; lng: number },
  dropoff: { lat: number; lng: number },
  rule: PricingRule,
) {
  const distanceKm = haversineKm(pickup, dropoff);
  // road factor for city routes (not straight line)
  const roadDistance = distanceKm * 1.35;
  const durationMin = estimateDurationMin(roadDistance, 22);
  const fare = calculateFare(roadDistance, durationMin, rule);
  return { distanceKm: fare.distanceKm, durationMin, fare };
}

export function cellKey(city: string, lat: number, lng: number, precision = 5): string {
  return `${city}:${encodeGeohash(lat, lng, precision)}`;
}
