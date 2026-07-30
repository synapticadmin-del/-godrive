import React from 'react';
import { AlertTriangle, RefreshCw, Home } from 'lucide-react';

interface Props {
  children: React.ReactNode;
  /** Remounts the boundary's subtree when this value changes — pass the current
   *  route so navigating away from a crashed page clears the error. */
  resetKey?: string;
}

interface State {
  error: Error | null;
}

/**
 * Catches render-time exceptions in the dashboard.
 *
 * Without a boundary, any thrown error in a page component unmounts the whole
 * React tree and the admin is left staring at a blank white screen with no
 * indication of what happened and no way back other than a manual reload. That
 * is the worst possible failure mode for an operations tool that is used while
 * trips are live.
 *
 * Error boundaries only catch errors thrown during render, in lifecycle methods
 * and in constructors. They deliberately do NOT catch errors inside event
 * handlers or rejected promises — those are already handled per-page by the
 * `error` state each page keeps for failed API calls.
 */
export class ErrorBoundary extends React.Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    // No error-reporting service is wired up yet, so the console is the only
    // place this detail survives. Keep the component stack: it is the fastest
    // way to identify which page threw.
    console.error('[ErrorBoundary] uncaught render error', error, info.componentStack);
  }

  componentDidUpdate(prevProps: Props) {
    // Navigating to a different route should give the admin a working screen
    // again rather than pinning them to the error until a full reload.
    if (this.state.error && prevProps.resetKey !== this.props.resetKey) {
      this.setState({ error: null });
    }
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;

    return (
      <div
        dir="rtl"
        className="min-h-[60vh] flex items-center justify-center p-6"
        role="alert"
        aria-live="assertive"
      >
        <div className="bg-surface-primary border border-border-primary rounded-2xl shadow-lg max-w-lg w-full p-8 text-center">
          <div className="w-14 h-14 rounded-2xl bg-error-main/10 flex items-center justify-center mx-auto mb-5">
            <AlertTriangle className="w-7 h-7 text-error-main" />
          </div>

          <h1 className="text-xl font-extrabold text-text-primary mb-2">حدث خطأ غير متوقع</h1>
          <p className="text-sm text-text-secondary leading-relaxed mb-6">
            الصفحة توقفت عن العمل. البيانات لم تتأثر — يمكنك إعادة المحاولة أو الرجوع
            للوحة التحكم.
          </p>

          {/* The message is the one piece of detail worth showing an operator;
              it is what they will quote when reporting the problem. */}
          <div className="bg-surface-secondary border border-border-primary rounded-xl p-3 mb-6 text-right">
            <p className="text-[11px] font-bold text-text-tertiary uppercase tracking-wider mb-1">
              تفاصيل الخطأ
            </p>
            <p className="text-xs text-error-main font-mono break-words leading-relaxed">
              {error.message || error.name || 'Unknown error'}
            </p>
          </div>

          <div className="flex items-center justify-center gap-3">
            <button
              onClick={() => this.setState({ error: null })}
              className="btn-primary px-5 py-2.5 font-bold text-sm gap-2"
            >
              <RefreshCw className="w-4 h-4" />
              إعادة المحاولة
            </button>
            {/* A hard navigation, not a router push: if the crash came from a
                corrupted router or context state, re-rendering in place would
                just throw again. */}
            <button
              onClick={() => {
                window.location.href = '/';
              }}
              className="btn-secondary px-5 py-2.5 font-bold text-sm gap-2"
            >
              <Home className="w-4 h-4" />
              لوحة التحكم
            </button>
          </div>
        </div>
      </div>
    );
  }
}

export default ErrorBoundary;
