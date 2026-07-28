import React, { createContext, useContext, useMemo, useState } from "react";
import { api } from "./api";

type User = {
  id: string;
  email: string;
  name: string | null;
  role: string;
};

type AuthState = {
  token: string | null;
  user: User | null;
  loginWithPassword: (email: string, password: string) => Promise<void>;
  requestOtp: (email: string) => Promise<{ devCode?: string; message: string }>;
  verifyOtp: (email: string, code: string) => Promise<void>;
  logout: () => void;
};

const AuthContext = createContext<AuthState | null>(null);
const TOKEN_KEY = "sg_admin_token";
const USER_KEY = "sg_admin_user";
const REFRESH_KEY = "sg_admin_refresh";

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [token, setToken] = useState<string | null>(() => localStorage.getItem(TOKEN_KEY));
  const [user, setUser] = useState<User | null>(() => {
    const raw = localStorage.getItem(USER_KEY);
    return raw ? (JSON.parse(raw) as User) : null;
  });

  const value = useMemo<AuthState>(
    () => ({
      token,
      user,
      async loginWithPassword(email: string, password: string) {
        const res = await api<{ token?: string; accessToken?: string; refreshToken?: string; user: User }>("/auth/login", {
          method: "POST",
          body: JSON.stringify({ email, password }),
        });
        if (res.user.role !== "admin") {
          throw new Error("هذا الحساب ليس أدمن");
        }
        const tok = res.accessToken || res.token;
        if (!tok) throw new Error("لم يتم إرجاع توكن الدخول");
        localStorage.setItem(TOKEN_KEY, tok);
        if (res.refreshToken) localStorage.setItem(REFRESH_KEY, res.refreshToken);
        localStorage.setItem(USER_KEY, JSON.stringify(res.user));
        setToken(tok);
        setUser(res.user);
      },
      async requestOtp(email: string) {
        return api<{ devCode?: string; message: string }>("/auth/request-otp", {
          method: "POST",
          body: JSON.stringify({ email, role: "admin", name: "Admin" }),
        });
      },
      async verifyOtp(email: string, code: string) {
        const res = await api<{ token?: string; accessToken?: string; refreshToken?: string; user: User }>("/auth/verify-otp", {
          method: "POST",
          body: JSON.stringify({ email, code }),
        });
        if (res.user.role !== "admin") {
          throw new Error("هذا الحساب ليس أدمن");
        }
        const tok = res.accessToken || res.token;
        if (!tok) throw new Error("No token returned");
        localStorage.setItem(TOKEN_KEY, tok);
        if (res.refreshToken) localStorage.setItem(REFRESH_KEY, res.refreshToken);
        localStorage.setItem(USER_KEY, JSON.stringify(res.user));
        setToken(tok);
        setUser(res.user);
      },
      logout() {
        localStorage.removeItem(TOKEN_KEY);
        localStorage.removeItem(USER_KEY);
        localStorage.removeItem(REFRESH_KEY);
        setToken(null);
        setUser(null);
      },
    }),
    [token, user],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth outside provider");
  return ctx;
}
