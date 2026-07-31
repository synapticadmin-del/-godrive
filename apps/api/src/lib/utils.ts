export function jsonError(message: string, status = 400, extra?: Record<string, unknown>) {
  return Response.json({ error: message, ...extra }, { status });
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function id(prefix = ""): string {
  const raw = crypto.randomUUID().replace(/-/g, "");
  return prefix ? `${prefix}_${raw}` : raw;
}

export function otpCode(): string {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  const num = 100000 + (buf[0] % 900000);
  return String(num);
}

export async function hashPassword(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const saltHex = Array.from(salt).map((b) => b.toString(16).padStart(2, "0")).join("");

  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    encoder.encode(password),
    "PBKDF2",
    false,
    ["deriveBits"]
  );

  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      salt: salt,
      iterations: 100000,
      hash: "SHA-256",
    },
    keyMaterial,
    256
  );

  const hashHex = Array.from(new Uint8Array(derivedBits)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `$pbkdf2$100000$${saltHex}$${hashHex}`;
}

/**
 * Returns true when the stored hash is a legacy unsalted SHA-256 hex digest
 * rather than the current PBKDF2 format ($pbkdf2$iterations$salt$hash).
 * Used by /auth/login to transparently upgrade legacy hashes after a
 * successful password verification.
 */
export function isLegacyHash(hash: string): boolean {
  return !hash.startsWith("$pbkdf2$");
}

export async function verifyPassword(password: string, storedHash: string): Promise<boolean> {
  if (storedHash.startsWith("$pbkdf2$")) {
    const parts = storedHash.split("$");
    if (parts.length !== 5) return false;
    const iterations = parseInt(parts[2], 10);
    const saltHex = parts[3];
    const targetHashHex = parts[4];

    const salt = new Uint8Array(saltHex.match(/.{1,2}/g)?.map((byte) => parseInt(byte, 16)) ?? []);
    const encoder = new TextEncoder();

    const keyMaterial = await crypto.subtle.importKey(
      "raw",
      encoder.encode(password),
      "PBKDF2",
      false,
      ["deriveBits"]
    );

    const derivedBits = await crypto.subtle.deriveBits(
      {
        name: "PBKDF2",
        salt: salt,
        iterations: iterations,
        hash: "SHA-256",
      },
      keyMaterial,
      256
    );

    const computedHashHex = Array.from(new Uint8Array(derivedBits)).map((b) => b.toString(16).padStart(2, "0")).join("");
    return computedHashHex === targetHashHex;
  }

  // Fallback legacy SHA-256 comparison for smooth migration
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const legacyHashHex = Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return legacyHashHex === storedHash;
}

export function asBool(v: string | undefined, fallback = false): boolean {
  if (v == null) return fallback;
  return v === "true" || v === "1" || v === "yes";
}

/* ------------------------------------------------------------------ */
/* Captain search radius                                               */
/* ------------------------------------------------------------------ */

/**
 * Great-circle distance in km, rounded to 100m.
 *
 * Lives here rather than inline in a route because three separate surfaces
 * now have to agree on "is this trip inside the captain's radius": the
 * browsable queue, the pushed offers inbox, and the dispatch fanout. Two
 * copies of this formula would eventually disagree by a rounding step and
 * put a trip in one list but not the other.
 */
export function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lon2 - lon1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) *
      Math.cos(lat2 * (Math.PI / 180)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(R * c * 10) / 10;
}

/** Radius applied to captains whose row predates migration 0018. */
export const DEFAULT_SEARCH_RADIUS_KM = 15;

/** Bounds accepted from a client. Anything outside is clamped, not rejected. */
export const MIN_SEARCH_RADIUS_KM = 1;
export const MAX_SEARCH_RADIUS_KM = 100;

/**
 * Resolve the radius to apply for a captain: an explicit request value wins,
 * then the stored column, then the default. Always returns a finite number
 * inside [MIN, MAX] so it can be compared against a distance without further
 * guarding — an unguarded NaN here would silently pass every filter and put
 * the far-away trips straight back in the captain's inbox.
 */
export function resolveSearchRadiusKm(...candidates: Array<number | string | null | undefined>): number {
  for (const candidate of candidates) {
    if (candidate == null || candidate === "") continue;
    const n = Number(candidate);
    if (!Number.isFinite(n) || n <= 0) continue;
    return Math.min(MAX_SEARCH_RADIUS_KM, Math.max(MIN_SEARCH_RADIUS_KM, n));
  }
  return DEFAULT_SEARCH_RADIUS_KM;
}

const DATE_ONLY_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Parse a positive integer query parameter, clamped to [min, max].
 *
 * Number("abc") is NaN, and Math.min(NaN, 500) is NaN, so an unguarded
 * Number(c.req.query(...)) binds NaN straight into a SQL LIMIT. This rejects
 * anything that is not a finite positive integer and falls back to a default.
 */
export function intParam(
  raw: string | undefined,
  fallback: number,
  min: number,
  max: number,
): number {
  if (raw == null || raw === "") return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  const i = Math.trunc(n);
  if (i < min) return min;
  if (i > max) return max;
  return i;
}

/**
 * Compute the immediately-preceding, equal-length window for [from, to].
 *
 * Used by /admin/analytics to produce a real "vs previous period" comparison.
 * The window must be the same length as the selected one and must end exactly
 * where it begins, or the two are not comparable.
 *
 * Date-only bounds ("2026-07-25") include the whole end day, so the effective
 * span is (to + 1 day) - from. A full timestamp is exact and used as-is.
 *
 * Returns null for an inverted or unparseable range, so callers can omit the
 * comparison rather than render a bogus one.
 *
 * Note this is "previous EQUAL-LENGTH period", not "previous calendar month":
 * the 31-day window before 2026-07-01 starts 2026-05-31, because June has only
 * 30 days. That is intentional and is covered by verify/period.js.
 */
export function previousPeriod(
  from: string,
  to: string,
): { prevFrom: string; prevToExclusive: string; spanDays: number } | null {
  const fromIsDateOnly = DATE_ONLY_RE.test(from);
  const toIsDateOnly = DATE_ONLY_RE.test(to);

  const fromMs = Date.parse(fromIsDateOnly ? `${from}T00:00:00.000Z` : from);
  const toMsRaw = Date.parse(toIsDateOnly ? `${to}T00:00:00.000Z` : to);
  if (Number.isNaN(fromMs) || Number.isNaN(toMsRaw)) return null;

  const toMsExclusive = toIsDateOnly ? toMsRaw + 864e5 : toMsRaw;
  const spanMs = toMsExclusive - fromMs;
  if (spanMs <= 0) return null;

  const prevFromMs = fromMs - spanMs;
  const bothDateOnly = fromIsDateOnly && toIsDateOnly;

  return {
    prevFrom: bothDateOnly
      ? new Date(prevFromMs).toISOString().slice(0, 10)
      : new Date(prevFromMs).toISOString(),
    // Exclusive: the previous window ends exactly where the current one starts.
    prevToExclusive: new Date(fromMs).toISOString(),
    spanDays: spanMs / 864e5,
  };
}

/**
 * Percentage change from `previous` to `current`, rounded to one decimal.
 *
 * Returns null when the baseline is zero and the current value is not: growth
 * from nothing is not "infinity percent", and callers should render that case
 * as "new" rather than fabricating a figure. Zero-to-zero is a genuine 0.
 */
export function pctDelta(
  current: number | null | undefined,
  previous: number | null | undefined,
): number | null {
  const cur = Number(current) || 0;
  const prev = Number(previous) || 0;
  if (prev === 0) return cur === 0 ? 0 : null;
  return Math.round(((cur - prev) / prev) * 1000) / 10;
}
