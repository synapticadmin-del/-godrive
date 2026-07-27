import React, { useState } from 'react';
import { X, AlertTriangle, ImageOff, CalendarX, FileX, Edit3, Send, Loader2, CarFront, UserX } from 'lucide-react';

interface RejectionReasonModalProps {
  isOpen: boolean;
  docTitle: string;
  captainName?: string;
  onClose: () => void;
  onSubmit: (reason: string) => Promise<void>;
}

const PRESETS = [
  {
    id: 'blurry',
    label: 'الصورة غير واضحة',
    description: 'جودة الصورة منخفضة أو النص غير مقروء',
    icon: ImageOff,
  },
  {
    id: 'expired',
    label: 'بطاقة منتهية الصلاحية',
    description: 'تاريخ انتهاء البطاقة أو المستند سابق لليوم',
    icon: CalendarX,
  },
  {
    id: 'license_invalid',
    label: 'رخصة القيادة مفقودة أو منتهية',
    description: 'الرخصة غير مرفقة أو منتهية الصلاحية أو غير سارية',
    icon: CarFront,
  },
  {
    id: 'mismatch',
    label: 'البيانات غير متطابقة',
    description: 'البيانات الموجودة في المستند لا تطابق بيانات الكابتن',
    icon: FileX,
  },
  {
    id: 'name_mismatch',
    label: 'اسم الكابتن غير مطابق للبطاقة',
    description: 'الاسم المسجل في الحساب لا يتطابق مع الاسم في المستند الرسمي',
    icon: UserX,
  },
  {
    id: 'custom',
    label: 'إدخال سبب آخر',
    description: 'كتابة سبب مخصص لرفض هذا المستند',
    icon: Edit3,
  },
];

export const RejectionReasonModal: React.FC<RejectionReasonModalProps> = ({
  isOpen,
  docTitle,
  captainName,
  onClose,
  onSubmit,
}) => {
  const [selectedPreset, setSelectedPreset] = useState<string>('blurry');
  const [customReason, setCustomReason] = useState<string>('');
  const [submitting, setSubmitting] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    let finalReason = '';
    if (selectedPreset === 'custom') {
      if (!customReason.trim()) {
        setError('يرجى كتابة سبب الرفض المخصص');
        return;
      }
      finalReason = customReason.trim();
    } else {
      const presetObj = PRESETS.find((p) => p.id === selectedPreset);
      finalReason = presetObj ? presetObj.label : 'تم رفض المستند';
    }

    try {
      setSubmitting(true);
      await onSubmit(finalReason);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'حدث خطأ أثناء حفظ سبب الرفض');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-fade-in"
      onClick={onClose}
      dir="rtl"
    >
      <div
        className="relative w-full max-w-lg bg-surface-primary border border-border-primary rounded-2xl shadow-2xl overflow-hidden transition-all transform scale-100"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Modal Header */}
        <div className="flex items-center justify-between p-5 border-b border-border-primary bg-surface-secondary/50">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-error-main/10 border border-error-main/20 flex items-center justify-center text-error-main">
              <AlertTriangle className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-base font-bold text-text-primary">سبب رفض المستند</h3>
              <p className="text-xs text-text-tertiary">
                {docTitle} {captainName ? `• ${captainName}` : ''}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 text-text-tertiary hover:text-text-primary hover:bg-surface-hover rounded-lg transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Modal Form */}
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {error && (
            <div className="p-3 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main text-xs font-bold">
              {error}
            </div>
          )}

          <div className="space-y-2">
            <label className="block text-xs font-bold text-text-secondary">
              اختر أحد الأسباب الجاهزة أو أدخل سبباً مخصصاً:
            </label>

            <div className="grid grid-cols-1 gap-2.5">
              {PRESETS.map((preset) => {
                const Icon = preset.icon;
                const isSelected = selectedPreset === preset.id;
                return (
                  <button
                    key={preset.id}
                    type="button"
                    onClick={() => {
                      setSelectedPreset(preset.id);
                      setError(null);
                    }}
                    className={`flex items-start gap-3 p-3 rounded-xl border text-right transition-all ${
                      isSelected
                        ? 'bg-error-main/10 border-error-main text-error-main shadow-xs'
                        : 'bg-surface-secondary/60 border-border-primary hover:border-border-secondary text-text-primary'
                    }`}
                  >
                    <div
                      className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 mt-0.5 ${
                        isSelected ? 'bg-error-main text-white' : 'bg-surface-tertiary text-text-tertiary'
                      }`}
                    >
                      <Icon className="w-4 h-4" />
                    </div>
                    <div className="flex-1">
                      <p className="text-xs font-bold">{preset.label}</p>
                      <p
                        className={`text-[11px] mt-0.5 ${
                          isSelected ? 'text-error-main/80' : 'text-text-tertiary'
                        }`}
                      >
                        {preset.description}
                      </p>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Custom Reason Text Input */}
          {selectedPreset === 'custom' && (
            <div className="space-y-1.5 pt-1 animate-fade-in">
              <label className="block text-xs font-bold text-text-secondary">
                سبب الرفض المخصص <span className="text-error-main">*</span>
              </label>
              <textarea
                rows={3}
                value={customReason}
                onChange={(e) => setCustomReason(e.target.value)}
                placeholder="اكتب سبب الرفض التفصيلي ليظهر للكابتن..."
                className="w-full p-3 bg-surface-secondary border border-border-primary rounded-xl text-xs text-text-primary focus:outline-none focus:border-error-main focus:ring-1 focus:ring-error-main/30 resize-none transition-all"
                autoFocus
              />
            </div>
          )}

          {/* Modal Actions */}
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
              disabled={submitting}
              className="flex items-center gap-1.5 px-5 py-2 text-xs font-bold text-white bg-error-main hover:bg-error-dark rounded-xl shadow-xs transition-all disabled:opacity-50"
            >
              {submitting ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  جاري الحفظ...
                </>
              ) : (
                <>
                  <Send className="w-4 h-4" />
                  تاكيد الرفض
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
