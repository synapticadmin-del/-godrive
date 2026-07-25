import { FormEvent, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import {
  Tag, Plus, Ban, Loader2, Check, Sliders, Shield, RefreshCw, Copy,
  Percent, DollarSign, Calendar, AlertCircle, Phone, Radio, Save
} from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';

interface Promo {
  code: string;
  type: 'percent' | 'fixed';
  value: number;
  max_uses: number | null;
  uses_count: number;
  expires_at: string | null;
  active: number;
  min_fare?: number;
}

export default function SettingsPage() {
  const { token } = useAuth();
  const [activeTab, setActiveTab] = useState<'promos' | 'system'>('promos');

  // Promos State
  const [promos, setPromos] = useState<Promo[]>([]);
  const [code, setCode] = useState('WELCOME10');
  const [value, setValue] = useState(10);
  const [type, setType] = useState<'percent' | 'fixed'>('percent');
  const [maxUses, setMaxUses] = useState<number | ''>(100);
  const [expiresAt, setExpiresAt] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all');

  // Global System Settings State
  const [sysConfig, setSysConfig] = useState({
    defaultCommission: 20,
    searchRadiusKm: 5,
    freeCancelMin: 3,
    cancelFeeEgp: 15,
    supportPhone: '+201000000000',
    supportWhatsapp: '+201000000000',
    autoAssign: true,
  });

  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [copiedCode, setCopiedCode] = useState<string | null>(null);

  const loadPromos = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await api<{ promos: Promo[] }>('/promos', { token });
      setPromos(res.promos || []);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'فشل تحميل أكواد الخصم');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadPromos();
  }, [token]);

  const generateRandomCode = () => {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let result = 'GO';
    for (let i = 0; i < 6; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    setCode(result);
  };

  const onCreatePromo = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setMessage(null);
    setSubmitting(true);
    try {
      await api('/promos', {
        method: 'POST',
        token,
        body: JSON.stringify({
          code: code.trim().toUpperCase(),
          type,
          value: Number(value),
          max_uses: maxUses !== '' ? Number(maxUses) : null,
          expires_at: expiresAt || null,
        }),
      });
      setMessage(`تم إنشاء كود الخصم (${code.toUpperCase()}) بنجاح`);
      setCode('');
      await loadPromos();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'فشل إنشاء كود الخصم');
    } finally {
      setSubmitting(false);
    }
  };

  const deactivatePromo = async (c: string) => {
    setError(null);
    setMessage(null);
    try {
      await api(`/promos/${c}/deactivate`, { method: 'POST', token });
      setMessage(`تم تعطيل الكود (${c})`);
      await loadPromos();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'فشل تعطيل الكود');
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopiedCode(text);
    setTimeout(() => setCopiedCode(null), 2000);
  };

  const handleSaveSystemConfig = (e: FormEvent) => {
    e.preventDefault();
    setMessage('تم حفظ الإعدادات العامة للنظام بنجاح');
  };

  // Stats calculation
  const totalPromos = promos.length;
  const activePromosCount = promos.filter((p) => p.active === 1).length;
  const totalUsesCount = promos.reduce((sum, p) => sum + (p.uses_count || 0), 0);

  const filteredPromos = promos.filter((p) => {
    const matchesQuery = p.code.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesStatus =
      statusFilter === 'all'
        ? true
        : statusFilter === 'active'
        ? p.active === 1
        : p.active === 0;
    return matchesQuery && matchesStatus;
  });

  return (
    <div className="space-y-6 animate-fade-in" dir="rtl">
      <PageHeader
        title="الإعدادات والحوكمة"
        subtitle="إدارة أكواد الخصم والترويج، الضوابط المالية، وإعدادات التشغيل العامة"
      />

      {/* Alert Notices */}
      {error && (
        <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main flex items-center justify-between animate-slide-down">
          <div className="flex items-center gap-3">
            <AlertCircle className="w-5 h-5 flex-shrink-0" />
            <span className="text-sm font-medium">{error}</span>
          </div>
          <button onClick={() => setError(null)} className="text-xs hover:underline">إغلاق</button>
        </div>
      )}

      {message && (
        <div className="p-4 bg-primary-500/10 border border-primary-500/30 rounded-xl text-primary-600 dark:text-primary-400 flex items-center justify-between animate-slide-down">
          <div className="flex items-center gap-2">
            <Check className="w-5 h-5 text-primary-500 flex-shrink-0" />
            <span className="text-sm font-bold">{message}</span>
          </div>
          <button onClick={() => setMessage(null)} className="text-xs hover:underline">إغلاق</button>
        </div>
      )}

      {/* Main Tab Navigation Bar */}
      <div className="flex items-center gap-2 border-b border-border-primary pb-1">
        <button
          onClick={() => setActiveTab('promos')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-bold transition-all ${
            activeTab === 'promos'
              ? 'bg-primary-500 text-white shadow-sm'
              : 'text-text-secondary hover:bg-surface-hover hover:text-text-primary'
          }`}
        >
          <Tag className="w-4 h-4" />
          أكواد الخصم والترويج ({activePromosCount})
        </button>

        <button
          onClick={() => setActiveTab('system')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-bold transition-all ${
            activeTab === 'system'
              ? 'bg-primary-500 text-white shadow-sm'
              : 'text-text-secondary hover:bg-surface-hover hover:text-text-primary'
          }`}
        >
          <Sliders className="w-4 h-4" />
          الإعدادات التشغيلية العامة
        </button>
      </div>

      {/* TAB 1: PROMO CODES */}
      {activeTab === 'promos' && (
        <div className="space-y-6">
          {/* Stats Bar */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="bg-surface-primary border border-border-primary rounded-xl p-4 flex items-center justify-between shadow-xs">
              <div>
                <p className="text-xs text-text-tertiary">إجمالي أكواد الخصم</p>
                <p className="text-2xl font-black text-text-primary font-mono mt-1">{totalPromos}</p>
              </div>
              <div className="w-10 h-10 rounded-xl bg-primary-500/10 flex items-center justify-center text-primary-500 font-bold">
                <Tag className="w-5 h-5" />
              </div>
            </div>

            <div className="bg-surface-primary border border-border-primary rounded-xl p-4 flex items-center justify-between shadow-xs">
              <div>
                <p className="text-xs text-text-tertiary">الأكواد النشطة حالياً</p>
                <p className="text-2xl font-black text-primary-600 dark:text-primary-400 font-mono mt-1">
                  {activePromosCount}
                </p>
              </div>
              <div className="w-10 h-10 rounded-xl bg-primary-500/10 flex items-center justify-center text-primary-500 font-bold">
                <Check className="w-5 h-5" />
              </div>
            </div>

            <div className="bg-surface-primary border border-border-primary rounded-xl p-4 flex items-center justify-between shadow-xs">
              <div>
                <p className="text-xs text-text-tertiary">مرات الاستخدام الإجمالية</p>
                <p className="text-2xl font-black text-text-primary font-mono mt-1">{totalUsesCount}</p>
              </div>
              <div className="w-10 h-10 rounded-xl bg-surface-secondary flex items-center justify-center text-text-secondary font-bold">
                <Shield className="w-5 h-5" />
              </div>
            </div>
          </div>

          {/* Grid Layout: Creation Form & Table */}
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
            {/* Left Side: Create Form (5 Cols) */}
            <form
              onSubmit={onCreatePromo}
              className="lg:col-span-5 bg-surface-primary border border-border-primary rounded-xl p-5 shadow-xs space-y-4"
            >
              <div className="flex items-center justify-between border-b border-border-primary pb-3">
                <h3 className="text-base font-extrabold text-text-primary flex items-center gap-2">
                  <Tag className="w-5 h-5 text-primary-500" />
                  إنشاء كود خصم جديد
                </h3>
                <button
                  type="button"
                  onClick={generateRandomCode}
                  className="text-xs text-primary-600 dark:text-primary-400 font-bold hover:underline flex items-center gap-1"
                >
                  <RefreshCw className="w-3.5 h-3.5" />
                  توليد كود
                </button>
              </div>

              <div>
                <label className="block text-xs font-bold text-text-secondary mb-1">
                  رمز كود الخصم (Promo Code)
                </label>
                <input
                  type="text"
                  required
                  placeholder="WELCOME10"
                  value={code}
                  onChange={(e) => setCode(e.target.value.toUpperCase())}
                  className="input font-mono font-bold uppercase tracking-wider"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1">نوع الخصم</label>
                  <select
                    value={type}
                    onChange={(e) => setType(e.target.value as 'percent' | 'fixed')}
                    className="input font-bold text-xs"
                  >
                    <option value="percent">نسبة مئوية (%)</option>
                    <option value="fixed">مبلغ ثابت (ج.م)</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1">
                    قيمة الخصم {type === 'percent' ? '(%)' : '(ج.م)'}
                  </label>
                  <input
                    type="number"
                    step="1"
                    min="1"
                    required
                    value={value}
                    onChange={(e) => setValue(Number(e.target.value))}
                    className="input font-mono font-bold"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1">
                    حد الاستخدام الأقصى
                  </label>
                  <input
                    type="number"
                    placeholder="100 (فارغ = بلا حد)"
                    value={maxUses}
                    onChange={(e) =>
                      setMaxUses(e.target.value === '' ? '' : Number(e.target.value))
                    }
                    className="input font-mono text-xs"
                  />
                </div>

                <div>
                  <label className="block text-xs font-bold text-text-secondary mb-1">تاريخ الانتهاء</label>
                  <input
                    type="date"
                    value={expiresAt}
                    onChange={(e) => setExpiresAt(e.target.value)}
                    className="input text-xs font-mono"
                  />
                </div>
              </div>

              <button
                type="submit"
                disabled={submitting}
                className="btn-primary w-full py-3 font-bold text-sm shadow-md gap-2"
              >
                {submitting ? (
                  <Loader2 className="w-5 h-5 animate-spin" />
                ) : (
                  <Plus className="w-5 h-5" />
                )}
                إنشاء وتفعيل كود الخصم
              </button>
            </form>

            {/* Right Side: Promos List Table (7 Cols) */}
            <div className="lg:col-span-7 bg-surface-primary border border-border-primary rounded-xl shadow-xs overflow-hidden">
              {/* Header Filters */}
              <div className="p-4 border-b border-border-primary flex flex-wrap items-center justify-between gap-3 bg-surface-secondary/30">
                <h3 className="font-bold text-text-primary text-base">سجل الكوبونات</h3>

                <div className="flex items-center gap-2">
                  <input
                    type="search"
                    placeholder="ابحث بالكود..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="input py-1 px-3 text-xs w-36 rounded-lg"
                  />

                  <select
                    value={statusFilter}
                    onChange={(e) =>
                      setStatusFilter(e.target.value as 'all' | 'active' | 'inactive')
                    }
                    className="input py-1 px-2 text-xs rounded-lg w-24 font-bold"
                  >
                    <option value="all">الكل</option>
                    <option value="active">نشط</option>
                    <option value="inactive">متوقف</option>
                  </select>
                </div>
              </div>

              {/* Table */}
              <div className="overflow-x-auto max-h-[500px] overflow-y-auto">
                {loading ? (
                  <div className="p-12 text-center text-text-tertiary">
                    <Loader2 className="w-8 h-8 animate-spin mx-auto text-primary-500 mb-2" />
                    <p className="text-xs">جاري تحميل الأكواد...</p>
                  </div>
                ) : filteredPromos.length === 0 ? (
                  <div className="p-12 text-center text-text-tertiary text-sm">
                    لا توجد أكواد خصم مسجلة
                  </div>
                ) : (
                  <table className="w-full text-right text-sm">
                    <thead className="sticky top-0 bg-surface-secondary border-b border-border-primary text-xs font-semibold text-text-tertiary">
                      <tr>
                        <th className="px-4 py-2.5">الكود</th>
                        <th className="px-3 py-2.5">القيمة</th>
                        <th className="px-3 py-2.5">الاستخدام</th>
                        <th className="px-3 py-2.5">الحالة</th>
                        <th className="px-3 py-2.5 text-center">إجراءات</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-primary/50">
                      {filteredPromos.map((p) => (
                        <tr key={p.code} className="hover:bg-surface-hover transition-colors">
                          <td className="px-4 py-3 font-mono font-bold text-text-primary">
                            <div className="flex items-center gap-1.5">
                              <span>{p.code}</span>
                              <button
                                onClick={() => copyToClipboard(p.code)}
                                className="text-text-tertiary hover:text-primary-500 p-1"
                                title="نسخ الكود"
                              >
                                <Copy className="w-3.5 h-3.5" />
                              </button>
                              {copiedCode === p.code && (
                                <span className="text-[10px] text-primary-500 font-bold">
                                  تم النسخ!
                                </span>
                              )}
                            </div>
                          </td>
                          <td className="px-3 py-3 font-bold text-primary-600 dark:text-primary-400 font-mono">
                            {p.type === 'percent' ? `${p.value}%` : `${p.value} ج.م`}
                          </td>
                          <td className="px-3 py-3 text-xs text-text-tertiary font-mono">
                            {p.uses_count} / {p.max_uses ?? '∞'}
                          </td>
                          <td className="px-3 py-3">
                            {p.active ? (
                              <span className="px-2 py-0.5 text-xs font-bold rounded-full bg-primary-500/10 text-primary-600 dark:text-primary-400 border border-primary-500/20">
                                نشط
                              </span>
                            ) : (
                              <span className="px-2 py-0.5 text-xs font-bold rounded-full bg-error-main/10 text-error-main border border-error-main/20">
                                متوقف
                              </span>
                            )}
                          </td>
                          <td className="px-3 py-3 text-center">
                            {p.active ? (
                              <button
                                onClick={() => deactivatePromo(p.code)}
                                className="p-1.5 rounded-lg text-error-main hover:bg-error-main/10 transition-colors"
                                title="تعطيل الكود"
                              >
                                <Ban className="w-4 h-4" />
                              </button>
                            ) : (
                              <span className="text-xs text-text-disabled">—</span>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* TAB 2: GLOBAL SYSTEM CONFIGURATIONS */}
      {activeTab === 'system' && (
        <form
          onSubmit={handleSaveSystemConfig}
          className="bg-surface-primary border border-border-primary rounded-xl p-6 shadow-xs space-y-6 max-w-4xl"
        >
          <div className="border-b border-border-primary pb-4">
            <h3 className="text-lg font-extrabold text-text-primary flex items-center gap-2">
              <Sliders className="w-5 h-5 text-primary-500" />
              إعدادات وقواعد المنصة الأساسية
            </h3>
            <p className="text-xs text-text-tertiary mt-1">
              التحكم في معايير التوزيع التلقائي، حدود الإلغاء، وأرقام التواصل المباشرة
            </p>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
            <div>
              <label className="block text-xs font-bold text-text-secondary mb-1.5">
                نسبة عمولة المنصة الافتراضية (%)
              </label>
              <div className="relative">
                <input
                  type="number"
                  step="1"
                  min="0"
                  max="100"
                  value={sysConfig.defaultCommission}
                  onChange={(e) =>
                    setSysConfig({ ...sysConfig, defaultCommission: Number(e.target.value) })
                  }
                  className="input pl-10 font-mono font-bold"
                />
                <Percent className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-primary-500" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-text-secondary mb-1.5">
                قطر البحث عن الكباتن المتاحين (كم)
              </label>
              <div className="relative">
                <input
                  type="number"
                  step="1"
                  min="1"
                  max="30"
                  value={sysConfig.searchRadiusKm}
                  onChange={(e) =>
                    setSysConfig({ ...sysConfig, searchRadiusKm: Number(e.target.value) })
                  }
                  className="input pl-14 font-mono font-bold"
                />
                <Radio className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-primary-500" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-text-secondary mb-1.5">
                مهلة الإلغاء المجاني للراكب (دقائق)
              </label>
              <input
                type="number"
                step="1"
                min="0"
                value={sysConfig.freeCancelMin}
                onChange={(e) =>
                  setSysConfig({ ...sysConfig, freeCancelMin: Number(e.target.value) })
                }
                className="input font-mono font-bold"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-text-secondary mb-1.5">
                غرامة الإلغاء المتأخر (ج.م)
              </label>
              <input
                type="number"
                step="5"
                min="0"
                value={sysConfig.cancelFeeEgp}
                onChange={(e) =>
                  setSysConfig({ ...sysConfig, cancelFeeEgp: Number(e.target.value) })
                }
                className="input font-mono font-bold"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-text-secondary mb-1.5">
                هاتف مركز دعم العملاء
              </label>
              <div className="relative">
                <input
                  type="text"
                  value={sysConfig.supportPhone}
                  onChange={(e) => setSysConfig({ ...sysConfig, supportPhone: e.target.value })}
                  className="input pl-10 font-mono text-xs"
                />
                <Phone className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-tertiary" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-text-secondary mb-1.5">
                رقم واتساب المساعدة المباشرة
              </label>
              <div className="relative">
                <input
                  type="text"
                  value={sysConfig.supportWhatsapp}
                  onChange={(e) => setSysConfig({ ...sysConfig, supportWhatsapp: e.target.value })}
                  className="input pl-10 font-mono text-xs"
                />
                <Phone className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-tertiary" />
              </div>
            </div>
          </div>

          <div className="pt-4 border-t border-border-primary flex items-center justify-end gap-3">
            <button type="submit" className="btn-primary px-6 py-2.5 font-bold text-sm gap-2">
              <Save className="w-4 h-4" />
              حفظ وتطبيق إعدادات المنصة
            </button>
          </div>
        </form>
      )}
    </div>
  );
}