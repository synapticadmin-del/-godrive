import { Suspense, lazy } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { useAuth } from './lib/auth';
import { canAccess, firstAllowedPath } from './lib/staff';
import Layout from './components/layout/Layout';
import ErrorBoundary from './components/ui/ErrorBoundary';

// Route-level code splitting: each page is fetched on first navigation rather
// than bundled into the initial chunk, so the login screen and first paint
// stay lean. All pages use default exports, so a plain lazy(() => import())
// is enough.
const LoginPage = lazy(() => import('./pages/LoginPage'));
const DashboardPage = lazy(() => import('./pages/DashboardPage'));
const CaptainsPage = lazy(() => import('./pages/CaptainsPage'));
const TripsPage = lazy(() => import('./pages/TripsPage'));
const PricingPage = lazy(() => import('./pages/PricingPage'));
const UsersPage = lazy(() => import('./pages/UsersPage'));
const LiveMapPage = lazy(() => import('./pages/LiveMapPage'));
const AuditLogPage = lazy(() => import('./pages/AuditLogPage'));
const AnalyticsPage = lazy(() => import('./pages/AnalyticsPage'));
const SettingsPage = lazy(() => import('./pages/SettingsPage'));
const CaptainVerificationPage = lazy(() => import('./pages/CaptainVerificationPage'));
// E14 — the operator console's two queues. Both are lazy like every other page.
const SafetyPage = lazy(() => import('./pages/SafetyPage'));
const PayoutsPage = lazy(() => import('./pages/PayoutsPage'));
// Migration 0024 RBAC — the owner's staff/role management console.
const StaffPage = lazy(() => import('./pages/StaffPage'));

function PageFallback() {
  return (
    <div className="min-h-[40vh] flex items-center justify-center" role="status" aria-label="جاري التحميل">
      <Loader2 className="w-8 h-8 text-primary-500 animate-spin" />
    </div>
  );
}

function ProtectedLayout() {
  const { token } = useAuth();
  if (!token) return <Navigate to="/login" replace />;
  return <Layout />;
}

/**
 * RBAC route guard (migration 0024). The API's requireStaff is the real
 * enforcement — this only decides what a role gets to SEE. A forbidden path
 * redirects to the first page the role may open instead of a dead screen.
 */
function Gated({ path, children }: { path: string; children: React.ReactElement }) {
  const { dashboardRole } = useAuth();
  if (!canAccess(dashboardRole, path)) {
    return <Navigate to={firstAllowedPath(dashboardRole)} replace />;
  }
  return children;
}

export default function App() {
  // Keyed on the pathname so that navigating away from a page that threw clears
  // the boundary — otherwise a single crash would pin the admin to the error
  // screen for the rest of the session.
  const { pathname } = useLocation();

  return (
    <ErrorBoundary resetKey={pathname}>
      <Suspense fallback={<PageFallback />}>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route element={<ProtectedLayout />}>
            <Route path="/" element={<Gated path="/"><DashboardPage /></Gated>} />
            <Route path="/live" element={<Gated path="/live"><LiveMapPage /></Gated>} />
            <Route path="/captains" element={<Gated path="/captains"><CaptainsPage /></Gated>} />
            <Route path="/verification" element={<Gated path="/verification"><CaptainVerificationPage /></Gated>} />
            <Route path="/safety" element={<Gated path="/safety"><SafetyPage /></Gated>} />
            <Route path="/trips" element={<Gated path="/trips"><TripsPage /></Gated>} />
            <Route path="/analytics" element={<Gated path="/analytics"><AnalyticsPage /></Gated>} />
            <Route path="/pricing" element={<Gated path="/pricing"><PricingPage /></Gated>} />
            <Route path="/payouts" element={<Gated path="/payouts"><PayoutsPage /></Gated>} />
            <Route path="/users" element={<Gated path="/users"><UsersPage /></Gated>} />
            <Route path="/audit" element={<Gated path="/audit"><AuditLogPage /></Gated>} />
            <Route path="/settings" element={<Gated path="/settings"><SettingsPage /></Gated>} />
            <Route path="/staff" element={<Gated path="/staff"><StaffPage /></Gated>} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </ErrorBoundary>
  );
}
