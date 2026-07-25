import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { formatCurrency } from '../lib/utils';
import { StatusBadge } from '../components/ui/Badge';
import { Users, Car, Route as RouteIcon, DollarSign, TrendingUp, Activity } from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';

interface Stats {
  users: { role: string; count: number }[];
  tripsByStatus: { status: string; count: number }[];
  today: { trips: number; gmv: number; commission: number } | null;
  onlineCaptains: number;
  pendingCaptains: number;
}

interface LiveTrip {
  id: string;
  status: string;
  city: string;
  rider_id: string;
  captain_id: string | null;
  estimated_fare: number | null;
  created_at: string;
}

export default function DashboardPage() {
  const { token } = useAuth();
  const [stats, setStats] = useState<Stats | null>(null);
  const [liveTrips, setLiveTrips] = useState<LiveTrip[]>([]);
  const [error, setError] = useState<string | null>(null);

  const fetchData = async () => {
    try {
      const [statsRes, liveRes] = await Promise.all([
        api<Stats>('/admin/stats', { token }),
        api<{ trips: LiveTrip[] }>('/admin/live-trips', { token }),
      ]);
      setStats(statsRes);
      setLiveTrips(liveRes.trips);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'فشل تحميل البيانات');
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 8000);
    return () => clearInterval(interval);
  }, [token]);

  const riders = stats?.users.find(u => u.role === 'rider')?.count ?? 0;
  const captains = stats?.users.find(u => u.role === 'captain')?.count ?? 0;
  const activeTrips = stats?.tripsByStatus.filter(t => !['completed', 'cancelled'].includes(t.status)).reduce((s, t) => s + t.count, 0) ?? 0;

  return (
    <div className="space-y-6">
      <PageHeader
        title="لوحة التحكم"
        subtitle="مراقبة أداء المنصة في الوقت الفعلي"
        actions={
          <div className="flex items-center gap-2 px-3 py-1.5 bg-surface-secondary rounded-lg">
            <Activity className="w-4 h-4 text-success-main" />
            <span className="text-sm text-text-secondary">تحديث كل 8 ثوانٍ</span>
          </div>
        }
      />

      {error && (
        <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main flex items-center gap-3">
          <span className="flex-1">{error}</span>
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="إجمالي الركاب" value={(riders || 0).toLocaleString('ar-EG')} icon={<Users className="w-6 h-6" />} trend="+12%" positive />
        <StatCard label="الكباتن المسجلين" value={(captains || 0).toLocaleString('ar-EG')} icon={<Car className="w-6 h-6" />} trend="+8%" positive />
        <StatCard label="الرحلات النشطة" value={String(activeTrips)} icon={<RouteIcon className="w-6 h-6" />} badge={stats?.onlineCaptains ? `${stats.onlineCaptains} أونلاين` : undefined} />
        <StatCard label="GMV اليوم" value={formatCurrency(stats?.today?.gmv ?? 0)} icon={<DollarSign className="w-6 h-6" />} trend={stats?.today?.commission ? `عمولة: ${formatCurrency(stats.today.commission)}` : ''} positive />
      </div>

      <div className="grid lg:grid-cols-3 gap-4">
        <div className="lg:col-span-2">
          <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden">
            <div className="px-5 py-4 border-b border-border-primary flex items-center justify-between">
              <div>
                <h3 className="text-lg font-semibold text-text-primary">الرحلات الحية</h3>
                <p className="text-text-tertiary text-sm">تحديث تلقائي</p>
              </div>
              {liveTrips.length > 0 && (
                <span className="inline-flex items-center gap-1.5 px-2.5 py-0.5 text-xs font-medium rounded-full bg-primary-500/10 text-primary-500">
                  <span className="w-1.5 h-1.5 rounded-full bg-primary-500 animate-pulse" />
                  {liveTrips.length} نشطة
                </span>
              )}
            </div>
            <div className="overflow-x-auto">
              {liveTrips.length > 0 ? (
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-border-primary bg-surface-secondary/50">
                      <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">ID</th>
                      <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الحالة</th>
                      <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">المدينة</th>
                      <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الأجرة</th>
                      <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الوقت</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border-primary/50">
                    {liveTrips.map((t) => (
                      <tr key={t.id} className="hover:bg-surface-hover transition-colors">
                        <td className="px-4 py-3 text-sm text-text-primary truncate max-w-[120px]" title={t.id}>{t.id.slice(0, 12)}…</td>
                        <td className="px-4 py-3"><StatusBadge status={t.status} /></td>
                        <td className="px-4 py-3 text-sm text-text-primary">{t.city}</td>
                        <td className="px-4 py-3 text-sm text-text-primary">{t.estimated_fare ?? '—'}</td>
                        <td className="px-4 py-3 text-sm text-text-tertiary">{new Date(t.created_at).toLocaleTimeString('ar-EG')}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : (
                <div className="p-12 text-center">
                  <RouteIcon className="w-12 h-12 mx-auto text-text-tertiary mb-4" />
                  <p className="text-text-secondary text-lg">لا توجد رحلات نشطة حالياً</p>
                  <p className="text-text-tertiary text-sm mt-1">الرحلات ستظهر هنا عند بدئها</p>
                </div>
              )}
            </div>
          </div>
        </div>

        <div className="space-y-4">
          <div className="bg-surface-primary border border-border-primary rounded-xl p-5">
            <h3 className="text-lg font-semibold text-text-primary mb-4">الكباتن</h3>
            <div className="grid grid-cols-2 gap-3">
              <MiniStat label="أونلاين" value={stats?.onlineCaptains ?? 0} color="success" />
              <MiniStat label="بانتظار الموافقة" value={stats?.pendingCaptains ?? 0} color="warning" />
            </div>
          </div>

          <div className="bg-surface-primary border border-border-primary rounded-xl p-5">
            <h3 className="text-lg font-semibold text-text-primary mb-4">حالة الرحلات</h3>
            <div className="space-y-2">
              {stats?.tripsByStatus.map((t) => (
                <div key={t.status} className="flex items-center justify-between py-1">
                  <StatusBadge status={t.status} />
                  <span className="font-semibold text-text-primary">{t.count}</span>
                </div>
              ))}
              {(!stats?.tripsByStatus || stats.tripsByStatus.length === 0) && (
                <p className="text-text-tertiary text-sm text-center py-4">لا توجد بيانات</p>
              )}
            </div>
          </div>

          <div className="bg-surface-primary border border-border-primary rounded-xl p-5">
            <h3 className="text-lg font-semibold text-text-primary mb-4">أداء اليوم</h3>
            <div className="grid grid-cols-2 gap-3">
              <MiniStat label="الرحلات" value={stats?.today?.trips ?? 0} color="info" />
              <MiniStat label="GMV" value={formatCurrency(stats?.today?.gmv ?? 0)} color="info" />
              <MiniStat label="العمولة" value={formatCurrency(stats?.today?.commission ?? 0)} color="info" />
              <MiniStat label="معدل الإكمال" value={stats?.today?.trips ? `${Math.round(((stats.tripsByStatus.find(s => s.status === 'completed')?.count ?? 0) / stats.today.trips) * 100)}%` : '0%'} color="info" />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function StatCard({ label, value, icon, trend, positive, badge }: { label: string; value: string; icon: React.ReactNode; trend?: string; positive?: boolean; badge?: string }) {
  return (
    <div className="bg-surface-primary border border-border-primary rounded-xl p-5">
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl bg-primary-500/10 flex items-center justify-center text-primary-500">{icon}</div>
          <div>
            <p className="text-sm text-text-secondary">{label}</p>
            <p className="text-2xl font-bold text-text-primary">{value}</p>
          </div>
        </div>
        {badge && <span className="px-2 py-0.5 text-xs font-medium rounded-full bg-success-main/10 text-success-main">{badge}</span>}
      </div>
      {trend && (
        <div className="mt-3 pt-3 border-t border-border-primary flex items-center gap-2">
          <TrendingUp className={`w-4 h-4 ${positive ? 'text-success-main' : 'text-error-main'}`} />
          <span className={`text-sm font-medium ${positive ? 'text-success-main' : 'text-error-main'}`}>{trend}</span>
        </div>
      )}
    </div>
  );
}

function MiniStat({ label, value, color }: { label: string; value: string | number; color: 'success' | 'warning' | 'info' | 'danger' }) {
  const colors = { success: 'bg-success-main/10 text-success-main', warning: 'bg-warning-main/10 text-warning-main', info: 'bg-primary-500/10 text-primary-500', danger: 'bg-error-main/10 text-error-main' };
  return (
    <div className={`p-3 rounded-xl ${colors[color]}`}>
      <p className="text-xs opacity-80">{label}</p>
      <p className="text-xl font-bold mt-0.5">{value}</p>
    </div>
  );
}