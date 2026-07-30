import { useEffect, useMemo, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { formatCurrency, formatDate } from '../lib/utils';
import { StatusBadge } from '../components/ui/Badge';
import { DataTable, type Column } from '../components/ui/DataTable';
import { Filter, Search, Download, RefreshCw } from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';
import { downloadCsv, formatCsvDate, formatCsvNumber, type CsvColumn } from '../lib/csv';

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

const STATUS_OPTIONS: Array<[string, string]> = [
  ['', 'جميع الحالات'],
  ['searching', 'جاري البحث (مفتوح للمزايدة)'],
  ['offered', 'تم التقديم بعرض سعر'],
  ['assigned', 'مُعين (تم التوافق)'],
  ['arrived', 'وصل الكابتن'],
  ['in_progress', 'قيد التنفيذ'],
  ['completed', 'مكتملة'],
  ['cancelled', 'ملغية'],
];

export default function TripsPage() {
  const { token } = useAuth();
  const [trips, setTrips] = useState<Trip[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const [fromDate, setFromDate] = useState('');
  const [toDate, setToDate] = useState('');
  const [exportNotice, setExportNotice] = useState<string | null>(null);

  const fetchTrips = async () => {
    try {
      setLoading(true);
      const q = statusFilter ? `?status=${encodeURIComponent(statusFilter)}` : '';
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

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return trips.filter((t) => {
      if (term) {
        const hit =
          t.id.toLowerCase().includes(term) ||
          (t.city ?? '').toLowerCase().includes(term) ||
          (t.pickup_address ?? '').toLowerCase().includes(term) ||
          (t.dropoff_address ?? '').toLowerCase().includes(term) ||
          (t.rider_id ?? '').toLowerCase().includes(term) ||
          (t.captain_id ?? '').toLowerCase().includes(term);
        if (!hit) return false;
      }

      // Date bounds compare on the calendar DAY, so an inclusive "to" really
      // does include everything that happened on that date. Comparing a full
      // timestamp against a date-only string is the same class of bug that was
      // fixed server-side on this branch.
      if (fromDate || toDate) {
        const day = dayOf(t.created_at);
        if (!day) return false;
        if (fromDate && day < fromDate) return false;
        if (toDate && day > toDate) return false;
      }
      return true;
    });
  }, [trips, search, fromDate, toDate]);

  const columns: Column<Trip>[] = [
    {
      key: 'id',
      header: 'رقم الرحلة',
      sortable: true,
      accessor: (t) => (
        <span className="text-xs font-mono font-bold text-text-primary" dir="ltr" title={t.id}>
          {t.id.slice(0, 12)}…
        </span>
      ),
    },
    {
      key: 'status',
      header: 'الحالة',
      sortable: true,
      accessor: (t) => <StatusBadge status={t.status} />,
    },
    {
      key: 'city',
      header: 'المنطقة',
      sortable: true,
      accessor: (t) => <span className="text-xs font-bold text-text-primary">{t.city || '—'}</span>,
    },
    {
      key: 'offered_price',
      header: 'عرض العميل',
      sortable: true,
      accessor: (t) => (
        <span className="text-xs font-mono font-bold text-primary-600 dark:text-primary-400">
          {/* formatCurrency, not string interpolation: it applies the ar-EG
              thousands separator, so 12500 reads as ١٢٬٥٠٠ ج.م rather than
              "12500 ج.م". Matches how fares render everywhere else. */}
          {t.offered_price != null
            ? formatCurrency(t.offered_price)
            : t.estimated_fare != null
              ? formatCurrency(t.estimated_fare)
              : '—'}
        </span>
      ),
    },
    {
      key: 'accepted_price',
      header: 'السعر المتفق عليه',
      sortable: true,
      accessor: (t) => (
        <span className="text-xs font-mono font-bold text-text-primary">
          {/* `!= null` rather than a truthy test: a genuine 0 fare (a fully
              discounted promo trip) must not read as "still negotiating". */}
          {t.accepted_price != null
            ? formatCurrency(t.accepted_price)
            : t.final_fare != null
              ? formatCurrency(t.final_fare)
              : 'قيد التفاوض'}
        </span>
      ),
    },
    {
      key: 'payment_method',
      header: 'طريقة الدفع',
      sortable: true,
      accessor: (t) => <span className="text-xs text-text-secondary">{t.payment_method || '—'}</span>,
    },
    {
      key: 'created_at',
      header: 'التاريخ',
      sortable: true,
      accessor: (t) => (
        <span className="text-xs text-text-tertiary font-mono">{formatDate(t.created_at)}</span>
      ),
    },
  ];

  const csvColumns: CsvColumn<Trip>[] = [
    { header: 'رقم الرحلة', value: (t) => t.id },
    { header: 'الحالة', value: (t) => t.status },
    { header: 'المنطقة', value: (t) => t.city ?? '' },
    { header: 'نقطة الانطلاق', value: (t) => t.pickup_address ?? '' },
    { header: 'نقطة الوصول', value: (t) => t.dropoff_address ?? '' },
    { header: 'السعر التقديري', value: (t) => formatCsvNumber(t.estimated_fare) },
    { header: 'عرض العميل', value: (t) => formatCsvNumber(t.offered_price) },
    { header: 'السعر المتفق عليه', value: (t) => formatCsvNumber(t.accepted_price) },
    { header: 'السعر النهائي', value: (t) => formatCsvNumber(t.final_fare) },
    { header: 'طريقة الدفع', value: (t) => t.payment_method ?? '' },
    { header: 'معرف الراكب', value: (t) => t.rider_id ?? '' },
    { header: 'معرف الكابتن', value: (t) => t.captain_id ?? '' },
    { header: 'تاريخ الإنشاء', value: (t) => formatCsvDate(t.created_at) },
  ];

  const handleExport = () => {
    const n = downloadCsv('trips', filtered, csvColumns);
    setExportNotice(`تم تصدير ${n.toLocaleString('ar-EG')} رحلة`);
    window.setTimeout(() => setExportNotice(null), 4000);
  };

  const hasFilters = !!(search || fromDate || toDate || statusFilter);

  return (
    <div className="space-y-6" dir="rtl">
      <PageHeader
        title="الرحلات والمزايدات"
        subtitle="متابعة الرحلات الحية وعروض الأسعار المتفق عليها بين العملاء والكباتن"
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative">
              <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-tertiary pointer-events-none" />
              <input
                type="search"
                placeholder="بحث برقم الرحلة أو المنطقة..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full sm:w-60 pl-3 pr-9 py-2 bg-surface-secondary border border-border-primary rounded-lg text-sm text-text-primary placeholder:text-text-tertiary focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 transition-all"
              />
            </div>

            <div className="flex items-center gap-1.5 px-2 py-1 bg-surface-secondary border border-border-primary rounded-lg">
              <input
                type="date"
                value={fromDate}
                max={toDate || undefined}
                onChange={(e) => setFromDate(e.target.value)}
                aria-label="من تاريخ"
                className="bg-transparent text-xs text-text-primary focus:outline-none font-mono"
              />
              <span className="text-text-tertiary text-xs">—</span>
              <input
                type="date"
                value={toDate}
                min={fromDate || undefined}
                onChange={(e) => setToDate(e.target.value)}
                aria-label="إلى تاريخ"
                className="bg-transparent text-xs text-text-primary focus:outline-none font-mono"
              />
            </div>

            <div className="flex items-center gap-2">
              <Filter className="w-4 h-4 text-text-tertiary" />
              <select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="px-3 py-2 bg-surface-secondary border border-border-primary rounded-lg text-sm text-text-primary focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 font-bold transition-all"
              >
                {STATUS_OPTIONS.map(([value, label]) => (
                  <option key={value} value={value}>{label}</option>
                ))}
              </select>
            </div>

            <button
              onClick={fetchTrips}
              disabled={loading}
              title="تحديث"
              className="p-2 rounded-lg bg-surface-secondary border border-border-primary text-text-secondary hover:text-text-primary hover:border-primary-500/40 transition-all disabled:opacity-40"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>

            <button
              onClick={handleExport}
              disabled={filtered.length === 0}
              title={filtered.length === 0 ? 'لا توجد بيانات للتصدير' : `تصدير ${filtered.length} رحلة إلى CSV`}
              className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium rounded-lg bg-surface-secondary border border-border-primary text-text-secondary hover:text-text-primary hover:border-primary-500/40 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <Download className="w-4 h-4" />
              تصدير CSV
            </button>
          </div>
        }
      />

      {error && (
        <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main text-sm">
          {error}
        </div>
      )}

      {exportNotice && (
        <div className="p-3 bg-success-main/10 border border-success-main/30 rounded-xl text-success-main text-sm flex items-center gap-2">
          <Download className="w-4 h-4 shrink-0" />
          {exportNotice}
        </div>
      )}

      <DataTable<Trip>
        data={filtered}
        columns={columns}
        keyAccessor={(t) => t.id}
        loading={loading}
        defaultSortKey="created_at"
        defaultSortDirection="desc"
        pageSize={25}
        emptyMessage={hasFilters ? 'لا توجد رحلات مطابقة للبحث' : 'لا توجد رحلات مسجلة'}
      />
    </div>
  );
}

/**
 * Calendar day (YYYY-MM-DD) of a stored timestamp.
 *
 * The database holds two encodings: "2026-07-25 22:00:10" (space separated,
 * written by the SQL DEFAULT) and "2026-07-25T22:00:10.698Z" (ISO, written by
 * nowIso()). Slicing the first 10 characters is correct for both and, unlike
 * `new Date(...)`, cannot shift the day across a timezone boundary.
 */
function dayOf(timestamp: string | null | undefined): string | null {
  if (!timestamp) return null;
  const s = String(timestamp);
  return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(0, 10) : null;
}
