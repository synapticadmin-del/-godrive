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
  return String(Math.floor(100000 + Math.random() * 900000));
}

export async function hashPassword(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function verifyPassword(password: string, hashHex: string): Promise<boolean> {
  const computed = await hashPassword(password);
  return computed === hashHex;
}

export function asBool(v: string | undefined, fallback = false): boolean {
  if (v == null) return fallback;
  return v === "true" || v === "1" || v === "yes";
}
