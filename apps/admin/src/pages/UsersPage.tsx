import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { formatDate } from '../lib/utils';
import { StatusBadge } from '../components/ui/Badge';
import { User as UserIcon, Loader2 } from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';

interface User {
  id: string; email: string; name: string | null; phone: string | null; role: string; status: string; created_at: string;
}

export default function UsersPage() {
  const { token } = useAuth();
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<{ users: User[] }>('/admin/users', { token }).then((r) => setUsers(r.users)).catch((e) => setError(e.message)).finally(() => setLoading(false));
  }, [token]);

  return (
    <div className="space-y-6">
      <PageHeader title="المستخدمون" subtitle="إدارة حسابات المستخدمين" />
      {error && <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main">{error}</div>}
      <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden">
        {loading ? (
          <div className="p-12 text-center"><Loader2 className="w-8 h-8 mx-auto text-text-tertiary animate-spin" /></div>
        ) : users.length === 0 ? (
          <div className="p-12 text-center"><UserIcon className="w-12 h-12 mx-auto text-text-tertiary mb-4" /><p className="text-text-secondary">لا يوجد مستخدمون</p></div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead><tr className="border-b border-border-primary bg-surface-secondary/50">
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الاسم</th>
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">البريد</th>
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الهاتف</th>
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الدور</th>
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الحالة</th>
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الانضمام</th>
              </tr></thead>
              <tbody className="divide-y divide-border-primary/50">
                {users.map((u) => (
                  <tr key={u.id} className="hover:bg-surface-hover transition-colors">
                    <td className="px-4 py-3 text-sm text-text-primary">{u.name || '—'}</td>
                    <td className="px-4 py-3 text-sm text-text-secondary">{u.email}</td>
                    <td className="px-4 py-3 text-sm text-text-secondary">{u.phone || '—'}</td>
                    <td className="px-4 py-3"><span className="px-2 py-0.5 text-xs font-medium rounded-full bg-primary-500/10 text-primary-500 capitalize">{u.role}</span></td>
                    <td className="px-4 py-3"><StatusBadge status={u.status} /></td>
                    <td className="px-4 py-3 text-sm text-text-tertiary">{formatDate(u.created_at)}</td>
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