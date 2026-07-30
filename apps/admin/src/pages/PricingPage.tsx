import { FormEvent, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import {
  DollarSign, Save, Loader2, Check, MapPin, Calculator, Plus, Search,
  Car, AlertCircle, RefreshCw, Layers
} from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';

interface PricingRule {
  city: string;
  currency: string;
  base_fare: number;
  per_km: number;
  per_min: number;
  booking_fee: number;
  min_fare: number;
  commission_rate: number;
  category?: string;
}

/** A row of the vehicle_types table, from GET /admin/vehicle-types. */
interface VehicleType {
  id: string;
  name: string;
  multiplier: number;
  active: number;
}

/** Arabic labels for the seeded vehicle categories; falls back to the row's
 *  English `name` for any category an admin adds later. */
const VEHICLE_NAMES_AR: Record<string, string> = {
  economy: 'اقتصادي',
  comfort: 'راحة',
  xl: 'عائلي (XL)',
};

const CITY_NAMES_AR: Record<string, string> = {
  cairo: 'القاهرة الكبرى',
  alex: 'الإسكندرية والساحل',
  giza: 'الجيزة والمدن الجديدة',
  mansoura: 'المنصورة الدقهلية',
  tanta: 'طنطا والغربية',
  assuit: 'أسيوط',
};

export default function PricingPage() {
  const { token } = useAuth();
  const [pricing, setPricing] = useState<PricingRule[]>([]);
  const [selected, setSelected] = useState<PricingRule | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  // Vehicle categories come from the vehicle_types table rather than a hardcoded
  // list. The previous hardcoded trio (economy/standard/comfort) did not match
  // the database, where the rows are economy/comfort/xl.
  const [vehicleTypes, setVehicleTypes] = useState<VehicleType[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  // Fare estimator inputs. These were fixed at 8 km / 12 min, so the estimate
  // could only ever describe one hypothetical trip.
  const [estimateDistanceKm, setEstimateDistanceKm] = useState(8);
  const [estimateTimeMin, setEstimateTimeMin] = useState(12);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showAddModal, setShowAddModal] = useState(false);

  // New city state
  const [newCity, setNewCity] = useState({
    city: '',
    currency: 'EGP',
    base_fare: 12,
    per_km: 4.5,
    per_min: 0.5,
    booking_fee: 3,
    min_fare: 20,
    commission_rate: 0.2,
  });

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await api<{ pricing: PricingRule[] }>('/admin/pricing', { token });
      setPricing(res.pricing || []);
      if (res.pricing && res.pricing.length > 0) {
        setSelected((prev) => (prev ? res.pricing.find((p) => p.city === prev.city) || res.pricing[0] : res.pricing[0]));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'فشل تحميل قواعد التسعير');
    } finally {
      setLoading(false);
    }
  };

  const loadVehicleTypes = async () => {
    try {
      const res = await api<{ vehicleTypes: VehicleType[] }>('/admin/vehicle-types', { token });
      const types = res.vehicleTypes || [];
      setVehicleTypes(types);
      // Default to the 1.0-multiplier category when present so the estimate
      // opens on the unmodified fare; otherwise fall back to the first row.
      setSelectedCategory((prev) => prev ?? (types.find((t) => t.multiplier === 1)?.id ?? types[0]?.id ?? null));
    } catch (err) {
      // A missing category list should not block the pricing editor, which is
      // the primary purpose of this page — the estimator just falls back to a
      // 1.0 multiplier.
      console.error('failed to load vehicle types', err);
    }
  };

  useEffect(() => {
    load();
    loadVehicleTypes();
  }, [token]);

  const onSave = async (e: FormEvent) => {
    e.preventDefault();
    if (!selected) return;
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await api(`/admin/pricing/${selected.city}`, {
        method: 'PUT',
        token,
        body: JSON.stringify({
          currency: selected.currency || 'EGP',
          baseFare: Number(selected.base_fare),
          perKm: Number(selected.per_km),
          perMin: Number(selected.per_min),
          bookingFee: Number(selected.booking_fee),
          minFare: Number(selected.min_fare),
          commissionRate: Number(selected.commission_rate),
        }),
      });
      setMessage(`تم حفظ تسعير مدينة (${CITY_NAMES_AR[selected.city] || selected.city}) بنجاح`);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'فشل حفظ التسعير');
    } finally {
      setSaving(false);
    }
  };

  const handleAddCity = async (e: FormEvent) => {
    e.preventDefault();
    if (!newCity.city.trim()) return;
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      await api(`/admin/pricing/${newCity.city.toLowerCase().trim()}`, {
        method: 'PUT',
        token,
        body: JSON.stringify({
          currency: newCity.currency,
          baseFare: Number(newCity.base_fare),
          perKm: Number(newCity.per_km),
          perMin: Number(newCity.per_min),
          bookingFee: Number(newCity.booking_fee),
          minFare: Number(newCity.min_fare),
          commissionRate: Number(newCity.commission_rate),
        }),
      });
      setMessage(`تم إضافة تسعير المدينة الجديدة (${newCity.city}) بنجاح`);
      setShowAddModal(false);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'فشل إضافة المدينة');
    } finally {
      setSaving(false);
    }
  };

  // Fare estimate for the distance/duration the admin entered.
  //
  // This mirrors calculateFare() in packages/shared/src/index.ts, which is what
  // the API actually charges. Two details the previous inline version got wrong:
  // the vehicle multiplier applies to the base, distance and time components but
  // NOT to the booking fee, and the result is rounded to 2 decimals before the
  // min-fare clamp. Reproducing it by hand is a duplication we accept for now
  // because the admin app does not yet depend on @synaptic-go/shared — switching
  // to the shared function is tracked as part of the data-layer work.
  const round2 = (n: number) => Math.round(n * 100) / 100;

  const activeMultiplier =
    vehicleTypes.find((t) => t.id === selectedCategory)?.multiplier ?? 1;

  const estimate = (() => {
    if (!selected) {
      return { total: 0, commission: 0, driverEarnings: 0, baseFare: 0, distanceFare: 0, timeFare: 0 };
    }
    const km = Number.isFinite(estimateDistanceKm) ? Math.max(0, estimateDistanceKm) : 0;
    const min = Number.isFinite(estimateTimeMin) ? Math.max(0, estimateTimeMin) : 0;

    const baseFare = selected.base_fare * activeMultiplier;
    const distanceFare = km * selected.per_km * activeMultiplier;
    const timeFare = min * selected.per_min * activeMultiplier;
    const raw = baseFare + distanceFare + timeFare + selected.booking_fee;
    const total = Math.max(selected.min_fare, round2(raw));
    const commission = round2(total * selected.commission_rate);

    return {
      total,
      commission,
      driverEarnings: round2(total - commission),
      baseFare: round2(baseFare),
      distanceFare: round2(distanceFare),
      timeFare: round2(timeFare),
    };
  })();

  const estimatedTotal = estimate.total;
  const estimatedCommission = estimate.commission;
  const estimatedDriverEarnings = estimate.driverEarnings;
  // True when the computed fare was raised to the city's minimum, which is worth
  // flagging: it means the per-km/per-min values are not what the rider pays.
  const minFareApplied = selected ? round2(estimatedTotal) === round2(selected.min_fare) : false;

  const filteredPricing = pricing.filter(
    (p) =>
      p.city.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (CITY_NAMES_AR[p.city] && CITY_NAMES_AR[p.city].includes(searchQuery))
  );

  return (
    <div className="space-y-6 animate-fade-in" dir="rtl">
      <PageHeader
        title="التسعير وحساب الرحلات"
        subtitle="إدارة شرائح الأسعار، نسبة عمولة المنصة، ورسوم الرحلات لكل محافظة"
      >
        <button
          onClick={() => setShowAddModal(true)}
          className="btn-primary gap-2 text-sm"
        >
          <Plus className="w-4 h-4" />
          إضافة تسعير مدينة جديدة
        </button>
      </PageHeader>

      {/* Alerts */}
      {error && (
        <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main flex items-center justify-between animate-slide-down">
          <div className="flex items-center gap-3">
            <AlertCircle className="w-5 h-5 flex-shrink-0" />
            <span>{error}</span>
          </div>
          <button onClick={() => setError(null)} className="text-xs hover:underline">إغلاق</button>
        </div>
      )}

      {message && (
        <div className="p-4 bg-primary-500/10 border border-primary-500/30 rounded-xl text-primary-600 dark:text-primary-400 flex items-center justify-between animate-slide-down">
          <div className="flex items-center gap-2">
            <Check className="w-5 h-5 flex-shrink-0 text-primary-500" />
            <span className="font-medium text-sm">{message}</span>
          </div>
          <button onClick={() => setMessage(null)} className="text-xs hover:underline">إغلاق</button>
        </div>
      )}

      {/* Vehicle category selector — drives the fare estimate below via each
          category's real multiplier from the vehicle_types table. The previous
          version was a hardcoded economy/standard/comfort toggle whose value was
          never read by anything. */}
      {vehicleTypes.length > 0 && (
        <div className="bg-surface-primary border border-border-primary rounded-xl p-3 flex flex-wrap items-center justify-between gap-3 shadow-xs">
          <div className="flex items-center gap-2">
            <Car className="w-5 h-5 text-primary-500" />
            <span className="text-sm font-semibold text-text-primary">فئة المركبة:</span>
            <span className="text-xs text-text-tertiary">
              تُستخدم في حساب التقدير أدناه — أسعار المدينة نفسها موحدة لكل الفئات
            </span>
          </div>
          <div className="flex items-center gap-1.5 bg-surface-secondary p-1 rounded-lg border border-border-primary">
            {vehicleTypes.map((vt) => (
              <button
                key={vt.id}
                type="button"
                onClick={() => setSelectedCategory(vt.id)}
                aria-pressed={selectedCategory === vt.id}
                className={`px-3 py-1.5 rounded-md text-xs font-bold transition-all ${
                  selectedCategory === vt.id
                    ? 'bg-primary-500 text-white shadow-xs'
                    : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                {VEHICLE_NAMES_AR[vt.id] || vt.name}
                <span className="mr-1.5 font-mono opacity-75">×{vt.multiplier}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Main Grid: City List & Form */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        {/* Left Column: Cities Table (5 Cols) */}
        <div className="lg:col-span-5 bg-surface-primary border border-border-primary rounded-xl shadow-xs overflow-hidden flex flex-col">
          {/* Table Header & Search */}
          <div className="p-4 border-b border-border-primary space-y-3 bg-surface-secondary/30">
            <div className="flex items-center justify-between">
              <h3 className="font-bold text-text-primary text-base flex items-center gap-2">
                <MapPin className="w-5 h-5 text-primary-500" />
                المناطق المتاحة ({pricing.length})
              </h3>
              <button
                onClick={load}
                className="p-1.5 rounded-lg hover:bg-surface-hover text-text-tertiary hover:text-text-primary transition-colors"
                title="تحديث البيانات"
              >
                <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
              </button>
            </div>
            <div className="relative">
              <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-tertiary" />
              <input
                type="search"
                placeholder="ابحث باسم المدينة..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="input pr-9 py-1.5 text-xs rounded-lg"
              />
            </div>
          </div>

          {/* Table */}
          <div className="overflow-x-auto max-h-[520px] overflow-y-auto">
            {loading ? (
              <div className="p-12 text-center text-text-tertiary space-y-2">
                <Loader2 className="w-8 h-8 animate-spin mx-auto text-primary-500" />
                <p className="text-xs">جاري تحميل قواعد التسعير...</p>
              </div>
            ) : filteredPricing.length === 0 ? (
              <div className="p-8 text-center text-text-tertiary">
                لا توجد نتائج مطابقة للبحث
              </div>
            ) : (
              <table className="w-full text-right text-sm">
                <thead className="sticky top-0 bg-surface-secondary border-b border-border-primary z-10 text-xs font-semibold text-text-tertiary">
                  <tr>
                    <th className="px-4 py-2.5">المدينة</th>
                    <th className="px-3 py-2.5">فتح العداد</th>
                    <th className="px-3 py-2.5">لكل كم</th>
                    <th className="px-3 py-2.5">العمولة</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-primary/50">
                  {filteredPricing.map((p) => {
                    const isSelected = selected?.city === p.city;
                    return (
                      <tr
                        key={p.city}
                        onClick={() => setSelected({ ...p })}
                        className={`cursor-pointer transition-all duration-150 ${
                          isSelected
                            ? 'bg-primary-500/10 border-r-4 border-r-primary-500 font-semibold'
                            : 'hover:bg-surface-hover'
                        }`}
                      >
                        <td className="px-4 py-3">
                          <div className="font-bold text-text-primary">
                            {CITY_NAMES_AR[p.city] || p.city}
                          </div>
                          <div className="text-[11px] text-text-tertiary uppercase font-mono">
                            {p.city}
                          </div>
                        </td>
                        <td className="px-3 py-3 font-mono text-text-secondary">
                          {p.base_fare} <span className="text-[10px]">ج.م</span>
                        </td>
                        <td className="px-3 py-3 font-mono text-text-secondary">
                          {p.per_km} <span className="text-[10px]">ج.م</span>
                        </td>
                        <td className="px-3 py-3">
                          <span className="px-2 py-0.5 rounded-full text-xs font-bold bg-primary-500/10 text-primary-600 dark:text-primary-400 border border-primary-500/20">
                            {Math.round(p.commission_rate * 100)}%
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
        </div>

        {/* Right Column: Edit Form & Calculator (7 Cols) */}
        {selected ? (
          <div className="lg:col-span-7 space-y-6">
            <form
              onSubmit={onSave}
              className="bg-surface-primary border border-border-primary rounded-xl p-5 shadow-xs space-y-5"
            >
              {/* Form Header */}
              <div className="flex items-center justify-between border-b border-border-primary pb-4">
                <div>
                  <h3 className="text-lg font-extrabold text-text-primary flex items-center gap-2">
                    <DollarSign className="w-5 h-5 text-primary-500" />
                    تعديل تسعير: {CITY_NAMES_AR[selected.city] || selected.city}
                  </h3>
                  <p className="text-xs text-text-tertiary mt-0.5">
                    الرمز التعريفي للمنطقة: <span className="font-mono">{selected.city}</span> · العملة: {selected.currency || 'EGP'}
                  </p>
                </div>
                <span className="px-3 py-1 bg-primary-500/10 text-primary-600 dark:text-primary-400 border border-primary-500/20 text-xs font-bold rounded-full">
                  نشط حالياً
                </span>
              </div>

              {/* Form Inputs Grid */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1.5">
                    الأجرة الأساسية (فتح العداد)
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      step="0.1"
                      value={selected.base_fare}
                      onChange={(e) =>
                        setSelected({ ...selected, base_fare: Number(e.target.value) })
                      }
                      className="input pl-12 font-mono font-bold"
                    />
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-text-tertiary">
                      ج.م
                    </span>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1.5">
                    سعر الكيلومتر الواحد
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      step="0.1"
                      value={selected.per_km}
                      onChange={(e) =>
                        setSelected({ ...selected, per_km: Number(e.target.value) })
                      }
                      className="input pl-12 font-mono font-bold"
                    />
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-text-tertiary">
                      ج.م/كم
                    </span>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1.5">
                    سعر الدقيقة الواحدة (وقت الإنتظار/الزحام)
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      step="0.05"
                      value={selected.per_min}
                      onChange={(e) =>
                        setSelected({ ...selected, per_min: Number(e.target.value) })
                      }
                      className="input pl-14 font-mono font-bold"
                    />
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-text-tertiary">
                      ج.م/دقيقة
                    </span>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1.5">
                    رسوم حجز الخدمة
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      step="0.5"
                      value={selected.booking_fee}
                      onChange={(e) =>
                        setSelected({ ...selected, booking_fee: Number(e.target.value) })
                      }
                      className="input pl-12 font-mono font-bold"
                    />
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-text-tertiary">
                      ج.م
                    </span>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1.5">
                    الحد الأدنى لقيمة الرحلة
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      step="1"
                      value={selected.min_fare}
                      onChange={(e) =>
                        setSelected({ ...selected, min_fare: Number(e.target.value) })
                      }
                      className="input pl-12 font-mono font-bold"
                    />
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-text-tertiary">
                      ج.م
                    </span>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1.5">
                    نسبة اقتطاع المنصة (العمولة)
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      step="1"
                      min="0"
                      max="100"
                      value={Math.round((selected.commission_rate || 0) * 100)}
                      onChange={(e) =>
                        setSelected({
                          ...selected,
                          commission_rate: Math.min(100, Math.max(0, Number(e.target.value))) / 100,
                        })
                      }
                      className="input pl-10 font-mono font-bold"
                    />
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm font-extrabold text-primary-500">
                      %
                    </span>
                  </div>
                </div>
              </div>

              {/* Submit Button */}
              <button
                type="submit"
                disabled={saving}
                className="btn-primary w-full py-3 text-base font-bold shadow-md gap-2"
              >
                {saving ? (
                  <Loader2 className="w-5 h-5 animate-spin" />
                ) : (
                  <Save className="w-5 h-5" />
                )}
                حفظ تعديلات التسعير
              </button>
            </form>

            {/* Fare Estimator Live Widget */}
            <div className="bg-surface-primary border border-border-primary rounded-xl p-5 shadow-xs space-y-3 bg-gradient-to-br from-surface-primary to-primary-500/5">
              <div className="flex items-center justify-between border-b border-border-primary pb-3">
                <h4 className="font-bold text-text-primary text-sm flex items-center gap-2">
                  <Calculator className="w-4 h-4 text-primary-500" />
                  حاسبة تسعير الرحلة
                </h4>
                {activeMultiplier !== 1 && (
                  <span className="text-xs text-text-tertiary font-mono">
                    مضاعف الفئة ×{activeMultiplier}
                  </span>
                )}
              </div>

              {/* Real inputs. The distance and duration used to be constants
                  (8 km / 12 min) with the values printed as static label text,
                  so the widget could only describe one hypothetical trip. */}
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label
                    htmlFor="estimate-distance"
                    className="block text-[11px] font-bold text-text-secondary mb-1.5"
                  >
                    المسافة (كم)
                  </label>
                  <input
                    id="estimate-distance"
                    type="number"
                    min="0"
                    max="500"
                    step="0.5"
                    value={estimateDistanceKm}
                    onChange={(e) => setEstimateDistanceKm(Number(e.target.value))}
                    className="input font-mono font-bold"
                  />
                </div>
                <div>
                  <label
                    htmlFor="estimate-duration"
                    className="block text-[11px] font-bold text-text-secondary mb-1.5"
                  >
                    المدة (دقيقة)
                  </label>
                  <input
                    id="estimate-duration"
                    type="number"
                    min="0"
                    max="600"
                    step="1"
                    value={estimateTimeMin}
                    onChange={(e) => setEstimateTimeMin(Number(e.target.value))}
                    className="input font-mono font-bold"
                  />
                </div>
              </div>

              {minFareApplied && (
                <p className="text-[11px] text-warning-dark bg-warning-light border border-warning-main/30 rounded-lg px-3 py-2 leading-relaxed">
                  الأجرة المحسوبة أقل من الحد الأدنى للمدينة ({selected.min_fare} ج.م)، فتم تطبيق
                  الحد الأدنى. أسعار الكيلومتر والدقيقة لا تؤثر على هذه الرحلة.
                </p>
              )}

              <div className="grid grid-cols-3 gap-3 text-center">
                <div className="p-3 bg-surface-secondary rounded-lg border border-border-primary">
                  <p className="text-[11px] text-text-tertiary mb-1">إجمالي ما يدفعه الراكب</p>
                  <p className="text-lg font-black text-text-primary font-mono">
                    {estimatedTotal.toFixed(1)} <span className="text-xs font-normal">ج.م</span>
                  </p>
                </div>

                <div className="p-3 bg-primary-500/10 rounded-lg border border-primary-500/20">
                  <p className="text-[11px] text-primary-600 dark:text-primary-400 font-bold mb-1">
                    ربح المنصة ({Math.round(selected.commission_rate * 100)}%)
                  </p>
                  <p className="text-lg font-black text-primary-600 dark:text-primary-400 font-mono">
                    {estimatedCommission.toFixed(1)} <span className="text-xs font-normal">ج.م</span>
                  </p>
                </div>

                <div className="p-3 bg-surface-secondary rounded-lg border border-border-primary">
                  <p className="text-[11px] text-text-tertiary mb-1">صافي الكابتن</p>
                  <p className="text-lg font-black text-text-primary font-mono">
                    {estimatedDriverEarnings.toFixed(1)} <span className="text-xs font-normal">ج.م</span>
                  </p>
                </div>
              </div>
            </div>
          </div>
        ) : (
          <div className="lg:col-span-7 bg-surface-primary border border-border-primary rounded-xl p-12 text-center text-text-tertiary">
            اختر مدينة من القائمة لعرض وتعديل قواعد التسعير
          </div>
        )}
      </div>

      {/* Add New City Modal */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-surface-primary border border-border-primary rounded-2xl p-6 w-full max-w-lg shadow-2xl space-y-4 animate-scale-up" dir="rtl">
            <div className="flex items-center justify-between border-b border-border-primary pb-3">
              <h3 className="font-extrabold text-lg text-text-primary flex items-center gap-2">
                <Plus className="w-5 h-5 text-primary-500" />
                إضافة شريحة تسعير لمدينة جديدة
              </h3>
              <button
                onClick={() => setShowAddModal(false)}
                className="text-text-tertiary hover:text-text-primary text-xl font-bold"
              >
                ×
              </button>
            </div>

            <form onSubmit={handleAddCity} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-text-secondary mb-1">
                  اسم المدينة (الرمز بالإنجليزية - e.g. mansoura, tanta)
                </label>
                <input
                  type="text"
                  required
                  placeholder="mansoura"
                  value={newCity.city}
                  onChange={(e) => setNewCity({ ...newCity, city: e.target.value })}
                  className="input font-mono"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1">فتح العداد (ج.م)</label>
                  <input
                    type="number"
                    step="0.5"
                    value={newCity.base_fare}
                    onChange={(e) => setNewCity({ ...newCity, base_fare: Number(e.target.value) })}
                    className="input font-mono"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1">لكل كم (ج.م)</label>
                  <input
                    type="number"
                    step="0.1"
                    value={newCity.per_km}
                    onChange={(e) => setNewCity({ ...newCity, per_km: Number(e.target.value) })}
                    className="input font-mono"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1">لكل دقيقة (ج.م)</label>
                  <input
                    type="number"
                    step="0.05"
                    value={newCity.per_min}
                    onChange={(e) => setNewCity({ ...newCity, per_min: Number(e.target.value) })}
                    className="input font-mono"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1">رسوم الحجز (ج.م)</label>
                  <input
                    type="number"
                    step="0.5"
                    value={newCity.booking_fee}
                    onChange={(e) => setNewCity({ ...newCity, booking_fee: Number(e.target.value) })}
                    className="input font-mono"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-text-secondary mb-1">العمولة (%)</label>
                <input
                  type="number"
                  step="1"
                  min="0"
                  max="100"
                  value={Math.round(newCity.commission_rate * 100)}
                  onChange={(e) => setNewCity({ ...newCity, commission_rate: Number(e.target.value) / 100 })}
                  className="input font-mono"
                />
              </div>

              <div className="flex items-center justify-end gap-3 pt-3 border-t border-border-primary">
                <button
                  type="button"
                  onClick={() => setShowAddModal(false)}
                  className="btn-secondary text-xs px-4"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={saving}
                  className="btn-primary text-xs px-5"
                >
                  {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : 'حفظ وإضافة'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}