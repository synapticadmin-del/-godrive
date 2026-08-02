import React, { useEffect, useState } from 'react';
import { AlertTriangle, Loader2, Send, X } from 'lucide-react';

/**
 * Reason capture for an operator decision.
 *
 * Every destructive or money-moving action in the SOS and payout queues goes
 * through this. It exists because F-11-08 is what an action with no recorded
 * "why" looks like once someone has to review it: a state change, a timestamp,
 * and nobody able to say what happened.
 *
 * The server is the real guard — `payoutDecisionSchema` and E13's
 * `sosResolveSchema` both reject a short reason with 400, and this component
 * cannot be the only thing enforcing it. What it does is stop the operator
 * discovering that after the fact, and keep the bar identical on both queues.
 *
 * Generalised from `RejectionReasonModal`, which is document-verification
 * specific (its presets are about blurry scans and expired licences) and is
 * left untouched for that flow.
 */

export interface ReasonChoice {
  value: string;
  label: string;
}

export interface ReasonPromptProps {
  isOpen: boolean;
  title: string;
  subtitle?: string;
  /** Quick-fill buttons. Clicking one replaces the textarea contents. */
  presets?: string[];
  /** Renders a required segmented selector above the reason (SOS outcome, event type). */
  choices?: ReasonChoice[];
  choiceLabel?: string;
  defaultChoice?: string;
  confirmLabel: string;
  tone?: 'danger' | 'success' | 'primary';
  /** Mirrors the server's `min()`. 3 everywhere today. */
  minLength?: number;
  onClose: () => void;
  onSubmit: (reason: string, choice?: string) => Promise<void>;
}

const toneClasses: Record<NonNullable<ReasonPromptProps['tone']>, string> = {
  danger: 'bg-error-main hover:bg-error-dark text-white',
  success: 'bg-success-main hover:bg-success-dark text-white',
  primary: 'bg-primary-500 hover:bg-primary-600 text-white',
};

const toneAccent: Record<NonNullable<ReasonPromptProps['tone']>, string> = {
  danger: 'bg-error-main/10 border-error-main/20 text-error-main',
  success: 'bg-success-main/10 border-success-main/20 text-success-main',
  primary: 'bg-primary-500/10 border-primary-500/20 text-primary-500',
};

export const ReasonPrompt: React.FC<ReasonPromptProps> = ({
  isOpen,
  title,
  subtitle,
  presets = [],
  choices,
  choiceLabel,
  defaultChoice,
  confirmLabel,
  tone = 'primary',
  minLength = 3,
  onClose,
  onSubmit,
}) => {
  const [reason, setReason] = useState('');
  const [choice, setChoice] = useState<string | undefined>(defaultChoice ?? choices?.[0]?.value);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Reset on open so a previous decision's text can never be submitted against
  // a different row — the queue reuses one modal instance for every row.
  useEffect(() => {
    if (isOpen) {
      setReason('');
      setChoice(defaultChoice ?? choices?.[0]?.value);
      setError(null);
      setSubmitting(false);
    }
  }, [isOpen, defaultChoice, choices]);

  useEffect(() => {
    if (!isOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !submitting) onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [isOpen, submitting, onClose]);

  if (!isOpen) return null;

  const trimmed = reason.trim();
  const tooShort = trimmed.length < minLength;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    if (tooShort) {
      setError(`السبب مطلوب — ${minLength} أحرف على الأقل`);
      return;
    }
    try {
      setSubmitting(true);
      await onSubmit(trimmed, choice);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'تعذّر تنفيذ الإجراء');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
      onClick={() => !submitting && onClose()}
      dir="rtl"
      role="dialog"
      aria-modal="true"
      aria-label={title}
    >
      <div
        className="relative w-full max-w-lg bg-surface-primary border border-border-primary rounded-2xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-5 border-b border-border-primary bg-surface-secondary/50">
          <div className="flex items-center gap-3">
            <div className={`w-10 h-10 rounded-xl border flex items-center justify-center ${toneAccent[tone]}`}>
              <AlertTriangle className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-base font-bold text-text-primary">{title}</h3>
              {subtitle && <p className="text-xs text-text-tertiary mt-0.5">{subtitle}</p>}
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            className="p-2 text-text-tertiary hover:text-text-primary hover:bg-surface-hover rounded-lg transition-colors disabled:opacity-50"
            aria-label="إغلاق"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {error && (
            <div className="p-3 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main text-xs font-bold">
              {error}
            </div>
          )}

          {choices && choices.length > 0 && (
            <div className="space-y-1.5">
              <label className="block text-xs font-bold text-text-secondary">
                {choiceLabel ?? 'النتيجة'} <span className="text-error-main">*</span>
              </label>
              <div className="flex flex-wrap gap-2">
                {choices.map((opt) => (
                  <button
                    key={opt.value}
                    type="button"
                    onClick={() => setChoice(opt.value)}
                    className={`px-3 py-1.5 rounded-xl border text-xs font-bold transition-all ${
                      choice === opt.value
                        ? 'bg-primary-500/10 border-primary-500 text-primary-500'
                        : 'bg-surface-secondary border-border-primary text-text-secondary hover:border-border-secondary'
                    }`}
                  >
                    {opt.label}
                  </button>
                ))}
              </div>
            </div>
          )}

          {presets.length > 0 && (
            <div className="space-y-1.5">
              <label className="block text-xs font-bold text-text-secondary">أسباب جاهزة</label>
              <div className="flex flex-wrap gap-2">
                {presets.map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => {
                      setReason(p);
                      setError(null);
                    }}
                    className="px-3 py-1.5 rounded-xl border border-border-primary bg-surface-secondary/60 text-xs text-text-primary hover:border-border-secondary transition-all"
                  >
                    {p}
                  </button>
                ))}
              </div>
            </div>
          )}

          <div className="space-y-1.5">
            <label htmlFor="reason-prompt-text" className="block text-xs font-bold text-text-secondary">
              السبب <span className="text-error-main">*</span>
            </label>
            <textarea
              id="reason-prompt-text"
              rows={3}
              value={reason}
              onChange={(e) => {
                setReason(e.target.value);
                setError(null);
              }}
              placeholder="اكتب ما حدث ولماذا اتُّخذ هذا القرار — سيظهر في سجل التدقيق."
              className="w-full p-3 bg-surface-secondary border border-border-primary rounded-xl text-xs text-text-primary focus:outline-none focus:border-primary-500 focus:ring-1 focus:ring-primary-500/30 resize-none transition-all"
              autoFocus
            />
            <p className="text-[11px] text-text-tertiary">
              {trimmed.length}/500 — يُسجَّل باسمك في سجل التدقيق ولا يمكن تعديله لاحقاً.
            </p>
          </div>

          <div className="flex items-center justify-end gap-3 pt-3 border-t border-border-primary">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="px-4 py-2 text-xs font-bold text-text-secondary bg-surface-secondary hover:bg-surface-tertiary border border-border-primary rounded-xl transition-all disabled:opacity-50"
            >
              إلغاء
            </button>
            <button
              type="submit"
              disabled={submitting || tooShort}
              className={`flex items-center gap-1.5 px-5 py-2 text-xs font-bold rounded-xl shadow-xs transition-all disabled:opacity-50 disabled:cursor-not-allowed ${toneClasses[tone]}`}
            >
              {submitting ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  جاري التنفيذ...
                </>
              ) : (
                <>
                  <Send className="w-4 h-4" />
                  {confirmLabel}
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default ReasonPrompt;
