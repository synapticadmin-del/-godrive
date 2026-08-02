import { useCallback, useState } from 'react';
import {
  AlertTriangle,
  Ban,
  CheckCircle,
  DollarSign,
  RefreshCw,
} from 'lucide-react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { formatCurrency, formatDate } from '../lib/utils';
import { usePolling } from '../lib/usePolling';
import { useToast } from '../components/ui/Toast';
import { Badge } from '../components/ui/Badge';
import { Button } from '../components/ui/Button';
import { Card } from '../components/ui/Card';
import { PageHeader } from '../components/layout/PageHeader';
import ReasonPrompt from '../components/ReasonPrompt';

/**
 * The payout queue — gate item 4's operations half.
 *
 * E06 stopped `POST /captain/wallet/payout` from debiting at request time and
 * moved the request into its own `payout_requests` table, which made the
 * platform stop minting liability but left the queue unworkable: no screen and
 * no endpoint could settle a row (F-11-04). This is that screen.
 *
 * **The captain's balance moves in exactly one place** — E06's
 * `settlePayoutRequest`, called by `POST /admin/payouts/:id/approve`. Neither
 * this page nor `routes/admin.ts` contains wallet SQL. Approving is the only
 * action in the product that debits for a payout, and rejecting moves nothing
 * because nothing was ever taken.
 *
 * Item 4 is split with E06 and closes only when both have merged.
 */

interface PayoutRequest {
  id: string;
  user_id: string;
  amount: number;
  amount_piastres: number;
  currency: string;
  method: 'bank_transfer' | 'vodafone_cash' | 'instapay' | 'fawry' | string;
  account_info: string;
  status: 'requested' | 'paid' | 'rejected' | string;
  wallet_transaction_id: string | null;
  decided_by: string | null;
  decided_at: string | null;
  decision_reason: string | null;
  created_at: string;
  updated_at: string;
  user_name: string | null;
  user_phone: string | null;
  user_balance: number;
}

type StatusFilter = 'requested' | 'paid' | 'rejected' | 'all';

const STATUS_TABS: { value: StatusFilter; label: string }[] = [
  { value: 'requested', label: 'قيد الانتظار' },
  { value: 'paid', label: 'مدفوعة' },
  { value: 'rejected', label: 'مرفوضة' },
  { value: 'all', label: 'الكل' },
];

const METHOD_LABELS: Record<string, string> = {
  bank_transfer: 'تحويل بنكي',
  vodafone_cash: 'فودافون كاش',
  instapay: 'إنستاباي',
  fawry: 'فوري',
};

const STATUS_LABELS: Record<string, { label: string; variant: 'warning' | 'success' | 'danger' | 'neutral' }> = {
  requested: { label: 'قيد الانتظار', variant: 'warning' },
  paid: { label: 'مدفوعة', variant: 'success' },
  rejected: { label: 'مرفوضة', variant: 'danger' },
};

const POLL_MS = 30000;

export default function PayoutsPage() {
  const { token } = useAuth();
  const { addToast } = useToast();

  const [filter, setFilter] = useState<StatusFilter>('requested');
  const [requests, setRequests] = useState<PayoutRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [target, setTarget] = useState<PayoutRequest | null>(null);
  const [action, setAction] = useState<null | 'approve' | 'reject'>(null);

  const load = useCallback(() => {
    api<{ requests: PayoutRequest[]; counts: { returned: number; open: number } }>(
      `/admin/payouts?status=${filter}&limit=100`,
      { token },
    )
      .then((r) => {
        setRequests(r.requests ?? []);
        setError(null);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'فشل تحميل طلبات السحب'))
      .finally(() => setLoading(false));
  }, [filter, token]);

  usePolling(load, POLL_MS);

  const submitDecision = async (reason: string) => {
    if (!target || !action) return;
    const res = await api<{ ok: boolean; walletTransactionId: string | null }>(
      `/admin/payouts/${target.id}/${action}`,
      { token, method: 'POST', body: JSON.stringify({ reason }) },
    );
    addToast({
      type: 'success',
      message:
        action === 'approve'
          ? `تم الصرف وخُصم المبلغ من محفظة الكابتن${res.walletTransactionId ? ` — ${res.walletTransactionId}` : ''}`
          : 'تم رفض الطلب وتسجيل السبب. لم يتحرك أي رصيد.',
    });
    setTarget(null);
    setAction(null);
    load();
  };

  const openCount = requests.filter((r) => r.status === 'requested').length;
  const openTotal = requests
    .filter((r) => r.status === 'requested')
    .reduce((sum, r) => sum + (r.amount ?? 0), 0);

  return (
    <div dir="rtl">
      <PageHeader
        title="طلبات السحب"
        subtitle="الموافقة تخصم من محفظة الكابتن. الرفض لا يحرّك أي رصيد."
        actions={
          <Button variant="secondary" size="sm" leftIcon={<RefreshCw className="w-4 h-4" />} onClick={load}>
            تحديث
          </Button>
        }
      />

      {filter === 'requested' && openCount > 0 && (
        <Card className="mb-4 border-warning-main/40">
          <div className="flex items-center gap-3">
            <DollarSign className="w-5 h-5 text-primary-500" />
            <p className="text-sm font-bold text-text-primary">
              {openCount} طلب في الانتظار — بإجمالي {formatCurrency(openTotal)}
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

      <div className="space-y-2">
        {loading && requests.length === 0 && (
          <Card><p className="text-sm text-text-tertiary">جاري التحميل...</p></Card>
        )}
        {!loading && requests.length === 0 && (
          <Card>
            <div className="flex items-center gap-3 text-text-tertiary">
              <CheckCircle className="w-5 h-5 text-success-main" />
              <p className="text-sm">لا توجد طلبات في هذا التصنيف.</p>
            </div>
          </Card>
        )}

        {requests.map((r) => {
          const covered = r.user_balance >= r.amount;
          const meta = STATUS_LABELS[r.status] ?? { label: r.status, variant: 'neutral' as const };
          return (
            <Card key={r.id}>
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="flex items-start gap-3 min-w-0">
                  <div className="w-9 h-9 rounded-xl bg-primary-500/10 text-primary-500 flex items-center justify-center shrink-0">
                    <DollarSign className="w-5 h-5" />
                  </div>
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-base font-bold text-text-primary">
                        {formatCurrency(r.amount)}
                      </span>
                      <Badge variant={meta.variant} size="sm">{meta.label}</Badge>
                      <Badge variant="info" size="sm">{METHOD_LABELS[r.method] ?? r.method}</Badge>
                    </div>
                    <p className="text-sm text-text-primary mt-1 truncate">
                      {r.user_name || 'كابتن'}{r.user_phone ? ` • ${r.user_phone}` : ''}
                    </p>
                    <p className="text-[11px] text-text-tertiary mt-0.5 font-mono break-all">
                      {r.account_info}
                    </p>
                    <p className="text-[11px] text-text-tertiary mt-0.5">
                      طُلب {formatDate(r.created_at)} • رصيد الكابتن {formatCurrency(r.user_balance)}
                    </p>

                    {r.status === 'requested' && !covered && (
                      <p className="text-[11px] text-error-main font-bold mt-1 flex items-center gap-1">
                        <AlertTriangle className="w-3.5 h-3.5" />
                        الرصيد الحالي لا يغطي المبلغ — ستُرفض الموافقة من الخادم.
                      </p>
                    )}

                    {r.decision_reason && (
                      <p className="text-[11px] text-text-secondary mt-1">
                        <span className="text-text-tertiary">السبب المسجّل:</span> {r.decision_reason}
                      </p>
                    )}
                  </div>
                </div>

                {r.status === 'requested' && (
                  <div className="flex items-center gap-2">
                    <Button
                      size="xs"
                      variant="success"
                      leftIcon={<CheckCircle className="w-3.5 h-3.5" />}
                      onClick={() => { setTarget(r); setAction('approve'); }}
                    >
                      صرف
                    </Button>
                    <Button
                      size="xs"
                      variant="danger"
                      leftIcon={<Ban className="w-3.5 h-3.5" />}
                      onClick={() => { setTarget(r); setAction('reject'); }}
                    >
                      رفض
                    </Button>
                  </div>
                )}
              </div>
            </Card>
          );
        })}
      </div>

      <ReasonPrompt
        isOpen={action === 'approve'}
        title="تأكيد صرف المستحقات"
        subtitle={
          target
            ? `${formatCurrency(target.amount)} إلى ${target.user_name || target.user_id} — سيُخصم من محفظته الآن.`
            : undefined
        }
        tone="success"
        confirmLabel="تأكيد الصرف"
        presets={['تم التحويل وأُرفق الإيصال', 'تم الصرف نقداً من الفرع', 'تمت مطابقة البيانات والتحويل']}
        onClose={() => { setAction(null); setTarget(null); }}
        onSubmit={submitDecision}
      />

      <ReasonPrompt
        isOpen={action === 'reject'}
        title="رفض طلب السحب"
        subtitle={
          target
            ? `${formatCurrency(target.amount)} — ${target.user_name || target.user_id}. لن يتحرك أي رصيد.`
            : undefined
        }
        tone="danger"
        confirmLabel="تأكيد الرفض"
        presets={['بيانات الحساب غير صحيحة', 'الرصيد غير كافٍ', 'الحساب قيد المراجعة', 'طلب مكرر']}
        onClose={() => { setAction(null); setTarget(null); }}
        onSubmit={submitDecision}
      />

      <p className="mt-6 text-[11px] text-text-tertiary flex items-start gap-1.5">
        <AlertTriangle className="w-3.5 h-3.5 shrink-0 mt-px" />
        المنصة لا تملك واجهة صرف آلي. «صرف» يعني أن التحويل تم خارج النظام وأن هذا السجل يوثّقه.
      </p>
    </div>
  );
}
