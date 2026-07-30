import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { formatCurrency } from '../lib/utils';
import { StatusBadge } from '../components/ui/Badge';
import { Users, Car, Route as RouteIcon, DollarSign, Activity } from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';
import { usePolling } from '../lib/usePolling';

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

  // Live dashboard polling — pauses while the tab is hidden, resumes (with an
  // immediate refetch) when it becomes visible again.
  usePolling(fetchData, 8000);

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
        {/* NOTE: the first two cards previously showed trend="+12%" / "+8%".
            Those were hard-coded literals — nothing computed them, and
            /admin/stats returns only current totals with no historical
            baseline to compare against. They have been removed rather than
            restyled. Cards that CAN state a real fact use `footnote`, which is
            a plain caption and makes no comparative claim. */}
        <StatCard
          label="إجمالي الركاب"
          value={(riders || 0).toLocaleString('ar-EG')}
          icon={<Users className="w-6 h-6" />}
          loading={!stats}
        />
        <StatCard
          label="الكباتن المسجلين"
          value={(captains || 0).toLocaleString('ar-EG')}
          icon={<Car className="w-6 h-6" />}
          footnote={stats?.pendingCaptains ? `${stats.pendingCaptains.toLocaleString('ar-EG')} بانتظار الموافقة` : undefined}
          loading={!stats}
        />
        <StatCard
          label="الرحلات النشطة"
          value={String(activeTrips)}
          icon={<RouteIcon className="w-6 h-6" />}
          badge={stats?.onlineCaptains ? `${stats.onlineCaptains} أونلاين` : undefined}
          loading={!stats}
        />
        <StatCard
          label="GMV اليوم"
          value={formatCurrency(stats?.today?.gmv ?? 0)}
          icon={<DollarSign className="w-6 h-6" />}
          footnote={stats?.today?.commission ? `عمولة: ${formatCurrency(stats.today.commission)}` : undefined}
          loading={!stats}
        />
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
                        {/* formatCurrency already returns '—' for null, and adds
                            the currency + ar-EG separator the bare number lacked. */}
                        <td className="px-4 py-3 text-sm text-text-primary">{formatCurrency(t.estimated_fare)}</td>
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
              {/* This tile previously divided ALL-TIME completed trips
                  (tripsByStatus, which is ungrouped by date) by TODAY's trip
                  count, under a heading that reads "أداء اليوم" (today's
                  performance). On any instance with history that yields
                  nonsense — 40 completed all-time over 2 trips today rendered
                  as "2000%".

                  /admin/stats.today does not return a completed count, so a
                  correct same-day rate cannot be derived here. Showing the
                  average fare instead: it is genuinely today-scoped, uses only
                  fields the endpoint actually returns, and is useful at a
                  glance. The real completion rate lives on the analytics page,
                  where it is computed over a well-defined range. */}
              <MiniStat
                label="متوسط قيمة الرحلة"
                value={
                  stats?.today?.trips
                    ? formatCurrency(Math.round((stats.today.gmv ?? 0) / stats.today.trips))
                    : formatCurrency(0)
                }
                color="info"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/**
 * Summary card for the live dashboard.
 *
 * `footnote` is a neutral caption for a fact the card can actually state (a
 * pending count, today's commission). It is deliberately NOT a trend: this
 * endpoint has no historical baseline, so any "+X% vs yesterday" rendered here
 * would be invented. The previous version accepted a free-text `trend` string
 * and was being passed literals; that prop no longer exists.
 */
function StatCard({
  label,
  value,
  icon,
  footnote,
  badge,
  loading = false,
}: {
  label: string;
  value: string;
  icon: React.ReactNode;
  footnote?: string;
  badge?: string;
  loading?: boolean;
}) {
  if (loading) {
    return (
      <div className="bg-surface-primary border border-border-primary rounded-xl p-5" aria-busy="true">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl bg-surface-tertiary animate-pulse" />
          <div className="flex-1 space-y-2">
            <div className="h-3 bg-surface-tertiary rounded animate-pulse w-2/3" />
            <div className="h-6 bg-surface-tertiary rounded animate-pulse w-1/2" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="group bg-surface-primary border border-border-primary rounded-xl p-5 transition-all duration-200 hover:border-primary-500/40 hover:shadow-md">
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl bg-primary-500/10 flex items-center justify-center text-primary-500 transition-transform duration-200 group-hover:scale-105">
            {icon}
          </div>
          <div>
            <p className="text-sm text-text-secondary">{label}</p>
            <p className="text-2xl font-bold text-text-primary">{value}</p>
          </div>
        </div>
        {badge && <span className="px-2 py-0.5 text-xs font-medium rounded-full bg-success-main/10 text-success-main">{badge}</span>}
      </div>
      {footnote && (
        <div className="mt-3 pt-3 border-t border-border-primary">
          <span className="text-sm text-text-tertiary">{footnote}</span>
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
