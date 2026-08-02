/**
 * Seeding and auth helpers, shared by the four money-path tests.
 *
 * Everything here writes through the real `env.DB` binding and the real
 * `signAccessToken` from `src/lib/jwt.ts`. Nothing is stubbed: a test that
 * authenticates with a hand-rolled token would not be testing the auth
 * middleware the request actually passes through.
 */
import { env } from "cloudflare:test";
import { signAccessToken } from "../src/lib/jwt";

export const SECRET = "e19-test-signing-secret-not-a-real-key";
export const ISSUER = "synaptic-go";

export type Role = "rider" | "captain" | "admin";

/** Insert a user with a known wallet balance, in both the REAL and piastres columns. */
export async function seedUser(
  id: string,
  role: Role,
  balanceEgp = 0,
): Promise<void> {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO users (id, email, role, status, wallet_balance, wallet_balance_piastres, created_at, updated_at)
     VALUES (?, ?, ?, 'active', ?, ?, datetime('now'), datetime('now'))`,
  )
    .bind(id, `${id}@test.local`, role, balanceEgp, Math.round(balanceEgp * 100))
    .run();
}

/** Insert an approved, online captain row for an existing user. */
export async function seedCaptain(userId: string, online = true): Promise<void> {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO captains (user_id, approval_status, is_online, created_at, updated_at)
     VALUES (?, 'approved', ?, datetime('now'), datetime('now'))`,
  )
    .bind(userId, online ? 1 : 0)
    .run();
}

export type SeedTrip = {
  id: string;
  riderId?: string;
  captainId?: string | null;
  status?: string;
  paymentMethod?: string;
  estimatedFare?: number | null;
  offeredPrice?: number | null;
  acceptedPrice?: number | null;
  finalFare?: number | null;
  commission?: number | null;
};

export async function seedTrip(t: SeedTrip): Promise<void> {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO trips
       (id, rider_id, captain_id, status, city, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
        currency, payment_method, estimated_fare, offered_price, accepted_price, final_fare, commission,
        created_at, updated_at)
     VALUES (?, ?, ?, ?, 'cairo', 30.0444, 31.2357, 30.0561, 31.2394,
             'EGP', ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))`,
  )
    .bind(
      t.id,
      t.riderId ?? "rider_1",
      t.captainId ?? null,
      t.status ?? "in_progress",
      t.paymentMethod ?? "cash",
      t.estimatedFare ?? 100,
      t.offeredPrice ?? null,
      t.acceptedPrice ?? null,
      t.finalFare ?? null,
      t.commission ?? 20,
    )
    .run();
}

/** A real access token for a seeded user, signed the way the API signs them. */
export function tokenFor(id: string, role: Role, email = `${id}@test.local`) {
  return signAccessToken({ id, email, role, name: id }, SECRET, ISSUER);
}

export async function authHeaders(id: string, role: Role): Promise<HeadersInit> {
  return {
    Authorization: `Bearer ${await tokenFor(id, role)}`,
    "Content-Type": "application/json",
  };
}

/** Wallet balance in piastres — the integer column, which is the one that matters. */
export async function balancePiastres(userId: string): Promise<number | null> {
  const row = await env.DB.prepare(
    `SELECT COALESCE(wallet_balance_piastres, CAST(ROUND(COALESCE(wallet_balance,0)*100) AS INTEGER)) AS p
       FROM users WHERE id = ?`,
  )
    .bind(userId)
    .first<{ p: number }>();
  return row?.p ?? null;
}

export async function ledgerRows(idempotencyKey: string) {
  const res = await env.DB.prepare(
    `SELECT id, status, amount, amount_piastres, direction, type
       FROM wallet_transactions WHERE idempotency_key = ?`,
  )
    .bind(idempotencyKey)
    .all();
  return res.results ?? [];
}
