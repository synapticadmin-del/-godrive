import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import {
  BarChart3, TrendingUp, DollarSign, CheckCircle, Calendar,
  PieChart as PieIcon, Award, ArrowUpRight, ArrowDownRight, RefreshCw, Minus, Download
} from 'lucide-react';
import {
  BarChart, Bar, AreaChart, Area, LineChart, Line, PieChart, Pie,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, Cell
} from 'recharts';
import { PageHeader } from '../components/layout/PageHeader';
import { downloadCsv, formatCsvNumber } from '../lib/csv';

interface PeriodTotals {
  trips: number;
  completed: number;
  cancelled: number;
  gmv: number;
  commission: number;
  completionRate: number;
}

/**
 * Percentage change vs the previous equal-length period, computed server-side.
 *
 * `null` means "no comparison available" — either the baseline was zero (growth
 * from nothing is not a percentage) or the range could not be compared. The UI
 * must render null as an explicit non-value, never as a placeholder figure.
 */
interface AnalyticsDeltas {
  trips: number | null;
  completed: number | null;
  gmv: number | null;
  commission: number | null;
  /** Change in completion rate, in percentage POINTS (not percent-of-percent). */
  completionRatePoints: number | null;
}

interface AnalyticsData {
  from: string;
  to: string;
  totals: PeriodTotals;
  daily: Array<{
    day: string;
    trips: number;
    completed: number;
    cancelled?: number;
    gmv: number;
    commission: number;
    completionRate?: number;
  }>;
  topCaptains: Array<{
    captain_id: string;
    name: string | null;
    email: string;
    trips: number;
    gmv: number;
  }>;
  previous?: { from: string; to: string; totals: PeriodTotals } | null;
  deltas?: AnalyticsDeltas;
}

const BRAND_COLORS = {
  primary: '#6bb522',       // GoDrive Green
  charcoal: '#53585f',      // GoDrive Slate
  accent: '#74c425',
  success: '#22c55e',
  warning: '#f59e0b',
  error: '#ef4444',
  purple: '#8b5cf6',
};

const PIE_COLORS = ['#6bb522', '#ef4444', '#f59e0b', '#3b82f6'];

/**
 * Format a Date as YYYY-MM-DD in the viewer's LOCAL calendar.
 *
 * Deliberately not `.toISOString().split('T')[0]`: toISOString converts to UTC
 * first, so for any positive-UTC timezone (this product operates in Cairo,
 * UTC+2/+3) a local date near midnight shifts back a day. That made "this
 * month" start on the last day of the PREVIOUS month, and made "today" resolve
 * to yesterday for the first hours of every day.
 */
function toLocalYmd(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/**
 * Build a date-only range for a preset, anchored to local midnight so the
 * boundaries line up with the days the admin actually sees.
 *
 * The ranges are inclusive of both ends: "7d" is today plus the six preceding
 * days, which is seven calendar days, matching the label.
 */
function presetRange(preset: '7d' | '30d' | 'thisMonth'): { from: string; to: string } {
  const now = new Date();
  const to = toLocalYmd(now);

  if (preset === 'thisMonth') {
    return { from: toLocalYmd(new Date(now.getFullYear(), now.getMonth(), 1)), to };
  }

  const days = preset === '7d' ? 7 : 30;
  // Step by calendar date rather than by milliseconds so DST transitions
  // cannot shift the boundary.
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (days - 1));
  return { from: toLocalYmd(start), to };
}

function CustomTooltip({ active, payload, label }: any) {
  if (active && payload && payload.length) {
    return (
      <div className="bg-surface-primary border border-border-primary rounded-xl p-3 shadow-xl text-right dir-rtl">
        <p className="font-bold text-text-primary text-xs mb-2 border-b border-border-primary pb-1 font-mono">
          {label}
        </p>
        {payload.map((entry: any, i: number) => (
          <div key={i} className="text-xs flex items-center justify-between gap-4 py-0.5">
            <span className="font-bold text-text-primary font-mono">
              {typeof entry.value === 'number' ? entry.value.toLocaleString('ar-EG') : entry.value}
            </span>
            <div className="flex items-center gap-1.5 text-text-secondary">
              <span>{entry.name}</span>
              <span className="w-2.5 h-2.5 rounded-full inline-block" style={{ backgroundColor: entry.color }} />
            </div>
          </div>
        ))}
      </div>
    );
  }
  return null;
}

export default function AnalyticsPage() {
  const { token } = useAuth();
  const [data, setData] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [exportNotice, setExportNotice] = useState<string | null>(null);

  // Preset Date Ranges
  const [datePreset, setDatePreset] = useState<'7d' | '30d' | 'thisMonth'>('30d');
  const [dateRange, setDateRange] = useState(() => presetRange('30d'));

  const applyPreset = (preset: '7d' | '30d' | 'thisMonth') => {
    setDatePreset(preset);
    setDateRange(presetRange(preset));
  };

  const loadAnalytics = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await api<AnalyticsData>(
        `/admin/analytics?from=${dateRange.from}&to=${dateRange.to}`,
        { token }
      );

      // Enhance daily data with completion rates if missing.
      // A day with no trips has NO completion rate — it is not 100% successful.
      // The old `: 100` fallback drew a flat perfect line across empty days.
      const enhancedDaily = (res.daily || []).map((d) => {
        const compRate = d.trips > 0 ? Math.round((d.completed / d.trips) * 100) : 0;
        const cancelledCount = d.cancelled ?? Math.max(0, d.trips - d.completed);
        return {
          ...d,
          completionRate: compRate,
          cancelled: cancelledCount,
        };
      });

      // topCaptains was previously read unguarded at render time, so an API
      // response that omitted it threw "Cannot read properties of undefined".
      // `daily` was already guarded; this makes the treatment consistent.
      setData({
        ...res,
        daily: enhancedDaily,
        topCaptains: res.topCaptains ?? [],
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'فشل تحميل بيانات التحليلات');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadAnalytics();
  }, [token, dateRange.from, dateRange.to]);

  // Calculated Metrics
  const totalTrips = data?.totals?.trips ?? 0;
  const completedTrips = data?.totals?.completed ?? 0;
  const cancelledTrips = data?.totals?.cancelled ?? Math.max(0, totalTrips - completedTrips);
  // No trips means no completion rate. The previous `: 100` fallback showed a
  // perfect 100% success ring for periods that had zero activity.
  const completionRate =
    data?.totals?.completionRate ?? (totalTrips > 0 ? Math.round((completedTrips / totalTrips) * 100) : 0);
  const totalGmv = data?.totals?.gmv ?? 0;
  // Real commission summed from trips.commission, not GMV x 0.2. The flat 20%
  // guess ignored per-city commission_rate in pricing_rules, so the figure was
  // wrong for every city not set to exactly 20%.
  const totalCommission = data?.totals?.commission ?? 0;
  const averageOrderValue = completedTrips > 0 ? Math.round(totalGmv / completedTrips) : 0;

  // True when the selected range genuinely contains no trips. Distinct from
  // `loading` and from an error: the request succeeded and the answer is zero.
  const isEmptyRange = !!data && totalTrips === 0 && (data.daily?.length ?? 0) === 0;

  const deltas = data?.deltas;
  const hasComparison = !!data?.previous;

  // Pie chart data for trip status ratios
  const tripRatioData = [
    { name: 'رحلات مكتملة', value: completedTrips },
    { name: 'رحلات ملغية', value: cancelledTrips },
  ];

  // CSV export — the daily series, which is the row-shaped part of this page.
  // The KPI totals are a single aggregate row and are better read on screen;
  // exporting the day-by-day breakdown is what makes a spreadsheet useful.
  const handleExportCsv = () => {
    if (!data) return;
    const rows = data.daily ?? [];
    const n = downloadCsv(`analytics-${dateRange.from}_${dateRange.to}`, rows, [
      { header: 'اليوم', value: (d) => d.day },
      { header: 'إجمالي الرحلات', value: (d) => formatCsvNumber(d.trips, 0) },
      { header: 'المكتملة', value: (d) => formatCsvNumber(d.completed, 0) },
      { header: 'الملغية', value: (d) => formatCsvNumber(d.cancelled ?? 0, 0) },
      { header: 'نسبة الإكمال %', value: (d) => formatCsvNumber(d.completionRate ?? 0, 1) },
      { header: 'حجم المعاملات (GMV)', value: (d) => formatCsvNumber(d.gmv) },
      { header: 'العمولة', value: (d) => formatCsvNumber(d.commission) },
    ]);
    setExportNotice(`تم تصدير ${n.toLocaleString('ar-EG')} يوم`);
    window.setTimeout(() => setExportNotice(null), 4000);
  };

  return (
    <div className="space-y-6 animate-fade-in" dir="rtl">
      {/* Header */}
      <PageHeader
        title="مؤشرات الأداء والتحليلات"
        subtitle="تحليل المبيعات، معدلات إكمال الرحلات، وعوائد شبكة الكباتن"
        actions={
          <div className="flex flex-wrap items-center gap-2">
            {/* Presets */}
            <div className="flex items-center bg-surface-secondary p-1 rounded-lg border border-border-primary">
              <button
                onClick={() => applyPreset('7d')}
                className={`px-3 py-1 rounded-md text-xs font-bold transition-all ${
                  datePreset === '7d' ? 'bg-primary-500 text-white shadow-xs' : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                7 أيام
              </button>
              <button
                onClick={() => applyPreset('30d')}
                className={`px-3 py-1 rounded-md text-xs font-bold transition-all ${
                  datePreset === '30d' ? 'bg-primary-500 text-white shadow-xs' : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                30 يوم
              </button>
              <button
                onClick={() => applyPreset('thisMonth')}
                className={`px-3 py-1 rounded-md text-xs font-bold transition-all ${
                  datePreset === 'thisMonth' ? 'bg-primary-500 text-white shadow-xs' : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                هذا الشهر
              </button>
            </div>

            {/* Custom Dates */}
            <div className="flex items-center gap-1.5 bg-surface-primary border border-border-primary px-3 py-1.5 rounded-lg text-xs">
              <Calendar className="w-4 h-4 text-primary-500" />
              <input
                type="date"
                value={dateRange.from}
                onChange={(e) => setDateRange({ ...dateRange, from: e.target.value })}
                className="bg-transparent text-text-primary focus:outline-none font-mono"
              />
              <span className="text-text-tertiary">إلى</span>
              <input
                type="date"
                value={dateRange.to}
                onChange={(e) => setDateRange({ ...dateRange, to: e.target.value })}
                className="bg-transparent text-text-primary focus:outline-none font-mono"
              />
            </div>

            <button
              onClick={loadAnalytics}
              className="p-2 rounded-lg bg-surface-primary border border-border-primary hover:bg-surface-hover text-text-secondary transition-colors"
              title="تحديث البيانات"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>

            <button
              onClick={handleExportCsv}
              disabled={!data || (data.daily?.length ?? 0) === 0}
              title={
                !data || (data.daily?.length ?? 0) === 0
                  ? 'لا توجد بيانات للتصدير'
                  : 'تصدير التحليلات اليومية إلى CSV'
              }
              className="flex items-center gap-1.5 px-3 py-2 text-xs font-bold rounded-lg bg-surface-secondary border border-border-primary text-text-secondary hover:text-text-primary hover:border-primary-500/40 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <Download className="w-4 h-4" />
              تصدير CSV
            </button>
          </div>
        }
      />

      {exportNotice && (
        <div className="p-3 bg-success-main/10 border border-success-main/30 rounded-xl text-success-main text-sm flex items-center gap-2">
          <Download className="w-4 h-4 shrink-0" />
          {exportNotice}
        </div>
      )}

      {error && (
        <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main text-sm">
          {error}
        </div>
      )}

      {loading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="bg-surface-primary border border-border-primary rounded-xl p-5 animate-pulse">
              <div className="h-4 bg-surface-tertiary rounded w-3/4 mb-3" />
              <div className="h-8 bg-surface-tertiary rounded w-1/2" />
            </div>
          ))}
        </div>
      ) : data ? (
        <>
          {/* Top 4 KPI Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <KPI
              label="إجمالي حجم المعاملات (GMV)"
              value={`${totalGmv.toLocaleString('ar-EG')} ج.م`}
              subtext={`صافي عمولة المنصة: ${totalCommission.toLocaleString('ar-EG')} ج.م`}
              icon={<DollarSign className="w-6 h-6" />}
              delta={deltas?.gmv}
              showComparison={hasComparison}
            />

            <KPI
              label="إجمالي الرحلات المطلوبة"
              value={totalTrips.toLocaleString('ar-EG')}
              subtext={`المكتملة: ${completedTrips.toLocaleString('ar-EG')} رحلة`}
              icon={<BarChart3 className="w-6 h-6" />}
              delta={deltas?.trips}
              showComparison={hasComparison}
            />

            <KPI
              label="نسبة نجاح وإكمال الرحلات"
              value={`${completionRate}%`}
              subtext={`الملغية: ${cancelledTrips.toLocaleString('ar-EG')} رحلة`}
              icon={<CheckCircle className="w-6 h-6" />}
              delta={deltas?.completionRatePoints}
              deltaUnit="points"
              showComparison={hasComparison}
            />

            <KPI
              label="متوسط قيمة الرحلة (AOV)"
              value={`${averageOrderValue.toLocaleString('ar-EG')} ج.م`}
              subtext="متوسط إنفاق الراكب في الرحلة"
              icon={<TrendingUp className="w-6 h-6" />}
              // AOV is GMV / completed trips. Deriving its delta from the GMV
              // delta would be wrong (both numerator and denominator move), and
              // the API does not return a previous AOV, so no delta is claimed.
              showComparison={false}
            />
          </div>

          {/* Empty range.
              The request succeeded and the honest answer is "no trips in this
              window". Previously the page rendered three blank charts with no
              explanation, which is indistinguishable from a failed load. The
              KPI cards above stay visible because zero IS the correct value. */}
          {isEmptyRange && (
            <div className="bg-surface-primary border border-border-primary border-dashed rounded-xl p-10 text-center">
              <div className="w-14 h-14 mx-auto rounded-2xl bg-surface-secondary flex items-center justify-center mb-4">
                <Calendar className="w-7 h-7 text-text-tertiary" />
              </div>
              <p className="text-text-primary font-bold text-base">لا توجد رحلات في هذه الفترة</p>
              <p className="text-text-tertiary text-sm mt-1.5 max-w-md mx-auto">
                لم يتم تسجيل أي رحلات بين {dateRange.from} و {dateRange.to}. جرّب توسيع النطاق الزمني
                أو اختيار فترة أخرى.
              </p>
              <div className="flex items-center justify-center gap-2 mt-5">
                <button
                  onClick={() => applyPreset('30d')}
                  className="px-3.5 py-1.5 rounded-lg text-xs font-bold bg-surface-secondary border border-border-primary text-text-secondary hover:text-text-primary hover:border-primary-500/40 transition-all"
                >
                  آخر 30 يوم
                </button>
                <button
                  onClick={loadAnalytics}
                  className="px-3.5 py-1.5 rounded-lg text-xs font-bold bg-primary-500 text-white hover:bg-primary-600 transition-all"
                >
                  إعادة المحاولة
                </button>
              </div>
            </div>
          )}

          {/* Section 1: Main Charts Grid.
              Hidden when the range is empty — an axis with no series is noise,
              and the dashed panel above already states the situation. */}
          <div className={`grid grid-cols-1 lg:grid-cols-12 gap-6 ${isEmptyRange ? 'hidden' : ''}`}>
            {/* GMV & Revenue Area Chart (7 Cols) */}
            <div className="lg:col-span-7 bg-surface-primary border border-border-primary rounded-xl p-5 shadow-xs space-y-4">
              <div className="flex items-center justify-between border-b border-border-primary pb-3">
                <div>
                  <h3 className="font-extrabold text-text-primary text-base flex items-center gap-2">
                    <TrendingUp className="w-5 h-5 text-primary-500" />
                    تطور حجم المعاملات اليومية (GMV)
                  </h3>
                  <p className="text-xs text-text-tertiary">متابعة الأرباح وحركة المبيعات خلال الفترة</p>
                </div>
                <span className="px-2.5 py-1 bg-primary-500/10 text-primary-600 dark:text-primary-400 border border-primary-500/20 text-xs font-bold rounded-full font-mono">
                  {totalGmv.toLocaleString('ar-EG')} ج.م
                </span>
              </div>

              <div className="h-[320px] w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={data.daily}>
                    <defs>
                      <linearGradient id="gmvGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor={BRAND_COLORS.primary} stopOpacity={0.4} />
                        <stop offset="95%" stopColor={BRAND_COLORS.primary} stopOpacity={0} />
                      </linearGradient>
                      <linearGradient id="commissionGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor={BRAND_COLORS.charcoal} stopOpacity={0.4} />
                        <stop offset="95%" stopColor={BRAND_COLORS.charcoal} stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    {/* The Tailwind class "font-mono" had been concatenated into
                        this SVG stroke value, making it an invalid colour, so
                        this grid silently failed to paint. Line 467 always had
                        the correct form. */}
                    <CartesianGrid strokeDasharray="3 3" stroke="rgb(var(--border-primary))" />
                    <XAxis dataKey="day" tick={{ fill: 'rgb(var(--text-tertiary))', fontSize: 11 }} />
                    <YAxis tick={{ fill: 'rgb(var(--text-tertiary))', fontSize: 11 }} />
                    <Tooltip content={<CustomTooltip />} />
                    <Legend />
                    <Area
                      type="monotone"
                      dataKey="gmv"
                      name="حجم المبيعات (GMV)"
                      stroke={BRAND_COLORS.primary}
                      strokeWidth={3}
                      fill="url(#gmvGradient)"
                    />
                    <Area
                      type="monotone"
                      dataKey="commission"
                      name="صافي عمولة المنصة"
                      stroke={BRAND_COLORS.charcoal}
                      strokeWidth={2}
                      fill="url(#commissionGradient)"
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>

            {/* Trip Status Donut / Ratio Chart (5 Cols) */}
            <div className="lg:col-span-5 bg-surface-primary border border-border-primary rounded-xl p-5 shadow-xs flex flex-col justify-between space-y-4">
              <div className="border-b border-border-primary pb-3">
                <h3 className="font-extrabold text-text-primary text-base flex items-center gap-2">
                  <PieIcon className="w-5 h-5 text-primary-500" />
                  توزيع نسبة إكمال الرحلات
                </h3>
                <p className="text-xs text-text-tertiary">مقارنة الرحلات الناجحة مقابل الملغية</p>
              </div>

              <div className="h-[240px] w-full relative">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={tripRatioData}
                      cx="50%"
                      cy="50%"
                      innerRadius={65}
                      outerRadius={95}
                      paddingAngle={5}
                      dataKey="value"
                    >
                      {tripRatioData.map((_, index) => (
                        <Cell key={`cell-${index}`} fill={PIE_COLORS[index % PIE_COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip content={<CustomTooltip />} />
                  </PieChart>
                </ResponsiveContainer>

                {/* Center Badge inside Donut */}
                <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                  <span className="text-2xl font-black text-text-primary font-mono">{completionRate}%</span>
                  <span className="text-[11px] font-bold text-text-tertiary">نسبة النجاح</span>
                </div>
              </div>

              {/* Legend Summary */}
              <div className="grid grid-cols-2 gap-3 pt-3 border-t border-border-primary text-center">
                <div className="p-2 rounded-lg bg-primary-500/10 border border-primary-500/20">
                  <p className="text-xs text-primary-600 dark:text-primary-400 font-bold">رحلات مكتملة</p>
                  <p className="text-base font-black font-mono text-text-primary">{completedTrips.toLocaleString('ar-EG')}</p>
                </div>
                <div className="p-2 rounded-lg bg-error-main/10 border border-error-main/20">
                  <p className="text-xs text-error-main font-bold">رحلات ملغية</p>
                  <p className="text-base font-black font-mono text-text-primary">{cancelledTrips.toLocaleString('ar-EG')}</p>
                </div>
              </div>
            </div>
          </div>

          {/* Section 2: Daily Trips Breakdown & Top Captains Leaderboard */}
          <div className={`grid grid-cols-1 lg:grid-cols-12 gap-6 ${isEmptyRange ? 'hidden' : ''}`}>
            {/* Daily Trips Bar Chart (7 Cols) */}
            <div className="lg:col-span-7 bg-surface-primary border border-border-primary rounded-xl p-5 shadow-xs space-y-4">
              <div className="flex items-center justify-between border-b border-border-primary pb-3">
                <h3 className="font-extrabold text-text-primary text-base flex items-center gap-2">
                  <BarChart3 className="w-5 h-5 text-primary-500" />
                  عدد الرحلات اليومية (المطلوبة والمكتملة)
                </h3>
                <span className="text-xs text-text-tertiary font-mono">آخر 30 يوم</span>
              </div>

              <div className="h-[280px] w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={data.daily}>
                    <CartesianGrid strokeDasharray="3 3" stroke="rgb(var(--border-primary))" />
                    <XAxis dataKey="day" tick={{ fill: 'rgb(var(--text-tertiary))', fontSize: 11 }} />
                    <YAxis tick={{ fill: 'rgb(var(--text-tertiary))', fontSize: 11 }} />
                    <Tooltip content={<CustomTooltip />} />
                    <Legend />
                    <Bar dataKey="trips" name="إجمالي المطلوبة" fill={BRAND_COLORS.charcoal} radius={[4, 4, 0, 0]} />
                    <Bar dataKey="completed" name="المكتملة" fill={BRAND_COLORS.primary} radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>

            {/* Top Captains Leaderboard (5 Cols) */}
            <div className="lg:col-span-5 bg-surface-primary border border-border-primary rounded-xl p-5 shadow-xs space-y-4 flex flex-col">
              <div className="flex items-center justify-between border-b border-border-primary pb-3">
                <h3 className="font-extrabold text-text-primary text-base flex items-center gap-2">
                  <Award className="w-5 h-5 text-primary-500" />
                  أفضل الكباتن تحقيقاً للإيرادات
                </h3>
                <span className="text-xs font-bold text-primary-600 dark:text-primary-400 bg-primary-500/10 px-2 py-0.5 rounded-full border border-primary-500/20">
                  الأعلى أداءً
                </span>
              </div>

              <div className="overflow-x-auto flex-1">
                <table className="w-full text-right text-sm">
                  <thead className="border-b border-border-primary text-xs font-semibold text-text-tertiary">
                    <tr>
                      <th className="py-2 px-3">#</th>
                      <th className="py-2 px-3">الكابتن</th>
                      <th className="py-2 px-3 text-center">الرحلات</th>
                      <th className="py-2 px-3 text-left">GMV الإجمالي</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border-primary/50">
                    {data.topCaptains.map((c, i) => (
                      <tr key={c.captain_id} className="hover:bg-surface-hover transition-colors">
                        <td className="py-2.5 px-3">
                          <span
                            className={`w-6 h-6 rounded-full inline-flex items-center justify-center text-xs font-bold ${
                              i === 0
                                ? 'bg-amber-500/20 text-amber-600 border border-amber-500/30'
                                : i === 1
                                ? 'bg-slate-400/20 text-slate-600 border border-slate-400/30'
                                : i === 2
                                ? 'bg-amber-700/20 text-amber-800 border border-amber-700/30'
                                : 'text-text-tertiary'
                            }`}
                          >
                            {i + 1}
                          </span>
                        </td>
                        <td className="py-2.5 px-3">
                          <p className="font-bold text-text-primary text-xs truncate max-w-[140px]">
                            {c.name || 'كابتن مجهول'}
                          </p>
                          <p className="text-[10px] text-text-tertiary truncate max-w-[140px]">
                            {c.email}
                          </p>
                        </td>
                        <td className="py-2.5 px-3 text-center font-mono font-bold text-xs">
                          {c.trips}
                        </td>
                        <td className="py-2.5 px-3 text-left font-mono font-bold text-xs text-primary-600 dark:text-primary-400">
                          {c.gmv ? `${c.gmv.toLocaleString('ar-EG')} ج.م` : '0 ج.م'}
                        </td>
                      </tr>
                    ))}

                    {!data.topCaptains.length && (
                      <tr>
                        <td colSpan={4} className="py-8 text-center text-text-tertiary text-xs">
                          لا توجد بيانات كباتن لهذه الفترة
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </>
      ) : null}
    </div>
  );
}

/**
 * KPI card.
 *
 * `delta` is a real percentage change computed server-side against the previous
 * equal-length period. Three distinct states, deliberately kept separate:
 *
 *   number  -> render the signed change with a direction arrow
 *   null    -> comparison exists but the baseline was zero: render "جديد" (new).
 *              Growth from nothing is not a percentage.
 *   omitted -> no comparison available at all: render no footer.
 *
 * This card previously accepted a free-text `trend` string, which is how
 * hard-coded literals like "+14.2%" ended up displayed under a "compared to the
 * previous period" label with nothing computing them. The typed `delta` makes
 * that class of mistake impossible: there is no way to pass a decorative
 * string any more.
 */
function KPI({
  label,
  value,
  subtext,
  icon,
  delta,
  deltaUnit = 'percent',
  higherIsBetter = true,
  showComparison = true,
}: {
  label: string;
  value: string;
  subtext?: string;
  icon: React.ReactNode;
  delta?: number | null;
  /** 'percent' renders "12.5%"; 'points' renders "3.2 نقطة" for rate changes. */
  deltaUnit?: 'percent' | 'points';
  higherIsBetter?: boolean;
  showComparison?: boolean;
}) {
  const hasDelta = typeof delta === 'number';
  const isFlat = hasDelta && delta === 0;
  const isUp = hasDelta && delta > 0;
  // A rise is not automatically good — cancellations going up is bad. Callers
  // set higherIsBetter=false for those so the colour matches the meaning.
  const isGood = isUp === higherIsBetter;

  const magnitude = hasDelta ? Math.abs(delta).toLocaleString('ar-EG') : null;
  const deltaText = !hasDelta
    ? 'جديد'
    : deltaUnit === 'points'
      ? `${magnitude} نقطة`
      : `${magnitude}%`;

  const toneClass = !hasDelta
    ? 'text-text-secondary'
    : isFlat
      ? 'text-text-tertiary'
      : isGood
        ? 'text-primary-600 dark:text-primary-400'
        : 'text-error-main';

  return (
    <div className="group bg-surface-primary border border-border-primary rounded-xl p-5 shadow-xs space-y-3 transition-all duration-200 hover:border-primary-500/40 hover:shadow-md">
      <div className="flex items-center justify-between">
        <span className="text-xs font-bold text-text-secondary">{label}</span>
        <div className="w-10 h-10 rounded-xl bg-primary-500/10 flex items-center justify-center text-primary-500 transition-transform duration-200 group-hover:scale-105">
          {icon}
        </div>
      </div>

      <div>
        <p className="text-2xl font-black text-text-primary font-mono tracking-tight">{value}</p>
        {subtext && <p className="text-[11px] text-text-tertiary mt-1">{subtext}</p>}
      </div>

      {showComparison && (
        <div className="pt-2 border-t border-border-primary flex items-center justify-between text-xs">
          <span className="text-text-tertiary text-[11px]">مقارنة بالفترة السابقة</span>
          <span className={`font-bold flex items-center gap-0.5 ${toneClass}`}>
            {isFlat ? (
              <Minus className="w-3.5 h-3.5" />
            ) : hasDelta ? (
              isUp ? <ArrowUpRight className="w-3.5 h-3.5" /> : <ArrowDownRight className="w-3.5 h-3.5" />
            ) : null}
            {deltaText}
          </span>
        </div>
      )}
    </div>
  );
}