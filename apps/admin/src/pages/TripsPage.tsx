import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { formatDate } from '../lib/utils';
import { StatusBadge } from '../components/ui/Badge';
import { Route as RouteIcon, Loader2, Filter } from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';

interface Trip {
  id: string;
  status: string;
  city: string;
  pickup_address: string | null;
  dropoff_address: string | null;
  estimated_fare: number | null;
  offered_price: number | null;
  accepted_price: number | null;
  final_fare: number | null;
  payment_method: string;
  created_at: string;
  rider_id: string;
  captain_id: string | null;
}

export default function TripsPage() {
  const { token } = useAuth();
  const [trips, setTrips] = useState<Trip[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState('');

  const fetchTrips = async () => {
    try {
      setLoading(true);
      const q = statusFilter ? `?status=${statusFilter}` : '';
      const res = await api<{ trips: Trip[] }>(`/admin/trips${q}`, { token });
      setTrips(res.trips || []);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'فشل التحميل');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchTrips(); }, [token, statusFilter]);

  return (
    <div className="space-y-6" dir="rtl">
      <PageHeader
        title="الرحلات والمزايدات"
        subtitle="متابعة الرحلات الحية وعروض الأسعار المتفق عليها بين العملاء والكباتن"
        actions={
          <div className="flex items-center gap-2">
            <Filter className="w-4 h-4 text-text-tertiary" />
            <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className="px-3 py-2 bg-surface-secondary border border-border-primary rounded-lg text-sm text-text-primary focus:border-primary-500 focus:outline-none font-bold">
              <option value="">جميع الحالات</option>
              <option value="searching">جاري البحث (مفتوح للمزايدة)</option>
              <option value="offered">تم التقديم بعرض سعر</option>
              <option value="assigned">مُعين (تم التوافق)</option>
              <option value="arrived">وصل الكابتن</option>
              <option value="in_progress">قيد التنفيذ</option>
              <option value="completed">مكتملة</option>
              <option value="cancelled">ملغية</option>
            </select>
          </div>
        }
      />

      {error && <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main text-sm">{error}</div>}

      <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden shadow-xs">
        {loading ? (
          <div className="p-12 text-center"><Loader2 className="w-8 h-8 mx-auto text-primary-500 animate-spin" /><p className="text-text-secondary text-xs mt-2">جاري تحميل رحلات المزايدة...</p></div>
        ) : trips.length === 0 ? (
          <div className="p-12 text-center"><RouteIcon className="w-12 h-12 mx-auto text-text-tertiary mb-4" /><p className="text-text-secondary">لا توجد رحلات مسجلة</p></div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right text-sm">
              <thead><tr className="border-b border-border-primary bg-surface-secondary/50 text-xs font-semibold text-text-tertiary">
                <th className="px-4 py-3">رقم الرحلة</th>
                <th className="px-4 py-3">الحالة</th>
                <th className="px-4 py-3">المنطقة</th>
                <th className="px-4 py-3">عرض العميل</th>
                <th className="px-4 py-3">السعر المتفق عليه</th>
                <th className="px-4 py-3">طريقة الدفع</th>
                <th className="px-4 py-3">التاريخ</th>
              </tr></thead>
              <tbody className="divide-y divide-border-primary/50">
                {trips.map((t) => (
                  <tr key={t.id} className="hover:bg-surface-hover transition-colors">
                    <td className="px-4 py-3 text-xs font-mono font-bold text-text-primary" title={t.id}>{t.id.slice(0, 12)}…</td>
                    <td className="px-4 py-3"><StatusBadge status={t.status} /></td>
                    <td className="px-4 py-3 text-xs font-bold text-text-primary">{t.city}</td>
                    <td className="px-4 py-3 text-xs font-mono font-bold text-primary-600 dark:text-primary-400">
                      {t.offered_price ? `${t.offered_price} ج.م` : t.estimated_fare ? `${t.estimated_fare} ج.م` : '—'}
                    </td>
                    <td className="px-4 py-3 text-xs font-mono font-bold text-text-primary">
                      {t.accepted_price ? `${t.accepted_price} ج.م` : t.final_fare ? `${t.final_fare} ج.م` : 'قيد التفاوض'}
                    </td>
                    <td className="px-4 py-3 text-xs text-text-secondary">{t.payment_method}</td>
                    <td className="px-4 py-3 text-xs text-text-tertiary font-mono">{formatDate(t.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}