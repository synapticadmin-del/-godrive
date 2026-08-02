import { useCallback, useState } from 'react';
import {
  AlertTriangle,
  ArrowUpRight,
  Bell,
  Check,
  CheckCircle,
  MapPin,
  Phone,
  Plus,
  RefreshCw,
  ShieldAlert,
} from 'lucide-react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { formatDate } from '../lib/utils';
import { usePolling } from '../lib/usePolling';
import { useToast } from '../components/ui/Toast';
import { Badge } from '../components/ui/Badge';
import { Button } from '../components/ui/Button';
import { Card } from '../components/ui/Card';
import { PageHeader } from '../components/layout/PageHeader';
import ReasonPrompt from '../components/ReasonPrompt';

/**
 * The SOS operator queue — gate item 10's operations half.
 *
 * Before this screen, a panic button produced a phone notification and nothing
 * else: once dismissed it was unrecoverable without direct D1 access (T11
 * F-11-02). An alert nobody can see is a safety feature that lies, which is
 * what item 10 is about.
 *
 * **This page adds no API of its own.** E13 already shipped the whole
 * admin-guarded surface under `/safety/sos*` — list, detail with the full
 * append-only trail, ack, free-text events, and resolve. Wiring a second copy
 * of those handlers into `routes/admin.ts` would be the duplication this
 * board exists to prevent, so the console calls E13's endpoints directly.
 *
 * Item 10 is split four ways (E05 · E09 · E13 · E14). This is one quarter of
 * it and closes nothing on its own.
 */

interface SosAlert {
  id: string;
  userId: string;
  tripId: string | null;
  lat: number | null;
  lng: number | null;
  reason: string | null;
  status: 'open' | 'resolved' | 'false_alarm' | string;
  acknowledged: boolean;
  acknowledgedAt: string | null;
  acknowledgedBy: string | null;
  resolvedAt: string | null;
  resolvedBy: string | null;
  createdAt: string;
}

interface SosEvent {
  id: string;
  event: string;
  actorId: string | null;
  actorRole: string | null;
  note: string | null;
  at: string;
}

type StatusFilter = 'open' | 'resolved' | 'false_alarm' | 'all';

const STATUS_TABS: { value: StatusFilter; label: string }[] = [
  { value: 'open', label: 'مفتوحة' },
  { value: 'resolved', label: 'مغلقة' },
  { value: 'false_alarm', label: 'إنذار خاطئ' },
  { value: 'all', label: 'الكل' },
];

const EVENT_LABELS: Record<string, string> = {
  raised: 'تم الإطلاق',
  acknowledged: 'استلمها مشغّل',
  escalated: 'تم التصعيد',
  contacted: 'تم التواصل',
  resolved: 'تم الحل',
  false_alarm: 'إنذار خاطئ',
  note: 'ملاحظة',
};

function statusVariant(status: string): 'danger' | 'success' | 'neutral' {
  if (status === 'open') return 'danger';
  if (status === 'resolved') return 'success';
  return 'neutral';
}

/** Minutes since the alert fired — the number an operator actually triages on. */
function ageMinutes(iso: string): number {
  const ms = Date.now() - new Date(iso).getTime();
  return Number.isFinite(ms) ? Math.max(0, Math.floor(ms / 60000)) : 0;
}

/** Poll fast enough that "within seconds of it firing" is true. */
const POLL_MS = 10000;

export default function SafetyPage() {
  const { token } = useAuth();
  const { addToast } = useToast();

  const [filter, setFilter] = useState<StatusFilter>('open');
  const [alerts, setAlerts] = useState<SosAlert[]>([]);
  const [unacknowledged, setUnacknowledged] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [selected, setSelected] = useState<SosAlert | null>(null);
  const [events, setEvents] = useState<SosEvent[]>([]);
  const [detailLoading, setDetailLoading] = useState(false);

  const [prompt, setPrompt] = useState<null | 'resolve' | 'note'>(null);
  const [busy, setBusy] = useState(false);

  const loadQueue = useCallback(() => {
    api<{ alerts: SosAlert[]; counts: { returned: number; unacknowledged: number } }>(
      `/safety/sos?status=${filter}&limit=100`,
      { token },
    )
      .then((r) => {
        setAlerts(r.alerts ?? []);
        setUnacknowledged(r.counts?.unacknowledged ?? 0);
        setError(null);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'فشل تحميل قائمة الاستغاثات'))
      .finally(() => setLoading(false));
  }, [filter, token]);

  usePolling(loadQueue, POLL_MS);

  const openDetail = useCallback(
    (alert: SosAlert) => {
      setSelected(alert);
      setDetailLoading(true);
      setEvents([]);
      api<{ alert: SosAlert; events: SosEvent[] }>(`/safety/sos/${alert.id}`, { token })
        .then((r) => {
          setSelected(r.alert);
          setEvents(r.events ?? []);
        })
        .catch((e) =>
          addToast({ type: 'error', message: e instanceof Error ? e.message : 'فشل تحميل التفاصيل' }),
        )
        .finally(() => setDetailLoading(false));
    },
    [token, addToast],
  );

  const acknowledge = async (alert: SosAlert) => {
    setBusy(true);
    try {
      const r = await api<{ ok: boolean; alreadyAcknowledged: boolean; acknowledgedBy?: string | null }>(
        `/safety/sos/${alert.id}/ack`,
        { token, method: 'POST', body: JSON.stringify({}) },
      );
      addToast({
        type: r.alreadyAcknowledged ? 'warning' : 'success',
        message: r.alreadyAcknowledged
          ? `الاستغاثة مُستلمة بالفعل${r.acknowledgedBy ? ` — ${r.acknowledgedBy}` : ''}`
          : 'تم استلام الاستغاثة باسمك',
      });
      loadQueue();
      openDetail(alert);
    } catch (e) {
      addToast({ type: 'error', message: e instanceof Error ? e.message : 'تعذّر الاستلام' });
    } finally {
      setBusy(false);
    }
  };

  const submitResolve = async (reason: string, outcome?: string) => {
    if (!selected) return;
    await api(`/safety/sos/${selected.id}/resolve`, {
      token,
      method: 'POST',
      body: JSON.stringify({ outcome: outcome ?? 'resolved', note: reason }),
    });
    addToast({ type: 'success', message: 'تم إغلاق الاستغاثة وتسجيل السبب' });
    loadQueue();
    openDetail(selected);
  };

  const submitEvent = async (reason: string, event?: string) => {
    if (!selected) return;
    await api(`/safety/sos/${selected.id}/events`, {
      token,
      method: 'POST',
      body: JSON.stringify({ event: event ?? 'note', note: reason }),
    });
    addToast({ type: 'success', message: 'تمت إضافة السجل' });
    openDetail(selected);
  };

  return (
    <div dir="rtl">
      <PageHeader
        title="الاستغاثات"
        subtitle="طابور الطوارئ — استلم الاستغاثة، سجّل ما حدث، ثم أغلقها بسبب."
        actions={
          <Button variant="secondary" size="sm" leftIcon={<RefreshCw className="w-4 h-4" />} onClick={loadQueue}>
            تحديث
          </Button>
        }
      />

      {unacknowledged > 0 && (
        <Card className="mb-4 border-error-main/40 bg-error-main/5">
          <div className="flex items-center gap-3">
            <Bell className="w-5 h-5 text-error-main animate-pulse" />
            <p className="text-sm font-bold text-error-main">
              {unacknowledged} استغاثة مفتوحة لم يستلمها أحد بعد.
            </p>
          </div>
        </Card>
      )}

      <div className="flex flex-wrap gap-2 mb-4">
        {STATUS_TABS.map((t) => (
          <button
            key={t.value}
            onClick={() => {
              setFilter(t.value);
              setLoading(true);
            }}
            className={`px-3 py-1.5 rounded-xl border text-xs font-bold transition-all ${
              filter === t.value
                ? 'bg-primary-500/10 border-primary-500 text-primary-500'
                : 'bg-surface-secondary border-border-primary text-text-secondary hover:border-border-secondary'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {error && (
        <Card className="mb-4 border-error-main/30">
          <p className="text-sm text-error-main font-bold">{error}</p>
        </Card>
      )}

      <div className="grid grid-cols-1 xl:grid-cols-5 gap-4">
        {/* Queue */}
        <div className="xl:col-span-3 space-y-2">
          {loading && alerts.length === 0 && (
            <Card><p className="text-sm text-text-tertiary">جاري التحميل...</p></Card>
          )}
          {!loading && alerts.length === 0 && (
            <Card>
              <div className="flex items-center gap-3 text-text-tertiary">
                <CheckCircle className="w-5 h-5 text-success-main" />
                <p className="text-sm">لا توجد استغاثات في هذا التصنيف.</p>
              </div>
            </Card>
          )}

          {alerts.map((a) => {
            const age = ageMinutes(a.createdAt);
            const isSelected = selected?.id === a.id;
            return (
              <Card
                key={a.id}
                hoverable
                onClick={() => openDetail(a)}
                className={`${isSelected ? 'ring-2 ring-primary-500' : ''} ${
                  a.status === 'open' && !a.acknowledged ? 'border-error-main/50' : ''
                }`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-start gap-3 min-w-0">
                    <div
                      className={`w-9 h-9 rounded-xl flex items-center justify-center shrink-0 ${
                        a.status === 'open' ? 'bg-error-main/10 text-error-main' : 'bg-surface-tertiary text-text-tertiary'
                      }`}
                    >
                      <ShieldAlert className="w-5 h-5" />
                    </div>
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <Badge variant={statusVariant(a.status)} size="sm">
                          {a.status === 'open' ? 'مفتوحة' : a.status === 'resolved' ? 'مغلقة' : 'إنذار خاطئ'}
                        </Badge>
                        {a.status === 'open' && (
                          <Badge variant={a.acknowledged ? 'info' : 'warning'} size="sm">
                            {a.acknowledged ? 'مُستلمة' : 'لم تُستلم'}
                          </Badge>
                        )}
                        <span className="text-[11px] text-text-tertiary">منذ {age} دقيقة</span>
                      </div>
                      <p className="text-sm font-bold text-text-primary mt-1 truncate">
                        {a.reason || 'بدون سبب مُدخل'}
                      </p>
                      <p className="text-[11px] text-text-tertiary mt-0.5 font-mono truncate">
                        {formatDate(a.createdAt)} • {a.id}
                      </p>
                    </div>
                  </div>

                  {a.status === 'open' && !a.acknowledged && (
                    <Button
                      size="xs"
                      variant="danger"
                      loading={busy}
                      leftIcon={<Check className="w-3.5 h-3.5" />}
                      onClick={(e) => {
                        e.stopPropagation();
                        void acknowledge(a);
                      }}
                    >
                      استلام
                    </Button>
                  )}
                </div>
              </Card>
            );
          })}
        </div>

        {/* Detail */}
        <div className="xl:col-span-2">
          <Card className="sticky top-4">
            {!selected && <p className="text-sm text-text-tertiary">اختر استغاثة لعرض تفاصيلها وسجلها.</p>}

            {selected && (
              <div className="space-y-4">
                <div>
                  <h3 className="text-base font-bold text-text-primary">تفاصيل الاستغاثة</h3>
                  <p className="text-[11px] text-text-tertiary font-mono mt-0.5">{selected.id}</p>
                </div>

                <dl className="space-y-2 text-xs">
                  <div className="flex justify-between gap-2">
                    <dt className="text-text-tertiary">الحالة</dt>
                    <dd><Badge variant={statusVariant(selected.status)} size="sm">{selected.status}</Badge></dd>
                  </div>
                  <div className="flex justify-between gap-2">
                    <dt className="text-text-tertiary">صاحب البلاغ</dt>
                    <dd className="font-mono text-text-primary truncate max-w-[60%]">{selected.userId}</dd>
                  </div>
                  <div className="flex justify-between gap-2">
                    <dt className="text-text-tertiary">الرحلة</dt>
                    <dd className="font-mono text-text-primary truncate max-w-[60%]">
                      {selected.tripId ?? '—'}
                    </dd>
                  </div>
                  {selected.acknowledgedBy && (
                    <div className="flex justify-between gap-2">
                      <dt className="text-text-tertiary">استلمها</dt>
                      <dd className="font-mono text-text-primary truncate max-w-[60%]">{selected.acknowledgedBy}</dd>
                    </div>
                  )}
                </dl>

                <div className="flex flex-wrap gap-2">
                  {selected.tripId && (
                    <a
                      href={`/trips?q=${encodeURIComponent(selected.tripId)}`}
                      className="inline-flex items-center gap-1 text-xs font-bold text-primary-500 hover:underline"
                    >
                      <ArrowUpRight className="w-3.5 h-3.5" /> فتح الرحلة
                    </a>
                  )}
                  <a
                    href={`/users?q=${encodeURIComponent(selected.userId)}`}
                    className="inline-flex items-center gap-1 text-xs font-bold text-primary-500 hover:underline"
                  >
                    <ArrowUpRight className="w-3.5 h-3.5" /> فتح حساب صاحب البلاغ
                  </a>
                  {selected.lat != null && selected.lng != null && (
                    <a
                      href={`https://www.google.com/maps?q=${selected.lat},${selected.lng}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 text-xs font-bold text-primary-500 hover:underline"
                    >
                      <MapPin className="w-3.5 h-3.5" /> الموقع وقت البلاغ
                    </a>
                  )}
                </div>

                {selected.status === 'open' && (
                  <div className="flex flex-wrap gap-2 pt-2 border-t border-border-primary">
                    {!selected.acknowledged && (
                      <Button size="xs" variant="danger" loading={busy}
                        leftIcon={<Check className="w-3.5 h-3.5" />}
                        onClick={() => void acknowledge(selected)}>
                        استلام
                      </Button>
                    )}
                    <Button size="xs" variant="secondary"
                      leftIcon={<Plus className="w-3.5 h-3.5" />}
                      onClick={() => setPrompt('note')}>
                      تسجيل إجراء
                    </Button>
                    <Button size="xs" variant="success"
                      leftIcon={<CheckCircle className="w-3.5 h-3.5" />}
                      onClick={() => setPrompt('resolve')}>
                      إغلاق
                    </Button>
                  </div>
                )}

                <div className="pt-2 border-t border-border-primary">
                  <h4 className="text-xs font-bold text-text-secondary mb-2">
                    السجل {detailLoading && <span className="text-text-tertiary">(تحميل...)</span>}
                  </h4>
                  {events.length === 0 && !detailLoading && (
                    <p className="text-xs text-text-tertiary">لا توجد أحداث مسجّلة.</p>
                  )}
                  <ol className="space-y-2">
                    {events.map((ev) => (
                      <li key={ev.id} className="flex gap-2 text-xs">
                        <div className="w-1.5 h-1.5 rounded-full bg-primary-500 mt-1.5 shrink-0" />
                        <div className="min-w-0">
                          <p className="font-bold text-text-primary">
                            {EVENT_LABELS[ev.event] ?? ev.event}
                            {ev.actorRole && (
                              <span className="text-text-tertiary font-normal"> • {ev.actorRole}</span>
                            )}
                          </p>
                          {ev.note && <p className="text-text-secondary mt-0.5 break-words">{ev.note}</p>}
                          <p className="text-[11px] text-text-tertiary mt-0.5">{formatDate(ev.at)}</p>
                        </div>
                      </li>
                    ))}
                  </ol>
                  <p className="text-[11px] text-text-tertiary mt-3 flex items-start gap-1.5">
                    <AlertTriangle className="w-3.5 h-3.5 shrink-0 mt-px" />
                    السجل غير قابل للتعديل أو الحذف — أي تصحيح يُضاف كسطر جديد.
                  </p>
                </div>
              </div>
            )}
          </Card>
        </div>
      </div>

      <ReasonPrompt
        isOpen={prompt === 'resolve'}
        title="إغلاق الاستغاثة"
        subtitle="السبب إلزامي ويُسجَّل في السجل غير القابل للتعديل."
        tone="success"
        confirmLabel="إغلاق الاستغاثة"
        choiceLabel="النتيجة"
        choices={[
          { value: 'resolved', label: 'تم التعامل معها' },
          { value: 'false_alarm', label: 'إنذار خاطئ' },
        ]}
        presets={['تم التواصل مع الراكب وتأكيد سلامته', 'تم إبلاغ الجهات المختصة', 'ضغط بالخطأ — تأكد عبر الهاتف']}
        onClose={() => setPrompt(null)}
        onSubmit={submitResolve}
      />

      <ReasonPrompt
        isOpen={prompt === 'note'}
        title="تسجيل إجراء"
        subtitle="لا يغيّر الحالة — يضيف سطراً إلى سجل الاستغاثة."
        tone="primary"
        confirmLabel="إضافة"
        choiceLabel="نوع الإجراء"
        choices={[
          { value: 'contacted', label: 'تم التواصل' },
          { value: 'escalated', label: 'تصعيد' },
          { value: 'note', label: 'ملاحظة' },
        ]}
        minLength={1}
        presets={['تم الاتصال بالراكب ولم يرد', 'تم تحويل الحالة إلى المشرف', 'تم إبلاغ الإسعاف']}
        onClose={() => setPrompt(null)}
        onSubmit={submitEvent}
      />

      <p className="mt-6 text-[11px] text-text-tertiary flex items-start gap-1.5">
        <Phone className="w-3.5 h-3.5 shrink-0 mt-px" />
        هذه الشاشة لا تُبلّغ أي جهة خارجية تلقائياً. أي تصعيد خارج المنصة إجراء يدوي ويجب تسجيله هنا.
      </p>
    </div>
  );
}
