import React, { useState, useEffect, useRef } from 'react';

export interface ToastType {
  id: string;
  type: 'success' | 'error' | 'warning' | 'info';
  message: string;
  duration?: number;
}

const ToastContext = React.createContext<{
  toasts: ToastType[];
  addToast: (toast: Omit<ToastType, 'id'>) => string;
  removeToast: (id: string) => void;
} | null>(null);

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<ToastType[]>([]);
  // A monotonic counter instead of Math.random(): two toasts raised in the same
  // tick (e.g. a bulk action reporting several failures) could previously draw
  // the same 7-char id, and React would then treat them as one list item and
  // drop all but the first. useId is not usable here because the id has to be
  // unique per toast, not per component instance.
  const nextId = useRef(0);

  const addToast = (toast: Omit<ToastType, 'id'>): string => {
    const id = `toast-${nextId.current++}`;
    const newToast: ToastType = { ...toast, id };
    setToasts((prev) => [...prev, newToast]);

    if (toast.duration !== 0) {
      setTimeout(() => removeToast(id), toast.duration || 4000);
    }

    return id;
  };

  const removeToast = (id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  };

  return (
    <ToastContext.Provider value={{ toasts, addToast, removeToast }}>
      {children}
      <ToastContainer toasts={toasts} onRemove={removeToast} />
    </ToastContext.Provider>
  );
}

export function useToast() {
  const context = React.useContext(ToastContext);
  if (!context) {
    throw new Error('useToast must be used within a ToastProvider');
  }
  return context;
}

function ToastContainer({ toasts, onRemove }: { toasts: ToastType[]; onRemove: (id: string) => void }) {
  if (!toasts.length) return null;

  return (
    <div
      className="fixed bottom-4 left-4 z-[1800] flex flex-col gap-2 pointer-events-none"
      role="region"
      aria-label="الإشعارات"
      aria-live="polite"
    >
      {toasts.map((toast) => (
        <ToastItem key={toast.id} toast={toast} onRemove={onRemove} />
      ))}
    </div>
  );
}

function ToastItem({ toast, onRemove }: { toast: ToastType; onRemove: (id: string) => void }) {
  const icons = {
    success: (
      <svg className="w-5 h-5 text-success-main" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
      </svg>
    ),
    error: (
      <svg className="w-5 h-5 text-error-main" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
      </svg>
    ),
    warning: (
      <svg className="w-5 h-5 text-warning-main" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.36 0L3.34 16.5c-.77.77-.895 1.897-.34 2.766z" />
      </svg>
    ),
    info: (
      <svg className="w-5 h-5 text-primary-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    ),
  };

  const bgColors = {
    success: 'bg-success-light',
    error: 'bg-error-light',
    warning: 'bg-warning-light',
    info: 'bg-info-light',
  };

  const textColors = {
    success: 'text-success-dark dark:text-success-main',
    error: 'text-error-dark dark:text-error-main',
    warning: 'text-warning-dark dark:text-warning-main',
    info: 'text-info-dark dark:text-info-main',
  };

  const borderColors = {
    success: 'border-success-main',
    error: 'border-error-main',
    warning: 'border-warning-main',
    info: 'border-primary-500',
  };

  const [visible, setVisible] = useState(true);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const timer = setTimeout(() => setVisible(false), toast.duration || 4000);
    return () => clearTimeout(timer);
  }, [toast.duration]);

  useEffect(() => {
    if (!visible) {
      const timer = setTimeout(() => {
        onRemove(toast.id);
      }, 300);
      return () => clearTimeout(timer);
    }
  }, [visible]);

  if (!visible) return null;

  return (
    <div
      ref={ref}
      className={`
        flex items-center gap-3 p-4 rounded-xl shadow-xl
        ${bgColors[toast.type]} ${textColors[toast.type]}
        border-l-4 ${borderColors[toast.type]}
        shadow-lg pointer-events-auto
      `}
      onClick={() => setVisible(false)}
    >
      <span className="flex-shrink-0">{icons[toast.type]}</span>
      <p className="flex-1 text-sm font-medium">{toast.message}</p>
      <button
        onClick={(e) => { e.stopPropagation(); onRemove(toast.id); }}
        className="p-1 rounded-lg hover:bg-black/10 dark:hover:bg-white/10 transition-colors"
        aria-label="إغلاق"
      >
        <svg className="w-5 h-5 opacity-60 hover:opacity-100" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
}