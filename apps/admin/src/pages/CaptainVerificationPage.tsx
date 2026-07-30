import { useEffect, useState, useMemo, useCallback, useRef } from 'react';
import { api, fetchDocumentBlobUrl, resolveAvatarUrl } from '../lib/api';
import { useAuth } from '../lib/auth';
import {
  ShieldCheck, Loader2, FileText, Check, X, Eye, ChevronDown, ChevronUp,
  User, Phone, Mail, FileCheck, Clock, AlertCircle, ZoomIn, ZoomOut,
  RotateCcw, ChevronLeft, ChevronRight, CheckCheck, CalendarDays
} from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';
import { RejectionReasonModal } from '../components/RejectionReasonModal';
import { useToast } from '../components/ui/Toast';

interface Doc {
  id: string;
  captain_id: string;
  type: string;
  r2_key: string;
  status: string;
  rejection_reason?: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
  captain_name?: string;
  captain_email?: string;
  captain_phone?: string;
  captain_avatar_url?: string;
}

interface CaptainGroup {
  captainId: string;
  captainName: string;
  captainEmail: string;
  captainPhone: string;
  captainAvatarUrl?: string | null;
  documents: Doc[];
  pendingCount: number;
  approvedCount: number;
  rejectedCount: number;
}

const fallbackDocTypeLabels: Record<string, string> = {
  license: 'رخصة القيادة',
  national_id: 'بطاقة رقم قومي',
  criminal_record: 'فيش جنائي',
  vehicle_reg: 'رخصة السيارة',
};

const docTypeLabel = (doc: Doc) => {
  const typeKey = doc.type || (doc as any).document_type || '';
  return fallbackDocTypeLabels[typeKey] || typeKey;
};

/**
 * Fetch a protected document as an authenticated blob URL and manage its
 * lifecycle: the object URL is revoked whenever the doc changes or the caller
 * unmounts, so we never leak blob URLs. The JWT travels in the Authorization
 * header — never in the document URL (which would leak it into logs/history).
 */
function useDocumentBlobUrl(docId: string | null | undefined): string | null {
  const [blobUrl, setBlobUrl] = useState<string | null>(null);

  useEffect(() => {
    if (!docId) {
      setBlobUrl(null);
      return;
    }
    let objectUrl: string | null = null;
    let cancelled = false;

    fetchDocumentBlobUrl(docId)
      .then((url) => {
        if (cancelled) {
          URL.revokeObjectURL(url);
          return;
        }
        objectUrl = url;
        setBlobUrl(url);
      })
      .catch(() => {
        if (!cancelled) setBlobUrl(null);
      });

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [docId]);

  return blobUrl;
}

/** Authenticated document thumbnail; identical layout to the previous <img>. */
function DocumentImage({ doc, className }: { doc: Doc; className?: string }) {
  const blobUrl = useDocumentBlobUrl(doc.id);
  if (!blobUrl) {
    return (
      <div className={`${className ?? ''} flex items-center justify-center bg-surface-tertiary`}>
        <Loader2 className="w-6 h-6 text-text-tertiary animate-spin" />
      </div>
    );
  }
  return <img src={blobUrl} alt={doc.type} className={className} />;
}

/* ------------------------------------------------------------------ */
/*  Zoomable Preview Modal                                            */
/* ------------------------------------------------------------------ */
function ZoomablePreviewModal({
  doc,
  allDocs,
  onClose,
  onNavigate,
}: {
  doc: Doc;
  allDocs: Doc[];
  onClose: () => void;
  onNavigate: (d: Doc) => void;
}) {
  const [scale, setScale] = useState(1);
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const [dragging, setDragging] = useState(false);
  const dragStart = useRef({ x: 0, y: 0 });
  const posStart = useRef({ x: 0, y: 0 });

  // Authenticated blob URL for the currently-previewed doc; revoked on change/close.
  const blobUrl = useDocumentBlobUrl(doc.id);

  const currentIdx = allDocs.findIndex((d) => d.id === doc.id);
  const hasPrev = currentIdx > 0;
  const hasNext = currentIdx < allDocs.length - 1;

  const resetView = useCallback(() => {
    setScale(1);
    setPosition({ x: 0, y: 0 });
  }, []);

  const zoomIn = useCallback(() => setScale((s) => Math.min(s + 0.5, 5)), []);
  const zoomOut = useCallback(() => {
    setScale((s) => {
      const next = Math.max(s - 0.5, 0.5);
      if (next <= 1) setPosition({ x: 0, y: 0 });
      return next;
    });
  }, []);

  const goPrev = useCallback(() => {
    if (hasPrev) { resetView(); onNavigate(allDocs[currentIdx - 1]); }
  }, [hasPrev, currentIdx, allDocs, onNavigate, resetView]);

  const goNext = useCallback(() => {
    if (hasNext) { resetView(); onNavigate(allDocs[currentIdx + 1]); }
  }, [hasNext, currentIdx, allDocs, onNavigate, resetView]);

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
      if (e.key === '+' || e.key === '=') zoomIn();
      if (e.key === '-') zoomOut();
      if (e.key === '0') resetView();
      if (e.key === 'ArrowLeft') goNext(); // RTL: left = next
      if (e.key === 'ArrowRight') goPrev(); // RTL: right = prev
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose, zoomIn, zoomOut, resetView, goPrev, goNext]);

  const onMouseDown = (e: React.MouseEvent) => {
    if (scale <= 1) return;
    setDragging(true);
    dragStart.current = { x: e.clientX, y: e.clientY };
    posStart.current = { ...position };
  };

  const onMouseMove = (e: React.MouseEvent) => {
    if (!dragging) return;
    setPosition({
      x: posStart.current.x + (e.clientX - dragStart.current.x),
      y: posStart.current.y + (e.clientY - dragStart.current.y),
    });
  };

  const onMouseUp = () => setDragging(false);

  return (
    <div
      className="fixed inset-0 z-50 bg-black/90 backdrop-blur-md flex flex-col animate-fade-in"
      onClick={onClose}
      dir="rtl"
    >
      {/* Top Bar */}
      <div
        className="flex items-center justify-between px-5 py-3 bg-black/50 border-b border-white/10"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-primary-500/20 border border-primary-500/30 flex items-center justify-center text-primary-400">
            <FileText className="w-4 h-4" />
          </div>
          <div>
            <h4 className="font-bold text-white text-sm">
              {docTypeLabel(doc)}
            </h4>
            <p className="text-xs text-white/50">
              {doc.captain_name || doc.captain_email} • {currentIdx + 1} من {allDocs.length}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {/* Zoom controls */}
          <div className="flex items-center gap-1 bg-white/10 rounded-xl border border-white/10 px-1 py-1">
            <button onClick={zoomOut} className="p-1.5 text-white/70 hover:text-white rounded-lg hover:bg-white/10 transition-colors" title="تصغير (-)">
              <ZoomOut className="w-4 h-4" />
            </button>
            <span className="text-xs text-white/60 font-mono min-w-[3rem] text-center">{Math.round(scale * 100)}%</span>
            <button onClick={zoomIn} className="p-1.5 text-white/70 hover:text-white rounded-lg hover:bg-white/10 transition-colors" title="تكبير (+)">
              <ZoomIn className="w-4 h-4" />
            </button>
            <button onClick={resetView} className="p-1.5 text-white/70 hover:text-white rounded-lg hover:bg-white/10 transition-colors" title="إعادة ضبط (0)">
              <RotateCcw className="w-4 h-4" />
            </button>
          </div>

          {/* Navigation */}
          <div className="flex items-center gap-1 bg-white/10 rounded-xl border border-white/10 px-1 py-1">
            <button
              onClick={goPrev}
              disabled={!hasPrev}
              className="p-1.5 text-white/70 hover:text-white rounded-lg hover:bg-white/10 transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
              title="المستند السابق"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
            <button
              onClick={goNext}
              disabled={!hasNext}
              className="p-1.5 text-white/70 hover:text-white rounded-lg hover:bg-white/10 transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
              title="المستند التالي"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
          </div>

          <button
            onClick={onClose}
            className="p-2 rounded-xl bg-white/10 border border-white/10 text-white hover:bg-white/20 transition-colors"
            title="إغلاق (Esc)"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
      </div>

      {/* Image Area */}
      <div
        className="flex-1 flex items-center justify-center overflow-hidden"
        onClick={(e) => e.stopPropagation()}
        onMouseDown={onMouseDown}
        onMouseMove={onMouseMove}
        onMouseUp={onMouseUp}
        onMouseLeave={onMouseUp}
        style={{ cursor: scale > 1 ? (dragging ? 'grabbing' : 'grab') : 'default' }}
      >
        {blobUrl ? (
          <img
            src={blobUrl}
            alt={doc.type}
            className="max-w-full max-h-full object-contain transition-transform duration-200 select-none"
            style={{
              transform: `scale(${scale}) translate(${position.x / scale}px, ${position.y / scale}px)`,
            }}
            draggable={false}
          />
        ) : (
          <Loader2 className="w-8 h-8 text-white/70 animate-spin" />
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Main Page                                                         */
/* ------------------------------------------------------------------ */
export default function CaptainVerificationPage() {
  const { token } = useAuth();
  const { addToast } = useToast();
  const [docs, setDocs] = useState<Doc[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('pending');
  const [previewDoc, setPreviewDoc] = useState<Doc | null>(null);
  const [previewGroup, setPreviewGroup] = useState<Doc[]>([]);
  const [bulkApproving, setBulkApproving] = useState<string | null>(null);

  // Two-step confirm for the bulk "قبول الجميع" action. Holds the captain id
  // awaiting confirmation; auto-reverts after a few seconds if not confirmed.
  const [confirmBulkId, setConfirmBulkId] = useState<string | null>(null);
  const confirmBulkTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

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
          captainAvatarUrl: doc.captain_avatar_url || null,
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
      addToast({ type: 'success', message: 'تم قبول المستند' });
      load();
    } catch (e) {
      addToast({ type: 'error', message: e instanceof Error ? e.message : 'فشل قبُول المستند' });
    }
  };

  const bulkApproveAll = async (group: CaptainGroup) => {
    const pendingDocs = group.documents.filter((d) => d.status === 'pending');
    if (pendingDocs.length === 0) return;

    setBulkApproving(group.captainId);
    try {
      for (const doc of pendingDocs) {
        await api(`/admin/documents/${doc.id}/review`, {
          method: 'POST',
          token,
          body: JSON.stringify({ status: 'approved' }),
        });
      }
      addToast({ type: 'success', message: `تم قبول ${pendingDocs.length.toLocaleString('ar-EG')} مستندات لـ ${group.captainName}` });
      load();
    } catch (e) {
      addToast({ type: 'error', message: e instanceof Error ? e.message : 'فشل في قبول بعض المستندات' });
    } finally {
      setBulkApproving(null);
    }
  };

  // Bulk-approve is destructive (accepts every pending doc at once), so it
  // goes through a two-step confirm: the first click arms the button (label
  // flips to "تأكيد القبول؟" and auto-reverts after 3s), the second runs it.
  const requestBulkApprove = (group: CaptainGroup) => {
    if (confirmBulkId === group.captainId) {
      if (confirmBulkTimer.current) clearTimeout(confirmBulkTimer.current);
      setConfirmBulkId(null);
      bulkApproveAll(group);
      return;
    }
    if (confirmBulkTimer.current) clearTimeout(confirmBulkTimer.current);
    setConfirmBulkId(group.captainId);
    confirmBulkTimer.current = setTimeout(() => setConfirmBulkId(null), 3000);
  };

  useEffect(() => () => {
    if (confirmBulkTimer.current) clearTimeout(confirmBulkTimer.current);
  }, []);

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

  const openPreview = (doc: Doc, groupDocs: Doc[]) => {
    setPreviewDoc(doc);
    setPreviewGroup(groupDocs);
  };

  /* ------------------------------------------------------------ */
  /*  Status badge for a single document                          */
  /* ------------------------------------------------------------ */
  const statusBadge = (d: Doc) => {
    if (d.status === 'pending') {
      return (
        <span className="px-2.5 py-1 text-[11px] font-bold rounded-lg bg-warning-main text-white shadow-xs flex items-center gap-1">
          <Clock className="w-3 h-3" /> بانتظار المراجعة
        </span>
      );
    }
    if (d.status === 'approved') {
      return (
        <span className="px-2.5 py-1 text-[11px] font-bold rounded-lg bg-success-main text-white shadow-xs flex items-center gap-1">
          <Check className="w-3 h-3" /> مقبول
        </span>
      );
    }
    if (d.status === 'rejected') {
      return (
        <span className="px-2.5 py-1 text-[11px] font-bold rounded-lg bg-error-main text-white shadow-xs flex items-center gap-1">
          <X className="w-3 h-3" /> مرفوض
        </span>
      );
    }
    return null;
  };

  /* ------------------------------------------------------------ */
  /*  Captain header badge                                        */
  /* ------------------------------------------------------------ */
  const captainStatusBadge = (group: CaptainGroup) => {
    if (group.pendingCount > 0) {
      return (
        <span className="px-2.5 py-1 text-[11px] font-bold rounded-full bg-warning-light text-warning-main border border-warning-main/30 flex items-center gap-1">
          <Clock className="w-3 h-3" />
          {group.pendingCount} مستندات معلقة
        </span>
      );
    }
    if (group.rejectedCount > 0) {
      return (
        <span className="px-2.5 py-1 text-[11px] font-bold rounded-full bg-error-light text-error-main border border-error-main/30 flex items-center gap-1">
          <AlertCircle className="w-3 h-3" />
          يتطلب تعديل مستندات
        </span>
      );
    }
    return (
      <span className="px-2.5 py-1 text-[11px] font-bold rounded-full bg-success-light text-success-main border border-success-main/30 flex items-center gap-1">
        <FileCheck className="w-3 h-3" />
        مكتمل التوثيق ({group.approvedCount})
      </span>
    );
  };

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
                  <div className="w-14 h-14 rounded-2xl bg-surface-tertiary" />
                  <div className="space-y-2">
                    <div className="h-4 w-40 bg-surface-tertiary rounded" />
                    <div className="h-3 w-60 bg-surface-tertiary rounded" />
                  </div>
                </div>
                <div className="h-8 w-24 bg-surface-tertiary rounded-lg" />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="h-56 bg-surface-tertiary rounded-xl" />
                <div className="h-56 bg-surface-tertiary rounded-xl" />
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
        <div className="space-y-5">
          {captainGroups.map((group) => {
            const isExpanded = expandedCaptains[group.captainId] ?? true;
            const allPending = group.pendingCount > 0 && group.pendingCount === group.documents.length;
            const isBulkApproving = bulkApproving === group.captainId;
            const isBulkConfirming = confirmBulkId === group.captainId;

            return (
              <div
                key={group.captainId}
                className="bg-surface-primary border border-border-primary hover:border-border-secondary rounded-2xl overflow-hidden shadow-xs transition-all duration-200"
              >
                {/* ─── Captain Profile Card Header ─── */}
                <div
                  onClick={() => toggleCaptainAccordion(group.captainId)}
                  className="p-5 flex flex-col md:flex-row md:items-center justify-between gap-4 cursor-pointer select-none bg-gradient-to-r from-surface-primary to-surface-secondary/40 hover:bg-surface-hover/50 transition-colors"
                >
                  {/* Captain Identity */}
                  <div className="flex items-center gap-4">
                    {/* Avatar with gradient ring */}
                    <div className="relative">
                      {resolveAvatarUrl(group.captainAvatarUrl) ? (
                        <img
                          src={resolveAvatarUrl(group.captainAvatarUrl)!}
                          alt=""
                          className="w-14 h-14 rounded-2xl object-cover border-2 border-primary-500/20 shadow-md shrink-0"
                        />
                      ) : (
                        <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-primary-400 to-primary-600 flex items-center justify-center text-white font-extrabold text-xl shadow-md shadow-primary-500/20 shrink-0">
                          {group.captainName.charAt(0).toUpperCase()}
                        </div>
                      )}
                      {/* Status dot */}
                      <div className={`absolute -bottom-0.5 -left-0.5 w-4 h-4 rounded-full border-2 border-surface-primary ${
                        group.pendingCount > 0 ? 'bg-warning-main' : group.rejectedCount > 0 ? 'bg-error-main' : 'bg-success-main'
                      }`} />
                    </div>

                    <div className="space-y-1.5">
                      <div className="flex items-center gap-2 flex-wrap">
                        <h3 className="font-extrabold text-base text-text-primary flex items-center gap-1.5">
                          <User className="w-4 h-4 text-primary-500" />
                          {group.captainName}
                        </h3>
                        {captainStatusBadge(group)}
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
                        {group.documents[0]?.created_at && (
                          <span className="flex items-center gap-1">
                            <CalendarDays className="w-3.5 h-3.5 text-text-tertiary" />
                            {new Date(group.documents[0].created_at).toLocaleDateString('ar-EG', { year: 'numeric', month: 'short', day: 'numeric' })}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Right: Stats + Bulk Approve + Expand */}
                  <div className="flex items-center gap-3 shrink-0 self-end md:self-center">
                    {/* Document count chips */}
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

                    {/* Bulk approve (only when all docs are pending) */}
                    {allPending && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          requestBulkApprove(group);
                        }}
                        disabled={isBulkApproving}
                        className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold rounded-xl shadow-xs transition-colors disabled:opacity-60 text-white ${
                          isBulkConfirming ? 'bg-warning-main hover:bg-warning-dark' : 'bg-success-main hover:bg-success-dark'
                        }`}
                        title={isBulkConfirming ? 'اضغط مرة أخرى للتأكيد' : 'قبول جميع المستندات دفعة واحدة'}
                      >
                        {isBulkApproving ? (
                          <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        ) : (
                          <CheckCheck className="w-3.5 h-3.5" />
                        )}
                        {isBulkConfirming ? 'تأكيد القبول؟' : 'قبول الجميع'}
                      </button>
                    )}

                    <button
                      className="p-2 rounded-xl bg-surface-secondary text-text-secondary border border-border-primary hover:bg-surface-tertiary transition-colors"
                      title={isExpanded ? 'طي التفاصيل' : 'توسيع التفاصيل'}
                    >
                      {isExpanded ? <ChevronUp className="w-5 h-5" /> : <ChevronDown className="w-5 h-5" />}
                    </button>
                  </div>
                </div>

                {/* ─── Accordion: Side-by-Side Document Grid ─── */}
                {isExpanded && (
                  <div className="p-5 border-t border-border-primary bg-surface-secondary/20 animate-fade-in">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      {group.documents.map((d) => (
                        <div
                          key={d.id}
                          className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden flex flex-col transition-all hover:border-primary-500/40 hover:shadow-md shadow-xs"
                        >
                          {/* Document Image / Thumbnail */}
                          <div className="relative h-56 bg-surface-tertiary flex items-center justify-center overflow-hidden group">
                            {d.r2_key && d.r2_key.startsWith('docs/') ? (
                              <DocumentImage
                                doc={d}
                                className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                              />
                            ) : (
                              <FileText className="w-12 h-12 text-text-tertiary" />
                            )}

                            {/* Hover Overlay */}
                            <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                              <button
                                onClick={() => openPreview(d, group.documents)}
                                className="px-4 py-2.5 bg-surface-primary/90 text-text-primary text-xs font-bold rounded-xl shadow-lg flex items-center gap-2 backdrop-blur-md hover:bg-surface-primary transition-colors"
                              >
                                <Eye className="w-4 h-4 text-primary-500" />
                                معاينة كاملة مع تكبير
                              </button>
                            </div>

                            {/* Status Badge */}
                            <div className="absolute top-2.5 right-2.5">
                              {statusBadge(d)}
                            </div>
                          </div>

                          {/* Document Info */}
                          <div className="p-4 flex-1 flex flex-col justify-between space-y-3">
                            <div>
                              <div className="flex items-center gap-2 mb-2">
                                <FileText className="w-4 h-4 text-primary-500" />
                                <h4 className="text-sm font-extrabold text-text-primary">
                                  {docTypeLabel(d)}
                                </h4>
                                {d.status === 'pending' && <span className="px-1.5 py-0.5 rounded bg-warning-main/10 text-warning-main text-[10px] font-bold">جديد</span>}
                                <span className="text-[10px] text-text-tertiary font-mono ml-auto">
                                  {new Date(d.created_at).toLocaleDateString('ar-EG')}
                                </span>
                              </div>

                              {/* Rejection reason display */}
                              {d.status === 'rejected' && d.rejection_reason && (
                                <div className="mt-2 p-2.5 bg-error-main/5 border border-error-main/20 rounded-lg">
                                  <p className="text-[11px] font-bold text-error-main flex items-center gap-1 mb-0.5">
                                    <AlertCircle className="w-3 h-3" /> سبب الرفض:
                                  </p>
                                  <p className="text-xs text-text-secondary">{d.rejection_reason}</p>
                                </div>
                              )}
                            </div>

                            {/* Action Buttons */}
                            <div className="flex items-center gap-2 pt-2 border-t border-border-primary">
                              <button
                                onClick={() => openPreview(d, group.documents)}
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

      {/* ─── Zoomable Full-Screen Preview Modal ─── */}
      {previewDoc && (
        <ZoomablePreviewModal
          doc={previewDoc}
          allDocs={previewGroup}
          onClose={() => { setPreviewDoc(null); setPreviewGroup([]); }}
          onNavigate={(d) => setPreviewDoc(d)}
        />
      )}

      {/* ─── Rejection Reason Modal ─── */}
      {rejectingDoc && (
        <RejectionReasonModal
          isOpen={!!rejectingDoc}
          docTitle={docTypeLabel(rejectingDoc.doc)}
          captainName={rejectingDoc.captainName}
          onClose={() => setRejectingDoc(null)}
          onSubmit={handleRejectSubmit}
        />
      )}
    </div>
  );
}
