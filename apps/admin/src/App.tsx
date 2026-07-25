import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './lib/auth';
import LoginPage from './pages/LoginPage';
import DashboardPage from './pages/DashboardPage';
import CaptainsPage from './pages/CaptainsPage';
import TripsPage from './pages/TripsPage';
import PricingPage from './pages/PricingPage';
import UsersPage from './pages/UsersPage';
import LiveMapPage from './pages/LiveMapPage';
import AuditLogPage from './pages/AuditLogPage';
import AnalyticsPage from './pages/AnalyticsPage';
import SettingsPage from './pages/SettingsPage';
import CaptainVerificationPage from './pages/CaptainVerificationPage';
import Layout from './components/layout/Layout';

function ProtectedLayout() {
  const { token } = useAuth();
  if (!token) return <Navigate to="/login" replace />;
  return <Layout />;
}

export default function App() {
  return (
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
  );
}