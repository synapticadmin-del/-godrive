import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { useAuth } from "../lib/auth";
import { formatDate } from "../lib/utils";
import { ShieldAlert, Loader2 } from "lucide-react";
import { PageHeader } from "../components/layout/PageHeader";

interface AuditRow {
  id: string; actor_id: string | null; action: string; entity_type: string | null;
  entity_id: string | null; payload: string | null; ip: string | null; created_at: string;
}

export default function AuditLogPage() {
  const { token } = useAuth();
  const [logs, setLogs] = useState<AuditRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<{ logs: AuditRow[] }>("/admin/audit-log?limit=200", { token }).then((r) => setLogs(r.logs)).catch((e) => setError(e.message)).finally(() => setLoading(false));
  }, [token]);

  return (
    <div className="space-y-6">
      <PageHeader title="سجل التدقيق" subtitle="سجل كل الإجراءات الإدارية" />
      {error && <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main">{error}</div>}
      <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden">
        {loading ? (
          <div className="p-12 text-center"><Loader2 className="w-8 h-8 mx-auto text-text-tertiary animate-spin" /></div>
        ) : logs.length === 0 ? (
          <div className="p-12 text-center"><ShieldAlert className="w-12 h-12 mx-auto text-text-tertiary mb-4" /><p className="text-text-secondary">لا سجلات بعد</p></div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead><tr className="border-b border-border-primary bg-surface-secondary/50">
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الوقت</th>
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الإجراء</th>
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الكيان</th>
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الفاعل</th>
                <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">IP</th>
              </tr></thead>
              <tbody className="divide-y divide-border-primary/50">
                {logs.map((l) => (
                  <tr key={l.id} className="hover:bg-surface-hover transition-colors">
                    <td className="px-4 py-3 text-sm text-text-tertiary">{formatDate(l.created_at)}</td>
                    <td className="px-4 py-3"><span className="px-2 py-0.5 text-xs font-medium rounded-full bg-primary-500/10 text-primary-500">{l.action}</span></td>
                    <td className="px-4 py-3 text-sm text-text-secondary">{l.entity_type || '—'}</td>
                    <td className="px-4 py-3 text-sm text-text-tertiary font-mono">{l.actor_id ? l.actor_id.slice(0, 10) + '…' : '—'}</td>
                    <td className="px-4 py-3 text-sm text-text-tertiary">{l.ip || '—'}</td>
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