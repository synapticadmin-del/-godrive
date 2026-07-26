import { useEffect, useState, useMemo } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import {
  ShieldCheck, Loader2, FileText, Check, X, Eye, ChevronDown, ChevronUp,
  User, Phone, Mail, FileCheck, Clock, AlertCircle
} from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';
import { RejectionReasonModal } from '../components/RejectionReasonModal';

interface Doc {
  id: string;
  captain_id: string;
  type: string;
  r2_key: string;
  status: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
  captain_name?: string;
  captain_email?: string;
  captain_phone?: string;
}

interface CaptainGroup {
  captainId: string;
  captainName: string;
  captainEmail: string;
  captainPhone: string;
  documents: Doc[];
  pendingCount: number;
  approvedCount: number;
  rejectedCount: number;
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

  // Rejection modal state
  const [rejectingDoc, setRejectingDoc] = useState<{ doc: Doc; captainName: string } | null>(null);

  // Accordion open/collapsed state per captain ID
  const [expandedCaptains, setExpandedCaptains] = useState<Record<string, boolean>>({});

  const load = async () => {
    try {
      setLoading(true);
      setError(null);
      const params = statusFilter ? `?status=${statusFilter}` : '';
      const res = await api<{ documents: Doc[] }>(`/admin/documents${params}`, { token });
      const fetchedDocs = res.documents || [];
      setDocs(fetchedDocs);

      // Expand all captain groups by default
      const initialExpanded: Record<string, boolean> = {};
      fetchedDocs.forEach((d) => {
        initialExpanded[d.captain_id] = true;
      });
      setExpandedCaptains((prev) => ({ ...initialExpanded, ...prev }));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'فشل تحميل مستندات الكباتن');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, [token, statusFilter]);

  // Group documents by Captain ID
  const captainGroups = useMemo(() => {
    const groupsMap = new Map<string, CaptainGroup>();

    docs.forEach((doc) => {
      const cId = doc.captain_id;
      if (!groupsMap.has(cId)) {
        groupsMap.set(cId, {
          captainId: cId,
          captainName: doc.captain_name || 'كابتن مجهول',
          captainEmail: doc.captain_email || '',
          captainPhone: doc.captain_phone || '',
          documents: [],
          pendingCount: 0,
          approvedCount: 0,
          rejectedCount: 0,
        });
      }

      const group = groupsMap.get(cId)!;
      group.documents.push(doc);
      if (doc.status === 'pending') group.pendingCount++;
      if (doc.status === 'approved') group.approvedCount++;
      if (doc.status === 'rejected') group.rejectedCount++;
    });

    return Array.from(groupsMap.values());
  }, [docs]);

  const toggleCaptainAccordion = (captainId: string) => {
    setExpandedCaptains((prev) => ({
      ...prev,
      [captainId]: !prev[captainId],
    }));
  };

  const approveDocument = async (docId: string) => {
    try {
      await api(`/admin/documents/${docId}/review`, {
        method: 'POST',
        token,
        body: JSON.stringify({ status: 'approved' }),
      });
      load();
    } catch {
      alert('فشل قبُول المستند');
    }
  };

  const handleRejectSubmit = async (reason: string) => {
    if (!rejectingDoc) return;
    const { doc } = rejectingDoc;
    try {
      // POST /admin/captains/:id/documents/:docId/reject
      await api(`/admin/captains/${doc.captain_id}/documents/${doc.id}/reject`, {
        method: 'POST',
        token,
        body: JSON.stringify({ reason }),
      });
      load();
    } catch {
      // Fallback endpoint if route is legacy
      await api(`/admin/documents/${doc.id}/review`, {
        method: 'POST',
        token,
        body: JSON.stringify({ status: 'rejected', reason }),
      });
      load();
    }
  };

  const fileUrl = (doc: Doc) =>
    `${API_BASE}/admin/documents/${doc.id}/file${token ? `?token=${encodeURIComponent(token)}` : ''}`;

  return (
    <div className="space-y-6 animate-fade-in" dir="rtl">
      {/* Header */}
      <PageHeader
        title="توثيق المستندات والتحقق من الكباتن"
        subtitle="مراجعة مستندات الكباتن، تدقيق رخص القيادة والسيارة قبل تفعيل الحسابات"
        actions={
          <div className="flex bg-surface-secondary rounded-xl p-1 border border-border-primary shadow-xs">
            {(
              [
                ['pending', 'بانتظار المراجعة'],
                ['approved', 'مستندات مقبولة'],
                ['rejected', 'مستندات مرفوضة'],
                ['', 'جميع المستندات'],
              ] as const
            ).map(([st, label]) => (
              <button
                key={st}
                onClick={() => setStatusFilter(st)}
                className={`px-3.5 py-1.5 text-xs font-bold rounded-lg transition-all ${
                  statusFilter === st
                    ? 'bg-primary-500 text-white shadow-xs'
                    : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        }
      />

      {error && (
        <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-2xl text-error-main text-sm font-bold flex items-center gap-2">
          <AlertCircle className="w-5 h-5 shrink-0" />
          {error}
        </div>
      )}

      {loading ? (
        <div className="space-y-4">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="bg-surface-primary border border-border-primary rounded-2xl p-6 animate-pulse space-y-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-4">
                  <div className="w-12 h-12 rounded-2xl bg-surface-tertiary" />
                  <div className="space-y-2">
                    <div className="h-4 w-40 bg-surface-tertiary rounded" />
                    <div className="h-3 w-60 bg-surface-tertiary rounded" />
                  </div>
                </div>
                <div className="h-8 w-24 bg-surface-tertiary rounded-lg" />
              </div>
            </div>
          ))}
        </div>
      ) : captainGroups.length === 0 ? (
        <div className="bg-surface-primary border border-border-primary rounded-2xl p-16 text-center space-y-4 shadow-xs">
          <div className="w-16 h-16 mx-auto rounded-3xl bg-surface-secondary flex items-center justify-center text-text-tertiary">
            <ShieldCheck className="w-8 h-8" />
          </div>
          <div>
            <h3 className="text-base font-bold text-text-primary">لا توجد مستندات للعرض</h3>
            <p className="text-sm text-text-tertiary mt-1">
              لم يتم العثور على أي مستندات في تصفية{' '}
              {statusFilter === 'pending'
                ? '"بانتظار المراجعة"'
                : statusFilter === 'approved'
                ? '"مقبولة"'
                : statusFilter === 'rejected'
                ? '"مرفوضة"'
                : '"الكل"'}
            </p>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          {captainGroups.map((group) => {
            const isExpanded = expandedCaptains[group.captainId] ?? true;

            return (
              <div
                key={group.captainId}
                className="bg-surface-primary border border-border-primary hover:border-border-secondary rounded-2xl overflow-hidden shadow-xs transition-all duration-200"
              >
                {/* Captain Profile Card Header (Accordion Trigger) */}
                <div
                  onClick={() => toggleCaptainAccordion(group.captainId)}
                  className="p-5 flex flex-col md:flex-row md:items-center justify-between gap-4 cursor-pointer select-none bg-gradient-to-r from-surface-primary to-surface-secondary/40 hover:bg-surface-hover/50 transition-colors"
                >
                  {/* Left (RTL Right): Captain Details */}
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 rounded-2xl bg-primary-500/10 border border-primary-500/20 flex items-center justify-center text-primary-500 font-extrabold text-lg shrink-0">
                      {group.captainName.charAt(0).toUpperCase()}
                    </div>

                    <div className="space-y-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <h3 className="font-extrabold text-base text-text-primary flex items-center gap-1.5">
                          <User className="w-4 h-4 text-primary-500" />
                          {group.captainName}
                        </h3>
                        {group.pendingCount > 0 ? (
                          <span className="px-2.5 py-0.5 text-[11px] font-bold rounded-full bg-warning-light text-warning-main border border-warning-main/30 flex items-center gap-1">
                            <Clock className="w-3 h-3" />
                            {group.pendingCount} مستندات معلقة
                          </span>
                        ) : group.rejectedCount > 0 ? (
                          <span className="px-2.5 py-0.5 text-[11px] font-bold rounded-full bg-error-light text-error-main border border-error-main/30 flex items-center gap-1">
                            <AlertCircle className="w-3 h-3" />
                            يتطلب تعديل مستندات
                          </span>
                        ) : (
                          <span className="px-2.5 py-0.5 text-[11px] font-bold rounded-full bg-success-light text-success-main border border-success-main/30 flex items-center gap-1">
                            <FileCheck className="w-3 h-3" />
                            مكتمل التوثيق ({group.approvedCount})
                          </span>
                        )}
                      </div>

                      <div className="flex items-center gap-4 text-xs text-text-tertiary flex-wrap">
                        {group.captainEmail && (
                          <span className="flex items-center gap-1 font-mono">
                            <Mail className="w-3.5 h-3.5 text-text-tertiary" />
                            {group.captainEmail}
                          </span>
                        )}
                        {group.captainPhone && (
                          <span className="flex items-center gap-1 font-mono">
                            <Phone className="w-3.5 h-3.5 text-text-tertiary" />
                            {group.captainPhone}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Right (RTL Left): Stats & Expand Button */}
                  <div className="flex items-center gap-3 shrink-0 self-end md:self-center">
                    <div className="flex items-center gap-2 text-xs bg-surface-secondary px-3 py-1.5 rounded-xl border border-border-primary">
                      <span className="text-text-secondary font-bold">المستندات ({group.documents.length}):</span>
                      {group.approvedCount > 0 && (
                        <span className="text-success-main font-bold font-mono">✓ {group.approvedCount}</span>
                      )}
                      {group.pendingCount > 0 && (
                        <span className="text-warning-main font-bold font-mono">⏳ {group.pendingCount}</span>
                      )}
                      {group.rejectedCount > 0 && (
                        <span className="text-error-main font-bold font-mono">✕ {group.rejectedCount}</span>
                      )}
                    </div>

                    <button
                      className="p-2 rounded-xl bg-surface-secondary text-text-secondary border border-border-primary hover:bg-surface-tertiary transition-colors"
                      title={isExpanded ? 'طي التفاصيل' : 'توسيع التفاصيل'}
                    >
                      {isExpanded ? <ChevronUp className="w-5 h-5" /> : <ChevronDown className="w-5 h-5" />}
                    </button>
                  </div>
                </div>

                {/* Accordion Content: Documents Grid */}
                {isExpanded && (
                  <div className="p-5 border-t border-border-primary bg-surface-secondary/20 animate-fade-in">
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                      {group.documents.map((d) => (
                        <div
                          key={d.id}
                          className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden flex flex-col transition-all hover:border-primary-500/40 shadow-xs"
                        >
                          {/* Document Image / Thumbnail Header */}
                          <div className="relative h-44 bg-surface-tertiary flex items-center justify-center overflow-hidden group">
                            {d.r2_key && d.r2_key.startsWith('docs/') ? (
                              <img
                                src={fileUrl(d)}
                                alt={d.type}
                                className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                              />
                            ) : (
                              <FileText className="w-12 h-12 text-text-tertiary" />
                            )}

                            {/* Hover Overlay Preview Button */}
                            <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                              <button
                                onClick={() => setPreviewDoc(d)}
                                className="px-3.5 py-2 bg-surface-primary/90 text-text-primary text-xs font-bold rounded-xl shadow-lg flex items-center gap-1.5 backdrop-blur-md hover:bg-surface-primary"
                              >
                                <Eye className="w-4 h-4 text-primary-500" />
                                المعاينة الكاملة
                              </button>
                            </div>

                            {/* Document Status Badge */}
                            <div className="absolute top-2.5 right-2.5">
                              {d.status === 'pending' && (
                                <span className="px-2.5 py-1 text-[11px] font-bold rounded-lg bg-warning-main text-white shadow-xs">
                                  بانتظار المراجعة
                                </span>
                              )}
                              {d.status === 'approved' && (
                                <span className="px-2.5 py-1 text-[11px] font-bold rounded-lg bg-success-main text-white shadow-xs">
                                  مقبول ✓
                                </span>
                              )}
                              {d.status === 'rejected' && (
                                <span className="px-2.5 py-1 text-[11px] font-bold rounded-lg bg-error-main text-white shadow-xs">
                                  مرفوض ✕
                                </span>
                              )}
                            </div>
                          </div>

                          {/* Document Info Body */}
                          <div className="p-4 flex-1 flex flex-col justify-between space-y-3">
                            <div>
                              <div className="flex items-center justify-between mb-1">
                                <span className="text-xs font-bold text-primary-600 dark:text-primary-400 bg-primary-500/10 px-2 py-0.5 rounded-md border border-primary-500/20">
                                  {docTypeLabels[d.type] || d.type}
                                </span>
                                <span className="text-[10px] text-text-tertiary font-mono">
                                  {new Date(d.created_at).toLocaleDateString('ar-EG')}
                                </span>
                              </div>
                            </div>

                            {/* Action Buttons */}
                            <div className="flex items-center gap-2 pt-2 border-t border-border-primary">
                              <button
                                onClick={() => setPreviewDoc(d)}
                                className="flex-1 flex items-center justify-center gap-1 px-3 py-2 bg-surface-secondary hover:bg-surface-hover text-text-secondary text-xs font-bold rounded-xl border border-border-primary transition-colors"
                              >
                                <Eye className="w-3.5 h-3.5" /> عرض
                              </button>

                              {d.status === 'pending' && (
                                <>
                                  <button
                                    onClick={() => approveDocument(d.id)}
                                    className="flex-1 flex items-center justify-center gap-1 px-3 py-2 bg-success-main hover:bg-success-dark text-white text-xs font-bold rounded-xl shadow-xs transition-colors"
                                  >
                                    <Check className="w-3.5 h-3.5" /> قبول
                                  </button>
                                  <button
                                    onClick={() =>
                                      setRejectingDoc({
                                        doc: d,
                                        captainName: group.captainName,
                                      })
                                    }
                                    className="flex-1 flex items-center justify-center gap-1 px-3 py-2 bg-error-main/10 hover:bg-error-main/20 text-error-main text-xs font-bold rounded-xl border border-error-main/30 transition-colors"
                                  >
                                    <X className="w-3.5 h-3.5" /> رفض
                                  </button>
                                </>
                              )}
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Full Document Image Preview Modal */}
      {previewDoc && (
        <div
          className="fixed inset-0 z-50 bg-black/85 backdrop-blur-md flex items-center justify-center p-4 animate-fade-in"
          onClick={() => setPreviewDoc(null)}
        >
          <div
            className="relative max-w-4xl max-h-[90vh] w-full bg-surface-primary border border-border-primary rounded-2xl overflow-hidden shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              onClick={() => setPreviewDoc(null)}
              className="absolute top-4 left-4 z-10 w-10 h-10 rounded-full bg-black/60 border border-white/20 flex items-center justify-center text-white hover:bg-black transition-colors"
            >
              <X className="w-5 h-5" />
            </button>

            <div className="p-4 bg-surface-secondary border-b border-border-primary flex items-center justify-between">
              <div>
                <h4 className="font-bold text-text-primary text-sm">
                  {docTypeLabels[previewDoc.type] || previewDoc.type}
                </h4>
                <p className="text-xs text-text-tertiary">
                  {previewDoc.captain_name || previewDoc.captain_email}
                </p>
              </div>
            </div>

            <div className="p-6 flex items-center justify-center max-h-[75vh] overflow-auto bg-black/90">
              <img
                src={fileUrl(previewDoc)}
                alt={previewDoc.type}
                className="max-w-full max-h-[70vh] object-contain rounded-xl shadow-lg"
              />
            </div>
          </div>
        </div>
      )}

      {/* Quick Rejection Reasons Preset Modal */}
      {rejectingDoc && (
        <RejectionReasonModal
          isOpen={!!rejectingDoc}
          docTitle={docTypeLabels[rejectingDoc.doc.type] || rejectingDoc.doc.type}
          captainName={rejectingDoc.captainName}
          onClose={() => setRejectingDoc(null)}
          onSubmit={handleRejectSubmit}
        />
      )}
    </div>
  );
}