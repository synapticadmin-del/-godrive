import { useEffect, useMemo, useState } from "react";
import { api } from "../lib/api";
import { useAuth } from "../lib/auth";
import { formatDate } from "../lib/utils";
import { DataTable, type Column } from "../components/ui/DataTable";
import { Badge } from "../components/ui/Badge";
import { Search, Download, RefreshCw } from "lucide-react";
import { PageHeader } from "../components/layout/PageHeader";
import { downloadCsv, formatCsvDate, type CsvColumn } from "../lib/csv";

interface AuditRow {
  id: string; actor_id: string | null; action: string; entity_type: string | null;
  entity_id: string | null; payload: string | null; ip: string | null; created_at: string;
}

/**
 * Colour an audit action by what it DOES, not by its exact name.
 *
 * Actions are namespaced strings ("captain.approve", "promo.deactivate"), and
 * new ones get added over time, so matching on the verb suffix keeps this
 * working for actions that do not exist yet. Every action previously rendered
 * in the same neutral blue, which made a suspension visually identical to a
 * routine settings read.
 */
function actionVariant(action: string): 'success' | 'danger' | 'warning' | 'info' {
  const verb = action.split('.').pop() ?? '';
  if (/approve|create|activate/.test(verb)) return 'success';
  if (/suspend|reject|delete|deactivate/.test(verb)) return 'danger';
  if (/update|review/.test(verb)) return 'warning';
  return 'info';
}

const PAGE_LIMIT = 500;

export default function AuditLogPage() {
  const { token } = useAuth();
  const [logs, setLogs] = useState<AuditRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [actionFilter, setActionFilter] = useState('');
  const [exportNotice, setExportNotice] = useState<string | null>(null);

  const load = () => {
    setLoading(true);
    setError(null);
    api<{ logs: AuditRow[] }>(`/admin/audit-log?limit=${PAGE_LIMIT}`, { token })
      .then((r) => setLogs(r.logs ?? []))
      .catch((e) => setError(e instanceof Error ? e.message : 'فشل تحميل سجل التدقيق'))
      .finally(() => setLoading(false));
  };

  useEffect(load, [token]);

  // The distinct actions actually present, so the filter only ever offers
  // values that will match something.
  const actionOptions = useMemo(
    () => Array.from(new Set(logs.map((l) => l.action))).sort(),
    [logs],
  );

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return logs.filter((l) => {
      if (actionFilter && l.action !== actionFilter) return false;
      if (!term) return true;
      return (
        l.action.toLowerCase().includes(term) ||
        (l.entity_type ?? '').toLowerCase().includes(term) ||
        (l.entity_id ?? '').toLowerCase().includes(term) ||
        (l.actor_id ?? '').toLowerCase().includes(term) ||
        (l.ip ?? '').toLowerCase().includes(term)
      );
    });
  }, [logs, search, actionFilter]);

  const columns: Column<AuditRow>[] = [
    {
      key: 'created_at',
      header: 'الوقت',
      sortable: true,
      accessor: (l) => <span className="text-sm text-text-tertiary">{formatDate(l.created_at)}</span>,
    },
    {
      key: 'action',
      header: 'الإجراء',
      sortable: true,
      accessor: (l) => (
        <Badge variant={actionVariant(l.action)} size="sm">
          <span className="font-mono" dir="ltr">{l.action}</span>
        </Badge>
      ),
    },
    {
      key: 'entity_type',
      header: 'الكيان',
      sortable: true,
      accessor: (l) => (
        <div className="min-w-0">
          <p className="text-sm text-text-secondary">{l.entity_type || '—'}</p>
          {/* entity_id was fetched but never displayed, so an entry told you a
              captain was suspended without saying WHICH captain. */}
          {l.entity_id && (
            <p className="text-xs text-text-tertiary font-mono truncate" dir="ltr" title={l.entity_id}>
              {l.entity_id}
            </p>
          )}
        </div>
      ),
    },
    {
      key: 'actor_id',
      header: 'الفاعل',
      sortable: true,
      accessor: (l) => (
        <span className="text-sm text-text-tertiary font-mono" dir="ltr" title={l.actor_id ?? undefined}>
          {l.actor_id ? `${l.actor_id.slice(0, 10)}…` : '—'}
        </span>
      ),
    },
    {
      key: 'ip',
      header: 'IP',
      sortable: true,
      accessor: (l) => (
        <span className="text-sm text-text-tertiary font-mono" dir="ltr">{l.ip || '—'}</span>
      ),
    },
  ];

  const csvColumns: CsvColumn<AuditRow>[] = [
    { header: 'الوقت', value: (l) => formatCsvDate(l.created_at) },
    { header: 'الإجراء', value: (l) => l.action },
    { header: 'نوع الكيان', value: (l) => l.entity_type ?? '' },
    { header: 'معرف الكيان', value: (l) => l.entity_id ?? '' },
    { header: 'معرف الفاعل', value: (l) => l.actor_id ?? '' },
    { header: 'IP', value: (l) => l.ip ?? '' },
    // payload is stored as a JSON string. Exported verbatim — escapeCsvField
    // quotes it and doubles its embedded quotes, so it survives intact.
    { header: 'التفاصيل', value: (l) => l.payload ?? '' },
  ];

  const handleExport = () => {
    const n = downloadCsv('audit-log', filtered, csvColumns);
    setExportNotice(`تم تصدير ${n.toLocaleString('ar-EG')} سجل`);
    window.setTimeout(() => setExportNotice(null), 4000);
  };

  return (
    <div className="space-y-6" dir="rtl">
      <PageHeader
        title="سجل التدقيق"
        subtitle="سجل كل الإجراءات الإدارية"
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative">
              <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-tertiary pointer-events-none" />
              <input
                type="search"
                placeholder="بحث في السجل..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full sm:w-56 pl-3 pr-9 py-2 bg-surface-secondary border border-border-primary rounded-lg text-sm text-text-primary placeholder:text-text-tertiary focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 transition-all"
              />
            </div>

            <select
              value={actionFilter}
              onChange={(e) => setActionFilter(e.target.value)}
              className="px-3 py-2 bg-surface-secondary border border-border-primary rounded-lg text-sm text-text-primary focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 transition-all"
            >
              <option value="">كل الإجراءات</option>
              {actionOptions.map((a) => (
                <option key={a} value={a}>{a}</option>
              ))}
            </select>

            <button
              onClick={load}
              disabled={loading}
              title="تحديث"
              className="p-2 rounded-lg bg-surface-secondary border border-border-primary text-text-secondary hover:text-text-primary hover:border-primary-500/40 transition-all disabled:opacity-40"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>

            <button
              onClick={handleExport}
              disabled={filtered.length === 0}
              title={filtered.length === 0 ? 'لا توجد بيانات للتصدير' : `تصدير ${filtered.length} سجل إلى CSV`}
              className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium rounded-lg bg-surface-secondary border border-border-primary text-text-secondary hover:text-text-primary hover:border-primary-500/40 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <Download className="w-4 h-4" />
              تصدير CSV
            </button>
          </div>
        }
      />

      {error && (
        <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main">
          {error}
        </div>
      )}

      {exportNotice && (
        <div className="p-3 bg-success-main/10 border border-success-main/30 rounded-xl text-success-main text-sm flex items-center gap-2">
          <Download className="w-4 h-4 shrink-0" />
          {exportNotice}
        </div>
      )}

      {/* The API caps this response, so say so rather than letting the admin
          believe they are looking at the complete history. */}
      {!loading && logs.length >= PAGE_LIMIT && (
        <div className="p-3 bg-warning-main/10 border border-warning-main/30 rounded-xl text-warning-main text-sm">
          يعرض أحدث {PAGE_LIMIT.toLocaleString('ar-EG')} سجل فقط. السجلات الأقدم غير معروضة.
        </div>
      )}

      <DataTable<AuditRow>
        data={filtered}
        columns={columns}
        keyAccessor={(l) => l.id}
        loading={loading}
        defaultSortKey="created_at"
        defaultSortDirection="desc"
        pageSize={25}
        emptyMessage={
          search || actionFilter ? 'لا توجد سجلات مطابقة للبحث' : 'لا سجلات بعد'
        }
      />
    </div>
  );
}
