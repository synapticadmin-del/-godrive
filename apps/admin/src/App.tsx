import { Suspense, lazy } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { useAuth } from './lib/auth';
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
            <Route path="/" element={<DashboardPage />} />
            <Route path="/live" element={<LiveMapPage />} />
            <Route path="/captains" element={<CaptainsPage />} />
            <Route path="/verification" element={<CaptainVerificationPage />} />
            <Route path="/trips" element={<TripsPage />} />
            <Route path="/analytics" element={<AnalyticsPage />} />
            <Route path="/pricing" element={<PricingPage />} />
            <Route path="/users" element={<UsersPage />} />
            <Route path="/audit" element={<AuditLogPage />} />
            <Route path="/settings" element={<SettingsPage />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </ErrorBoundary>
  );
}
