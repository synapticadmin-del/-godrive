import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { ShieldCheck, Loader2, FileText, Check, X, Eye } from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';

interface Doc {
  id: string; captain_id: string; type: string; r2_key: string; status: string;
  reviewed_by: string | null; reviewed_at: string | null; created_at: string;
  captain_name?: string; captain_email?: string; captain_phone?: string;
}

const API_BASE = import.meta.env.VITE_API_URL || 'https://api.synapticstudio.tech';
const docTypeLabels: Record<string, string> = {
  license: 'رخصة القيادة',
  national_id: 'بطاقة رقم قومي',
  criminal_record: 'فيش جنائي',
  vehicle_reg: 'رخصة السيارة',
};

export default function CaptainVerificationPage() {
  const { token } = useAuth();
  const [docs, setDocs] = useState<Doc[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('pending');
  const [previewDoc, setPreviewDoc] = useState<Doc | null>(null);

  const load = async () => {
    try {
      setLoading(true);
      const params = statusFilter ? `?status=${statusFilter}` : '';
      const res = await api<{ documents: Doc[] }>(`/admin/documents${params}`, { token });
      setDocs(res.documents || []);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'فشل التحميل');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, [token, statusFilter]);

  const review = async (id: string, status: 'approved' | 'rejected') => {
    try {
      await api(`/admin/documents/${id}/review`, { method: 'POST', token, body: JSON.stringify({ status }) });
      load();
    } catch {
      alert('فشل المراجعة');
    }
  };

  const fileUrl = (doc: Doc) => `${API_BASE}/admin/documents/${doc.id}/file`;

  return (
    <div className="space-y-6">
      <PageHeader
        title="توثيق المستندات"
        subtitle="مراجعة مستندات الكباتن قبل الموافقة"
        actions={
          <div className="flex bg-surface-secondary rounded-lg p-1 border border-border-primary">
            {([['pending', 'بانتظار'], ['approved', 'مقبولة'], ['rejected', 'مرفوضة'], ['', 'الكل']] as const).map(([st, label]) => (
              <button key={st} onClick={() => setStatusFilter(st)}
                className={`px-3 py-1.5 text-xs font-medium rounded-md transition-all ${statusFilter === st ? 'bg-primary-500 text-white' : 'text-text-secondary hover:text-text-primary'}`}>
                {label}
              </button>
            ))}
          </div>
        }
      />

      {error && <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main">{error}</div>}

      {loading ? (
        <div className="bg-surface-primary border border-border-primary rounded-xl p-12 text-center">
          <Loader2 className="w-8 h-8 mx-auto text-text-tertiary animate-spin" />
        </div>
      ) : docs.length === 0 ? (
        <div className="bg-surface-primary border border-border-primary rounded-xl p-12 text-center">
          <ShieldCheck className="w-12 h-12 mx-auto text-text-tertiary mb-4" />
          <p className="text-text-secondary">لا توجد مستندات {statusFilter === 'pending' ? 'بانتظار المراجعة' : statusFilter === 'approved' ? 'مقبولة' : statusFilter === 'rejected' ? 'مرفوضة' : ''}</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {docs.map((d) => (
            <div key={d.id} className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden flex flex-col">
              <div className="relative h-48 bg-surface-tertiary flex items-center justify-center overflow-hidden">
                {d.r2_key && d.r2_key.startsWith('docs/') ? (
                  <img src={fileUrl(d)} alt={d.type} className="w-full h-full object-cover" />
                ) : (
                  <FileText className="w-12 h-12 text-text-tertiary" />
                )}
                <div className="absolute top-2 right-2">
                  {d.status === 'pending' && <span className="px-2 py-0.5 text-xs font-bold rounded-full bg-warning-light text-warning-main">بانتظار</span>}
                  {d.status === 'approved' && <span className="px-2 py-0.5 text-xs font-bold rounded-full bg-success-light text-success-main">مقبول</span>}
                  {d.status === 'rejected' && <span className="px-2 py-0.5 text-xs font-bold rounded-full bg-error-light text-error-main">مرفوض</span>}
                </div>
              </div>
              <div className="p-4 flex-1 flex flex-col">
                <span className="text-sm font-bold text-text-primary mb-2">{docTypeLabels[d.type] || d.type}</span>
                <p className="text-sm text-text-secondary truncate">{d.captain_name || d.captain_email || d.captain_id.slice(0, 10)}</p>
                {d.captain_phone && <p className="text-xs text-text-tertiary">{d.captain_phone}</p>}
                <p className="text-xs text-text-tertiary mt-1">{new Date(d.created_at).toLocaleDateString('ar-EG')}</p>
                <div className="flex items-center gap-2 mt-3 pt-3 border-t border-border-primary">
                  <button onClick={() => setPreviewDoc(d)}
                    className="flex-1 flex items-center justify-center gap-1 px-3 py-2 bg-surface-secondary hover:bg-surface-tertiary text-text-secondary text-xs font-medium rounded-lg border border-border-primary transition-colors">
                    <Eye className="w-3.5 h-3.5" /> عرض
                  </button>
                  {d.status === 'pending' && (<>
                    <button onClick={() => review(d.id, 'approved')}
                      className="flex items-center justify-center gap-1 px-3 py-2 bg-success-main hover:bg-success-dark text-white text-xs font-medium rounded-lg transition-colors">
                      <Check className="w-3.5 h-3.5" /> قبول
                    </button>
                    <button onClick={() => review(d.id, 'rejected')}
                      className="flex items-center justify-center gap-1 px-3 py-2 bg-error-main/10 hover:bg-error-main/20 text-error-main text-xs font-medium rounded-lg border border-error-main/30 transition-colors">
                      <X className="w-3.5 h-3.5" /> رفض
                    </button>
                  </>)}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {previewDoc && (
        <div className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4" onClick={() => setPreviewDoc(null)}>
          <div className="relative max-w-3xl max-h-[90vh] w-full" onClick={(e) => e.stopPropagation()}>
            <button onClick={() => setPreviewDoc(null)}
              className="absolute -top-2 -left-2 z-10 w-10 h-10 rounded-full bg-surface-primary border border-border-primary flex items-center justify-center text-text-primary hover:bg-surface-hover">
              <X className="w-5 h-5" />
            </button>
            <img src={fileUrl(previewDoc)} alt={previewDoc.type} className="w-full h-full object-contain rounded-xl" />
            <div className="absolute bottom-0 left-0 right-0 p-4 bg-gradient-to-t from-black/80 to-transparent rounded-b-xl">
              <p className="text-white font-bold">{docTypeLabels[previewDoc.type] || previewDoc.type}</p>
              <p className="text-white/70 text-sm">{previewDoc.captain_name || previewDoc.captain_email}</p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}