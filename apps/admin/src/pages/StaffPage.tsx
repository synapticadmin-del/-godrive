import { useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { ROLE_DESCRIPTIONS_AR, ROLE_LABELS_AR, STAFF_ROLES, type StaffRole } from '../lib/staff';
import { Badge } from '../components/ui/Badge';
import { PageHeader } from '../components/layout/PageHeader';
import { Loader2, Plus, RefreshCw, ShieldCheck, Trash2, UserX, UserCheck } from 'lucide-react';

interface StaffRow {
  id: string;
  email: string;
  name: string | null;
  dashboard_role: string;
  status: string;
  created_at: string;
}

/**
 * Owner-only staff console (migration 0024 RBAC).
 *
 * Everything on this page calls the /admin/staff endpoints, which sit behind
 * staff:manage — the UI is gated in App.tsx and the Sidebar, and the server
 * re-checks the role on every request, so this page is safe even if somebody
 * hand-navigates to /staff on a limited account.
 */
export default function StaffPage() {
  const { token, user } = useAuth();
  const [staff, setStaff] = useState<StaffRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // Add-staff form state.
  const [showAdd, setShowAdd] = useState(false);
  const [form, setForm] = useState({ name: '', email: '', password: '', dashboardRole: 'assistant' as StaffRole });
  const [saving, setSaving] = useState(false);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    api<{ staff: StaffRow[] }>('/admin/staff', { token })
      .then((r) => setStaff(r.staff ?? []))
      .catch((e) => setError(e instanceof Error ? e.message : 'فشل تحميل قائمة الموظفين'))
      .finally(() => setLoading(false));
  }, [token]);

  useEffect(load, [load]);

  const flash = (message: string) => {
    setNotice(message);
    window.setTimeout(() => setNotice(null), 4000);
  };

  const fail = (e: unknown) => setError(e instanceof Error ? e.message : 'فشلت العملية');

  async function addStaff() {
    setSaving(true);
    setError(null);
    try {
      await api('/admin/staff', {
        method: 'POST',
        token,
        body: JSON.stringify(form),
      });
      setForm({ name: '', email: '', password: '', dashboardRole: 'assistant' });
      setShowAdd(false);
      flash('تمت إضافة الموظف بنجاح');
      load();
    } catch (e) {
      fail(e);
    } finally {
      setSaving(false);
    }
  }

  async function changeRole(target: StaffRow, dashboardRole: StaffRole) {
    if (dashboardRole === target.dashboard_role) return;
    setError(null);
    try {
      await api(`/admin/staff/${target.id}`, {
        method: 'PATCH',
        token,
        body: JSON.stringify({ dashboardRole }),
      });
      flash(`تم تغيير دور ${target.name || target.email} إلى ${ROLE_LABELS_AR[dashboardRole]}`);
      load();
    } catch (e) {
      fail(e);
    }
  }

  async function toggleStatus(target: StaffRow) {
    setError(null);
    const status = target.status === 'active' ? 'suspended' : 'active';
    try {
      await api(`/admin/staff/${target.id}`, {
        method: 'PATCH',
        token,
        body: JSON.stringify({ status }),
      });
      flash(status === 'active' ? 'تم تفعيل الحساب' : 'تم تعطيل الحساب');
      load();
    } catch (e) {
      fail(e);
    }
  }

  async function removeStaff(target: StaffRow) {
    if (!window.confirm(`تأكيد إزالة ${target.name || target.email}؟ سيتم تعطيل حسابه نهائيًا.`)) return;
    setError(null);
    try {
      await api(`/admin/staff/${target.id}`, { method: 'DELETE', token });
      flash('تمت إزالة الموظف');
      load();
    } catch (e) {
      fail(e);
    }
  }

  return (
    <div className="p-6 space-y-6 max-w-6xl mx-auto">
      <PageHeader
        title="الموظفون والأدوار"
        subtitle="إدارة حسابات لوحة التحكم وصلاحياتها — متاح للمالك فقط"
        actions={
          <div className="flex items-center gap-2">
            <button
              onClick={load}
              className="flex items-center gap-2 px-3 py-2 rounded-lg border border-border-primary text-text-secondary hover:bg-surface-hover text-sm"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
              تحديث
            </button>
            <button
              onClick={() => setShowAdd((v) => !v)}
              className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-500 text-white hover:bg-primary-600 text-sm font-semibold"
            >
              <Plus className="w-4 h-4" />
              إضافة موظف
            </button>
          </div>
        }
      />

      {notice && (
        <div className="px-4 py-3 rounded-lg bg-success-main/10 text-success-main border border-success-main/30 text-sm" role="status">
          {notice}
        </div>
      )}
      {error && (
        <div className="px-4 py-3 rounded-lg bg-error-main/10 text-error-main border border-error-main/30 text-sm" role="alert">
          {error}
        </div>
      )}

      {/* Add-staff form */}
      {showAdd && (
        <div className="bg-surface-primary border border-border-primary rounded-xl p-5 space-y-4">
          <h3 className="text-base font-bold text-text-primary flex items-center gap-2">
            <ShieldCheck className="w-5 h-5 text-primary-500" />
            حساب جديد على لوحة التحكم
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <label className="space-y-1">
              <span className="text-sm text-text-secondary">الاسم</span>
              <input
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                className="w-full px-3 py-2 rounded-lg border border-border-primary bg-surface-secondary text-text-primary text-sm"
                placeholder="اسم الموظف"
              />
            </label>
            <label className="space-y-1">
              <span className="text-sm text-text-secondary">البريد الإلكتروني</span>
              <input
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                type="email"
                dir="ltr"
                className="w-full px-3 py-2 rounded-lg border border-border-primary bg-surface-secondary text-text-primary text-sm"
                placeholder="staff@example.com"
              />
            </label>
            <label className="space-y-1">
              <span className="text-sm text-text-secondary">كلمة المرور (8 أحرف على الأقل)</span>
              <input
                value={form.password}
                onChange={(e) => setForm({ ...form, password: e.target.value })}
                type="password"
                dir="ltr"
                className="w-full px-3 py-2 rounded-lg border border-border-primary bg-surface-secondary text-text-primary text-sm"
              />
            </label>
            <label className="space-y-1">
              <span className="text-sm text-text-secondary">الدور</span>
              <select
                value={form.dashboardRole}
                onChange={(e) => setForm({ ...form, dashboardRole: e.target.value as StaffRole })}
                className="w-full px-3 py-2 rounded-lg border border-border-primary bg-surface-secondary text-text-primary text-sm"
              >
                {STAFF_ROLES.map((role) => (
                  <option key={role} value={role}>
                    {ROLE_LABELS_AR[role]}
                  </option>
                ))}
              </select>
              <span className="block text-xs text-text-tertiary mt-1">{ROLE_DESCRIPTIONS_AR[form.dashboardRole]}</span>
            </label>
          </div>
          <div className="flex justify-end">
            <button
              onClick={addStaff}
              disabled={saving || !form.email || !form.password}
              className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-500 text-white hover:bg-primary-600 disabled:opacity-50 text-sm font-semibold"
            >
              {saving && <Loader2 className="w-4 h-4 animate-spin" />}
              إنشاء الحساب
            </button>
          </div>
        </div>
      )}

      {/* Staff table */}
      <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden">
        {loading ? (
          <div className="p-10 flex justify-center">
            <Loader2 className="w-7 h-7 text-primary-500 animate-spin" />
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border-primary text-text-tertiary text-xs">
                <th className="text-right px-4 py-3 font-semibold">الموظف</th>
                <th className="text-right px-4 py-3 font-semibold">الدور</th>
                <th className="text-right px-4 py-3 font-semibold">الحالة</th>
                <th className="text-right px-4 py-3 font-semibold">إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {staff.map((member) => {
                const isSelf = member.id === user?.id;
                const role = (member.dashboard_role in ROLE_LABELS_AR
                  ? member.dashboard_role
                  : 'owner') as StaffRole;
                return (
                  <tr key={member.id} className="border-b border-border-primary last:border-0 hover:bg-surface-hover/50">
                    <td className="px-4 py-3">
                      <p className="font-medium text-text-primary">
                        {member.name || '—'}
                        {isSelf && <span className="mr-2 text-xs text-primary-500">(أنت)</span>}
                      </p>
                      <p className="text-xs text-text-tertiary" dir="ltr">{member.email}</p>
                    </td>
                    <td className="px-4 py-3">
                      {isSelf ? (
                        // An actor can never edit their own account — the API
                        // refuses it too; rendering a live select would invite
                        // a click that can only ever fail.
                        <Badge variant="info">{ROLE_LABELS_AR[role]}</Badge>
                      ) : (
                        <select
                          value={role}
                          onChange={(e) => changeRole(member, e.target.value as StaffRole)}
                          className="px-2 py-1.5 rounded-lg border border-border-primary bg-surface-secondary text-text-primary text-xs"
                        >
                          {STAFF_ROLES.map((r) => (
                            <option key={r} value={r}>
                              {ROLE_LABELS_AR[r]}
                            </option>
                          ))}
                        </select>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <Badge variant={member.status === 'active' ? 'success' : 'danger'}>
                        {member.status === 'active' ? 'نشط' : 'موقوف'}
                      </Badge>
                    </td>
                    <td className="px-4 py-3">
                      {!isSelf && (
                        <div className="flex items-center gap-1.5">
                          <button
                            onClick={() => toggleStatus(member)}
                            title={member.status === 'active' ? 'تعطيل الحساب' : 'تفعيل الحساب'}
                            className="p-2 rounded-lg text-text-secondary hover:bg-surface-hover"
                          >
                            {member.status === 'active' ? <UserX className="w-4 h-4" /> : <UserCheck className="w-4 h-4" />}
                          </button>
                          <button
                            onClick={() => removeStaff(member)}
                            title="إزالة الموظف"
                            className="p-2 rounded-lg text-error-main hover:bg-error-main/10"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* Role reference */}
      <div className="bg-surface-primary border border-border-primary rounded-xl p-5">
        <h3 className="text-base font-bold text-text-primary mb-3">مستويات الأدوار</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {STAFF_ROLES.map((role) => (
            <div key={role} className="flex items-start gap-3 p-3 rounded-lg bg-surface-secondary border border-border-primary">
              <Badge variant={role === 'owner' ? 'info' : role === 'admin' ? 'success' : 'warning'}>
                {ROLE_LABELS_AR[role]}
              </Badge>
              <p className="text-xs text-text-secondary leading-relaxed">{ROLE_DESCRIPTIONS_AR[role]}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
