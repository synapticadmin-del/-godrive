import type { UserRole } from "@synaptic-go/shared";

export type AuthUser = {
  id: string;
  email: string;
  role: UserRole;
  name: string | null;
};

export type DbUser = {
  id: string;
  email: string;
  password_hash: string | null;
  name: string | null;
  phone: string | null;
  role: UserRole;
  status: string;
  wallet_balance?: number;
  wallet_updated_at?: string | null;
  created_at: string;
};

export type DbCaptain = {
  user_id: string;
  vehicle_make: string | null;
  vehicle_model: string | null;
  vehicle_plate: string | null;
  vehicle_color: string | null;
  license_number: string | null;
  approval_status: string;
  is_online: number;
  last_lat: number | null;
  last_lng: number | null;
  last_seen_at: string | null;
  rating_avg: number;
  rating_count: number;
};

export type DbTrip = {
  id: string;
  rider_id: string;
  captain_id: string | null;
  status: string;
  city: string;
  pickup_lat: number;
  pickup_lng: number;
  pickup_address: string | null;
  dropoff_lat: number;
  dropoff_lng: number;
  dropoff_address: string | null;
  distance_km: number | null;
  duration_min: number | null;
  currency: string;
  estimated_fare: number | null;
  final_fare: number | null;
  commission: number | null;
  payment_method: string;
  cancel_reason: string | null;
  captain_lat: number | null;
  captain_lng: number | null;
  promo_code?: string | null;
  discount?: number | null;
  vehicle_type_id?: string | null;
  route_geometry?: string | null;
  scheduled_for?: string | null;
  schedule_status?: string | null;
  waypoints?: string | null;
  surge_multiplier?: number;
  company_id?: string | null;
  cost_center?: string | null;
  billed_to_company?: number;
  created_at: string;
  assigned_at: string | null;
  arrived_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
  updated_at: string;
};

export type DbPricing = {
  city: string;
  currency: string;
  base_fare: number;
  per_km: number;
  per_min: number;
  booking_fee: number;
  min_fare: number;
  commission_rate: number;
};
