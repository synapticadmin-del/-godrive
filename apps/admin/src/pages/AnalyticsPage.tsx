import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import {
  BarChart3, TrendingUp, DollarSign, CheckCircle, Calendar,
  PieChart as PieIcon, Award, ArrowUpRight, ArrowDownRight, RefreshCw, Minus, Download, Users, Zap
} from 'lucide-react';
import {
  BarChart, Bar, AreaChart, Area, PieChart, Pie,
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

interface AnalyticsDeltas {
  trips: number | null;
  completed: number | null;
  gmv: number | null;
  commission: number | null;
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
  cyan: '#06b6d4',
};

const PIE_COLORS = ['#6bb522', '#ef4444', '#f59e0b', '#3b82f6'];

type DatePresetOption = 'today' | '7d' | '30d' | 'thisYear';

function toLocalYmd(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function presetRange(preset: DatePresetOption): { from: string; to: string } {
  const now = new Date();
  const to = toLocalYmd(now);

  if (preset === 'today') {
    return { from: to, to };
  }

  if (preset === 'thisYear') {
    return { from: `${now.getFullYear()}-01-01`, to };
  }

  const days = preset === '7d' ? 7 : 30;
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (days - 1));
  return { from: toLocalYmd(start), to };
}

function CustomTooltip({ active, payload, label }: any) {
  if (active && payload && payload.length) {
    return (
      <div className="bg-surface-primary/95 backdrop-blur-md border border-border-primary rounded-xl p-3.5 shadow-2xl text-right dir-rtl min-w-[180px]">
        <p className="font-bold text-text-primary text-xs mb-2 border-b border-border-primary/80 pb-1.5 font-mono flex items-center justify-between">
          <span>التاريخ</span>
          <span className="text-primary-500">{label}</span>
        </p>
        {payload.map((entry: any, i: number) => (
          <div key={i} className="text-xs flex items-center justify-between gap-4 py-1">
            <span className="font-extrabold text-text-primary font-mono dir-ltr">
              {typeof entry.value === 'number' ? entry.value.toLocaleString('ar-EG') : entry.value}
            </span>
            <div className="flex items-center gap-1.5 text-text-secondary font-medium">
              <span>{entry.name}</span>
              <span className="w-2.5 h-2.5 rounded-full inline-block shadow-xs" style={{ backgroundColor: entry.color }} />
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

  // Time-range Preset Filter
  const [datePreset, setDatePreset] = useState<DatePresetOption>('30d');
  const [dateRange, setDateRange] = useState(() => presetRange('30d'));

  const applyPreset = (preset: DatePresetOption) => {
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

      const enhancedDaily = (res.daily || []).map((d) => {
        const compRate = d.trips > 0 ? Math.round((d.completed / d.trips) * 100) : 0;
        const cancelledCount = d.cancelled ?? Math.max(0, d.trips - d.completed);
        return {
          ...d,
          completionRate: compRate,
          cancelled: cancelledCount,
        };
      });

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

  // Metrics calculation
  const totalTrips = data?.totals?.trips ?? 0;
  const completedTrips = data?.totals?.completed ?? 0;
  const cancelledTrips = data?.totals?.cancelled ?? Math.max(0, totalTrips - completedTrips);
  const completionRate =
    data?.totals?.completionRate ?? (totalTrips > 0 ? Math.round((completedTrips / totalTrips) * 100) : 0);
  const totalGmv = data?.totals?.gmv ?? 0;
  const totalCommission = data?.totals?.commission ?? 0;
  const averageOrderValue = completedTrips > 0 ? Math.round(totalGmv / completedTrips) : 0;

  const isEmptyRange = !!data && totalTrips === 0 && (data.daily?.length ?? 0) === 0;
  const deltas = data?.deltas;
  const hasComparison = !!data?.previous;

  const tripRatioData = [
    { name: 'رحلات مكتملة', value: completedTrips },
    { name: 'رحلات ملغية', value: cancelledTrips },
  ];

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
    setExportNotice(`تم تصدير ${n.toLocaleString('ar-EG')} يوم بنجاح`);
    window.setTimeout(() => setExportNotice(null), 4000);
  };

  return (
    <div className="space-y-6 animate-fade-in" dir="rtl">
      {/* Header & Interactive Time-Range Controls */}
      <PageHeader
        title="مؤشرات الأداء والتحليلات الشاملة"
        subtitle="متابعة الإيرادات، نمو الرحلات اليومي، وأداء شبكة الكباتن والتطبيقات"
        actions={
          <div className="flex flex-wrap items-center gap-2">
            {/* Presets: Today, 7 Days, 30 Days, Year */}
            <div className="flex items-center bg-surface-secondary/80 backdrop-blur-md p-1 rounded-xl border border-border-primary shadow-xs">
              <button
                onClick={() => applyPreset('today')}
                className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${
                  datePreset === 'today'
                    ? 'bg-primary-500 text-white shadow-md'
                    : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                اليوم
              </button>
              <button
                onClick={() => applyPreset('7d')}
                className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${
                  datePreset === '7d'
                    ? 'bg-primary-500 text-white shadow-md'
                    : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                7 أيام
              </button>
              <button
                onClick={() => applyPreset('30d')}
                className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${
                  datePreset === '30d'
                    ? 'bg-primary-500 text-white shadow-md'
                    : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                30 يوم
              </button>
              <button
                onClick={() => applyPreset('thisYear')}
                className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${
                  datePreset === 'thisYear'
                    ? 'bg-primary-500 text-white shadow-md'
                    : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                هذا العام
              </button>
            </div>

            {/* Custom Dates Input */}
            <div className="flex items-center gap-1.5 bg-surface-primary/90 backdrop-blur-md border border-border-primary px-3 py-1.5 rounded-xl text-xs shadow-xs">
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
              className="p-2.5 rounded-xl bg-surface-primary border border-border-primary hover:bg-surface-hover text-text-secondary transition-all hover:scale-105 shadow-xs"
              title="تحديث البيانات"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-primary-500' : ''}`} />
            </button>

            <button
              onClick={handleExportCsv}
              disabled={!data || (data.daily?.length ?? 0) === 0}
              className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-bold rounded-xl bg-surface-secondary border border-border-primary text-text-secondary hover:text-text-primary hover:border-primary-500/40 transition-all disabled:opacity-40 disabled:cursor-not-allowed shadow-xs"
            >
              <Download className="w-4 h-4" />
              تصدير CSV
            </button>
          </div>
        }
      />

      {exportNotice && (
        <div className="p-3 bg-success-main/10 border border-success-main/30 rounded-2xl text-success-main text-sm font-bold flex items-center gap-2 shadow-xs">
          <Download className="w-4 h-4 shrink-0" />
          {exportNotice}
        </div>
      )}

      {error && (
        <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-2xl text-error-main text-sm font-bold">
          {error}
        </div>
      )}

      {/* Loading Skeleton */}
      {loading ? (
        <div className="space-y-6">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {[...Array(4)].map((_, i) => (
              <div key={i} className="bg-surface-primary/80 border border-border-primary rounded-2xl p-5 animate-pulse space-y-3">
                <div className="flex justify-between items-center">
                  <div className="h-4 bg-surface-tertiary rounded w-1/2" />
                  <div className="w-10 h-10 bg-surface-tertiary rounded-xl" />
                </div>
                <div className="h-8 bg-surface-tertiary rounded w-3/4" />
                <div className="h-3 bg-surface-tertiary rounded w-2/3" />
              </div>
            ))}
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            <div className="lg:col-span-7 bg-surface-primary/80 border border-border-primary rounded-2xl p-6 h-80 animate-pulse" />
            <div className="lg:col-span-5 bg-surface-primary/80 border border-border-primary rounded-2xl p-6 h-80 animate-pulse" />
          </div>
        </div>
      ) : data ? (
        <>
          {/* Glowing KPI Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <KPI
              label="إجمالي حجم المعاملات (GMV)"
              value={`${totalGmv.toLocaleString('ar-EG')} ج.م`}
              subtext={`صافي عمولة المنصة: ${totalCommission.toLocaleString('ar-EG')} ج.م`}
              icon={<DollarSign className="w-6 h-6" />}
              delta={deltas?.gmv}
              showComparison={hasComparison}
              badgeColor="primary"
            />

            <KPI
              label="إجمالي الرحلات المطلوبة"
              value={totalTrips.toLocaleString('ar-EG')}
              subtext={`المكتملة: ${completedTrips.toLocaleString('ar-EG')} رحلة`}
              icon={<BarChart3 className="w-6 h-6" />}
              delta={deltas?.trips}
              showComparison={hasComparison}
              badgeColor="cyan"
            />

            <KPI
              label="نسبة نجاح وإكمال الرحلات"
              value={`${completionRate}%`}
              subtext={`الملغية: ${cancelledTrips.toLocaleString('ar-EG')} رحلة`}
              icon={<CheckCircle className="w-6 h-6" />}
              delta={deltas?.completionRatePoints}
              deltaUnit="points"
              showComparison={hasComparison}
              badgeColor="success"
            />

            <KPI
              label="متوسط قيمة الرحلة (AOV)"
              value={`${averageOrderValue.toLocaleString('ar-EG')} ج.م`}
              subtext="متوسط إنفاق الراكب للرحلة"
              icon={<TrendingUp className="w-6 h-6" />}
              showComparison={false}
              badgeColor="purple"
            />
          </div>

          {/* Empty State */}
          {isEmptyRange && (
            <div className="bg-surface-primary border border-border-primary border-dashed rounded-2xl p-12 text-center shadow-xs space-y-4">
              <div className="w-16 h-16 mx-auto rounded-3xl bg-surface-secondary flex items-center justify-center text-text-tertiary">
                <Calendar className="w-8 h-8" />
              </div>
              <div>
                <h3 className="text-base font-bold text-text-primary">لا توجد رحلات أو بيانات لهذه الفترة</h3>
                <p className="text-xs text-text-tertiary mt-1.5 max-w-md mx-auto">
                  لم يتم تسجيل رحلات بين {dateRange.from} و {dateRange.to}. قم باختيار نطاق زمني أكبر مثل "30 يوم" أو "هذا العام".
                </p>
              </div>
              <div className="flex items-center justify-center gap-2 pt-2">
                <button
                  onClick={() => applyPreset('30d')}
                  className="px-4 py-2 rounded-xl text-xs font-bold bg-primary-500 text-white hover:bg-primary-600 shadow-md transition-all"
                >
                  عرض آخر 30 يوم
                </button>
              </div>
            </div>
          )}

          {/* Charts Grid */}
          <div className={`grid grid-cols-1 lg:grid-cols-12 gap-6 ${isEmptyRange ? 'hidden' : ''}`}>
            {/* Revenue & GMV Area Chart (7 Cols) */}
            <div className="lg:col-span-7 bg-surface-primary/80 backdrop-blur-xl border border-border-primary/80 rounded-2xl p-6 shadow-md space-y-4">
              <div className="flex items-center justify-between border-b border-border-primary/80 pb-4">
                <div>
                  <h3 className="font-extrabold text-text-primary text-base flex items-center gap-2">
                    <TrendingUp className="w-5 h-5 text-primary-500" />
                    تطور الإيرادات وحجم المبيعات (GMV)
                  </h3>
                  <p className="text-xs text-text-tertiary">متابعة الأرباح وحركة المبيعات خلال الفترة المحددة</p>
                </div>
                <span className="px-3 py-1 bg-primary-500/10 text-primary-600 dark:text-primary-400 border border-primary-500/20 text-xs font-black rounded-xl font-mono shadow-xs">
                  {totalGmv.toLocaleString('ar-EG')} ج.م
                </span>
              </div>

              <div className="h-[320px] w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={data.daily} margin={{ top: 10, right: 10, left: 10, bottom: 0 }}>
                    <defs>
                      <linearGradient id="gmvGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#6bb522" stopOpacity={0.4} />
                        <stop offset="95%" stopColor="#6bb522" stopOpacity={0.0} />
                      </linearGradient>
                      <linearGradient id="commissionGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#8b5cf6" stopOpacity={0.4} />
                        <stop offset="95%" stopColor="#8b5cf6" stopOpacity={0.0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="rgba(150, 150, 150, 0.12)" />
                    <XAxis
                      dataKey="day"
                      tick={{ fill: 'currentColor', opacity: 0.7, fontSize: 11 }}
                      axisLine={{ stroke: 'rgba(150,150,150,0.2)' }}
                    />
                    <YAxis
                      allowDecimals={false}
                      tickFormatter={(v) => `${v.toLocaleString('ar-EG')}`}
                      tick={{ fill: 'currentColor', opacity: 0.7, fontSize: 11 }}
                      axisLine={{ stroke: 'rgba(150,150,150,0.2)' }}
                    />
                    <Tooltip content={<CustomTooltip />} />
                    <Legend wrapperStyle={{ paddingTop: '12px', fontSize: '12px' }} />
                    <Area
                      type="monotone"
                      dataKey="gmv"
                      name="حجم المبيعات (GMV)"
                      stroke="#6bb522"
                      strokeWidth={3}
                      dot={{ r: 4, fill: '#6bb522', strokeWidth: 2, stroke: '#ffffff' }}
                      activeDot={{ r: 6, strokeWidth: 0 }}
                      fill="url(#gmvGradient)"
                    />
                    <Area
                      type="monotone"
                      dataKey="commission"
                      name="صافي عمولة المنصة"
                      stroke="#8b5cf6"
                      strokeWidth={2.5}
                      dot={{ r: 3, fill: '#8b5cf6', strokeWidth: 2, stroke: '#ffffff' }}
                      activeDot={{ r: 5, strokeWidth: 0 }}
                      fill="url(#commissionGradient)"
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>

            {/* Trip Completion Donut (5 Cols) */}
            <div className="lg:col-span-5 bg-surface-primary/80 backdrop-blur-xl border border-border-primary/80 rounded-2xl p-6 shadow-md flex flex-col justify-between space-y-4">
              <div className="border-b border-border-primary/80 pb-4">
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
                      paddingAngle={6}
                      dataKey="value"
                    >
                      {tripRatioData.map((_, index) => (
                        <Cell key={`cell-${index}`} fill={PIE_COLORS[index % PIE_COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip content={<CustomTooltip />} />
                  </PieChart>
                </ResponsiveContainer>

                {/* Center Badge */}
                <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                  <span className="text-3xl font-black text-text-primary font-mono">{completionRate}%</span>
                  <span className="text-xs font-bold text-text-tertiary mt-0.5">نسبة الإكمال</span>
                </div>
              </div>

              {/* Legend Grid */}
              <div className="grid grid-cols-2 gap-3 pt-3 border-t border-border-primary/80 text-center">
                <div className="p-2.5 rounded-xl bg-primary-500/10 border border-primary-500/20">
                  <p className="text-xs text-primary-600 dark:text-primary-400 font-bold">رحلات مكتملة</p>
                  <p className="text-base font-black font-mono text-text-primary mt-0.5">{completedTrips.toLocaleString('ar-EG')}</p>
                </div>
                <div className="p-2.5 rounded-xl bg-error-main/10 border border-error-main/20">
                  <p className="text-xs text-error-main font-bold">رحلات ملغية</p>
                  <p className="text-base font-black font-mono text-text-primary mt-0.5">{cancelledTrips.toLocaleString('ar-EG')}</p>
                </div>
              </div>
            </div>
          </div>

          {/* Section 2: Daily Trips Breakdown & Top Captains Leaderboard */}
          <div className={`grid grid-cols-1 lg:grid-cols-12 gap-6 ${isEmptyRange ? 'hidden' : ''}`}>
            {/* Daily Trips Bar Chart (7 Cols) */}
            <div className="lg:col-span-7 bg-surface-primary/80 backdrop-blur-xl border border-border-primary/80 rounded-2xl p-6 shadow-md space-y-4">
              <div className="flex items-center justify-between border-b border-border-primary/80 pb-4">
                <h3 className="font-extrabold text-text-primary text-base flex items-center gap-2">
                  <BarChart3 className="w-5 h-5 text-primary-500" />
                  حركة الرحلات اليومية (المطلوبة vs المكتملة)
                </h3>
                <span className="text-xs font-bold text-text-tertiary font-mono">النمو اليومي</span>
              </div>

              <div className="h-[280px] w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={data.daily} margin={{ top: 10, right: 10, left: 10, bottom: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="rgba(150, 150, 150, 0.12)" />
                    <XAxis
                      dataKey="day"
                      tick={{ fill: 'currentColor', opacity: 0.7, fontSize: 11 }}
                      axisLine={{ stroke: 'rgba(150,150,150,0.2)' }}
                    />
                    <YAxis
                      allowDecimals={false}
                      tickFormatter={(v) => `${v}`}
                      tick={{ fill: 'currentColor', opacity: 0.7, fontSize: 11 }}
                      axisLine={{ stroke: 'rgba(150,150,150,0.2)' }}
                    />
                    <Tooltip content={<CustomTooltip />} />
                    <Legend wrapperStyle={{ paddingTop: '12px', fontSize: '12px' }} />
                    <Bar
                      dataKey="trips"
                      name="إجمالي المطلوبة"
                      fill="#3b82f6"
                      barSize={24}
                      radius={[6, 6, 0, 0]}
                    />
                    <Bar
                      dataKey="completed"
                      name="المكتملة"
                      fill="#6bb522"
                      barSize={24}
                      radius={[6, 6, 0, 0]}
                    />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>

            {/* Top Captains Leaderboard Table (5 Cols) */}
            <div className="lg:col-span-5 bg-surface-primary/80 backdrop-blur-xl border border-border-primary/80 rounded-2xl p-6 shadow-md space-y-4 flex flex-col">
              <div className="flex items-center justify-between border-b border-border-primary/80 pb-4">
                <h3 className="font-extrabold text-text-primary text-base flex items-center gap-2">
                  <Award className="w-5 h-5 text-amber-500" />
                  أفضل الكباتن تحقيقاً للإيرادات
                </h3>
                <span className="text-xs font-extrabold text-primary-600 dark:text-primary-400 bg-primary-500/10 px-2.5 py-1 rounded-full border border-primary-500/20 shadow-xs">
                  Leaderboard
                </span>
              </div>

              <div className="overflow-x-auto flex-1">
                <table className="w-full text-right text-sm">
                  <thead className="border-b border-border-primary text-xs font-semibold text-text-tertiary">
                    <tr>
                      <th className="py-2.5 px-3">#</th>
                      <th className="py-2.5 px-3">الكابتن</th>
                      <th className="py-2.5 px-3 text-center">الرحلات</th>
                      <th className="py-2.5 px-3 text-left">GMV الإجمالي</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border-primary/50">
                    {data.topCaptains.map((c, i) => (
                      <tr key={c.captain_id} className="hover:bg-surface-hover/70 transition-colors">
                        <td className="py-3 px-3">
                          <span
                            className={`w-6 h-6 rounded-full inline-flex items-center justify-center text-xs font-extrabold shadow-xs ${
                              i === 0
                                ? 'bg-amber-500/20 text-amber-500 border border-amber-500/40'
                                : i === 1
                                ? 'bg-slate-400/20 text-slate-400 border border-slate-400/40'
                                : i === 2
                                ? 'bg-amber-700/20 text-amber-700 border border-amber-700/40'
                                : 'text-text-tertiary bg-surface-secondary'
                            }`}
                          >
                            {i + 1}
                          </span>
                        </td>
                        <td className="py-3 px-3">
                          <p className="font-bold text-text-primary text-xs truncate max-w-[140px]">
                            {c.name || 'كابتن مجهول'}
                          </p>
                          <p className="text-[10px] text-text-tertiary font-mono truncate max-w-[140px]">
                            {c.email}
                          </p>
                        </td>
                        <td className="py-3 px-3 text-center font-mono font-bold text-xs">
                          {c.trips}
                        </td>
                        <td className="py-3 px-3 text-left font-mono font-extrabold text-xs text-primary-600 dark:text-primary-400">
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

function KPI({
  label,
  value,
  subtext,
  icon,
  delta,
  deltaUnit = 'percent',
  higherIsBetter = true,
  showComparison = true,
  badgeColor = 'primary',
}: {
  label: string;
  value: string;
  subtext?: string;
  icon: React.ReactNode;
  delta?: number | null;
  deltaUnit?: 'percent' | 'points';
  higherIsBetter?: boolean;
  showComparison?: boolean;
  badgeColor?: 'primary' | 'cyan' | 'success' | 'purple';
}) {
  const hasDelta = typeof delta === 'number';
  const isFlat = hasDelta && delta === 0;
  const isUp = hasDelta && delta > 0;
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

  const badgeBgMap = {
    primary: 'bg-primary-500/10 text-primary-500 border-primary-500/20',
    cyan: 'bg-cyan-500/10 text-cyan-500 border-cyan-500/20',
    success: 'bg-emerald-500/10 text-emerald-500 border-emerald-500/20',
    purple: 'bg-purple-500/10 text-purple-500 border-purple-500/20',
  };

  return (
    <div className="group bg-surface-primary/80 backdrop-blur-xl border border-border-primary/80 rounded-2xl p-5 shadow-md space-y-3 transition-all duration-300 hover:border-primary-500/50 hover:shadow-xl hover:-translate-y-0.5">
      <div className="flex items-center justify-between">
        <span className="text-xs font-extrabold text-text-secondary">{label}</span>
        <div
          className={`w-11 h-11 rounded-2xl border flex items-center justify-center transition-transform duration-300 group-hover:scale-110 shadow-xs ${badgeBgMap[badgeColor]}`}
        >
          {icon}
        </div>
      </div>

      <div>
        <p className="text-2xl font-black text-text-primary font-mono tracking-tight">{value}</p>
        {subtext && <p className="text-[11px] text-text-tertiary mt-1 font-medium">{subtext}</p>}
      </div>

      {showComparison && (
        <div className="pt-2 border-t border-border-primary/80 flex items-center justify-between text-xs">
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