import { SignJWT, jwtVerify } from "jose";
import type { AuthUser } from "./types";

function secretKey(secret: string) {
  return new TextEncoder().encode(secret);
}

const ACCESS_TTL = "15m";
const REFRESH_TTL = "30d";

export async function signAccessToken(
  user: AuthUser,
  secret: string,
  issuer: string,
): Promise<string> {
  return new SignJWT({
    email: user.email,
    role: user.role,
    name: user.name,
    typ: "access",
  })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(user.id)
    .setIssuer(issuer)
    .setIssuedAt()
    .setExpirationTime(ACCESS_TTL)
    .sign(secretKey(secret));
}

/** @deprecated use signAccessToken — kept for backwards compat during rollout */
export async function signToken(
  user: AuthUser,
  secret: string,
  issuer: string,
  expiresIn = ACCESS_TTL,
): Promise<string> {
  return new SignJWT({
    email: user.email,
    role: user.role,
    name: user.name,
    typ: "access",
  })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(user.id)
    .setIssuer(issuer)
    .setIssuedAt()
    .setExpirationTime(expiresIn)
    .sign(secretKey(secret));
}

export async function signRefreshToken(
  user: AuthUser,
  secret: string,
  issuer: string,
  jti: string,
): Promise<string> {
  return new SignJWT({
    email: user.email,
    role: user.role,
    typ: "refresh",
  })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(user.id)
    .setIssuer(issuer)
    .setJti(jti)
    .setIssuedAt()
    .setExpirationTime(REFRESH_TTL)
    .sign(secretKey(secret));
}

export async function verifyToken(
  token: string,
  secret: string,
  issuer: string,
): Promise<AuthUser & { typ?: string; jti?: string }> {
  const { payload } = await jwtVerify(token, secretKey(secret), { issuer });
  if (!payload.sub || typeof payload.email !== "string" || typeof payload.role !== "string") {
    throw new Error("Invalid token payload");
  }
  return {
    id: payload.sub,
    email: payload.email,
    role: payload.role as AuthUser["role"],
    name: typeof payload.name === "string" ? payload.name : null,
    typ: typeof payload.typ === "string" ? payload.typ : undefined,
    jti: typeof payload.jti === "string" ? payload.jti : undefined,
  };
}

export async function hashToken(token: string): Promise<string> {
  const data = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export { ACCESS_TTL, REFRESH_TTL };
