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
