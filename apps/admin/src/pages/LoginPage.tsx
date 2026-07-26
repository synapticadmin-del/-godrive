import { FormEvent, useState } from "react";
import { Navigate } from "react-router-dom";
import { useAuth } from "../lib/auth";
import { getApiUrl } from "../lib/api";
import { ArrowLeft, Mail, Shield, Loader2 } from "lucide-react";
import GoDriveLogo from "../components/common/GoDriveLogo";

export default function LoginPage() {
  const { token, loginWithPassword } = useAuth();
  const [email, setEmail] = useState("admin@synapticstudio.tech");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  if (token) return <Navigate to="/" replace />;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      await loginWithPassword(email.trim().toLowerCase(), password);
    } catch (err) {
      setError(err instanceof Error ? err.message : "بيانات الدخول غير صحيحة");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-bg-primary" dir="rtl">
      {/* Background decoration with GoDrive brand green */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-40 -right-40 w-96 h-96 rounded-full bg-primary-500/10 blur-3xl" />
        <div className="absolute -bottom-40 -left-40 w-96 h-96 rounded-full bg-primary-500/5 blur-3xl" />
      </div>

      <div className="relative w-full max-w-md">
        {/* Brand */}
        <div className="text-center mb-8 flex flex-col items-center">
          <GoDriveLogo size="xl" className="mb-2" />
          <p className="text-sm font-medium text-text-tertiary mt-1">لوحة تحكم الإدارة</p>
        </div>

        {/* Card */}
        <div className="bg-surface-primary border border-border-primary rounded-2xl p-6 shadow-xl">
          {/* API indicator */}
          <div className="mb-4 px-3 py-2 bg-surface-secondary rounded-lg flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-success-main animate-pulse" />
            <span className="text-xs text-text-tertiary truncate">{getApiUrl()}</span>
          </div>

          {/* Error */}
          {error && (
            <div className="mb-4 p-3 bg-error-main/10 border border-error-main/30 rounded-lg flex items-center gap-2 text-error-main text-sm animate-fade-in">
              <Shield className="w-4 h-4 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {/* Email & Password Form */}
          <form onSubmit={onSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-text-secondary mb-1.5">البريد الإلكتروني</label>
              <div className="relative">
                <Mail className="absolute right-3 top-1/2 -translate-y-1/2 w-5 h-5 text-text-tertiary pointer-events-none" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  placeholder="admin@synapticstudio.tech"
                  className="input pr-10"
                  autoComplete="email"
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-text-secondary mb-1.5">كلمة المرور</label>
              <div className="relative">
                <Shield className="absolute right-3 top-1/2 -translate-y-1/2 w-5 h-5 text-text-tertiary pointer-events-none" />
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  placeholder="••••••••"
                  className="input pr-10"
                  autoComplete="current-password"
                />
              </div>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed mt-2"
            >
              {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : "تسجيل الدخول"}
            </button>
          </form>
        </div>

        <p className="text-center mt-6 text-xs text-text-tertiary">
          © 2026 GoDrive · جميع الحقوق محفوظة
        </p>
      </div>
    </div>
  );
}