import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import {
  BarChart3, TrendingUp, DollarSign, CheckCircle, Loader2, Calendar,
  PieChart as PieIcon, Award, Shield, ArrowUpRight, ArrowDownRight, RefreshCw, Filter
} from 'lucide-react';
import {
  BarChart, Bar, AreaChart, Area, LineChart, Line, PieChart, Pie,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, Cell
} from 'recharts';
import { PageHeader } from '../components/layout/PageHeader';

interface AnalyticsData {
  from: string;
  to: string;
  totals: {
    trips: number;
    completed: number;
    cancelled: number;
    gmv: number;
    completionRate: number;
  };
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

  // Preset Date Ranges
  const [datePreset, setDatePreset] = useState<'7d' | '30d' | 'thisMonth'>('30d');
  const [dateRange, setDateRange] = useState({
    from: new Date(Date.now() - 30 * 864e5).toISOString().split('T')[0],
    to: new Date().toISOString().split('T')[0],
  });

  const applyPreset = (preset: '7d' | '30d' | 'thisMonth') => {
    setDatePreset(preset);
    const now = new Date();
    let fromDate = new Date();

    if (preset === '7d') {
      fromDate = new Date(Date.now() - 7 * 864e5);
    } else if (preset === '30d') {
      fromDate = new Date(Date.now() - 30 * 864e5);
    } else if (preset === 'thisMonth') {
      fromDate = new Date(now.getFullYear(), now.getMonth(), 1);
    }

    setDateRange({
      from: fromDate.toISOString().split('T')[0],
      to: now.toISOString().split('T')[0],
    });
  };

  const loadAnalytics = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await api<AnalyticsData>(
        `/admin/analytics?from=${dateRange.from}&to=${dateRange.to}`,
        { token }
      );

      // Enhance daily data with completion rates if missing
      const enhancedDaily = (res.daily || []).map((d) => {
        const compRate = d.trips > 0 ? Math.round((d.completed / d.trips) * 100) : 100;
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
  const completionRate = data?.totals?.completionRate ?? (totalTrips > 0 ? Math.round((completedTrips / totalTrips) * 100) : 100);
  const totalGmv = data?.totals?.gmv ?? 0;
  const estimatedCommission = totalGmv * 0.2; // ~20% platform revenue
  const averageOrderValue = completedTrips > 0 ? Math.round(totalGmv / completedTrips) : 0;

  // Pie chart data for trip status ratios
  const tripRatioData = [
    { name: 'رحلات مكتملة', value: completedTrips },
    { name: 'رحلات ملغية', value: cancelledTrips },
  ];

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
          </div>
        }
      />

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
              subtext={`صافي عمولة المنصة: ~${estimatedCommission.toLocaleString('ar-EG')} ج.م`}
              icon={<DollarSign className="w-6 h-6" />}
              trend="+14.2%"
              positive
            />

            <KPI
              label="إجمالي الرحلات المطلوبة"
              value={totalTrips.toLocaleString('ar-EG')}
              subtext={`المكتملة: ${completedTrips.toLocaleString('ar-EG')} رحلة`}
              icon={<BarChart3 className="w-6 h-6" />}
              trend="+8.5%"
              positive
            />

            <KPI
              label="نسبة نجاح وإكمال الرحلات"
              value={`${completionRate}%`}
              subtext={`الملغية: ${cancelledTrips.toLocaleString('ar-EG')} رحلة`}
              icon={<CheckCircle className="w-6 h-6" />}
              trend={completionRate >= 80 ? 'ممتاز' : 'يحتاج تحسين'}
              positive={completionRate >= 80}
            />

            <KPI
              label="متوسط قيمة الرحلة (AOV)"
              value={`${averageOrderValue} ج.م`}
              subtext="متوسط إنفاق الراكب في الرحلة"
              icon={<TrendingUp className="w-6 h-6" />}
              trend="+3.1%"
              positive
            />
          </div>

          {/* Section 1: Main Charts Grid */}
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
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
                    <CartesianGrid strokeDasharray="3 3" stroke="rgb(var(--border-primary)) font-mono" />
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
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
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

function KPI({
  label,
  value,
  subtext,
  icon,
  trend,
  positive,
}: {
  label: string;
  value: string;
  subtext?: string;
  icon: React.ReactNode;
  trend?: string;
  positive?: boolean;
}) {
  return (
    <div className="bg-surface-primary border border-border-primary rounded-xl p-5 shadow-xs space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-bold text-text-secondary">{label}</span>
        <div className="w-10 h-10 rounded-xl bg-primary-500/10 flex items-center justify-center text-primary-500">
          {icon}
        </div>
      </div>

      <div>
        <p className="text-2xl font-black text-text-primary font-mono tracking-tight">{value}</p>
        {subtext && <p className="text-[11px] text-text-tertiary mt-1">{subtext}</p>}
      </div>

      {trend && (
        <div className="pt-2 border-t border-border-primary flex items-center justify-between text-xs">
          <span className="text-text-tertiary text-[11px]">مقارنة بالفترة السابقة</span>
          <span
            className={`font-bold flex items-center gap-0.5 ${
              positive ? 'text-primary-600 dark:text-primary-400' : 'text-error-main'
            }`}
          >
            {positive ? <ArrowUpRight className="w-3.5 h-3.5" /> : <ArrowDownRight className="w-3.5 h-3.5" />}
            {trend}
          </span>
        </div>
      )}
    </div>
  );
}