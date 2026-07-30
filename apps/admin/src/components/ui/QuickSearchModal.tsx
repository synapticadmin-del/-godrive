import { useState, useEffect } from 'react';
import { api } from '../../lib/api';
import { useAuth } from '../../lib/auth';

interface QuickSearchResult {
  captains: Array<{ id: string; name: string | null; email: string; phone: string | null; vehicle_plate: string | null }>;
  riders: Array<{ id: string; name: string | null; email: string; phone: string | null }>;
  trips: Array<{ id: string; status: string; city: string; estimated_fare: number | null; created_at: string }>;
}

export function QuickSearchModal({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  const { token } = useAuth();
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState<QuickSearchResult | null>(null);

  useEffect(() => {
    if (!query.trim()) {
      setResults(null);
      return;
    }

    const timer = setTimeout(async () => {
      setLoading(true);
      try {
        const res = await api<{ results: QuickSearchResult }>(`/admin/search?q=${encodeURIComponent(query)}`, { token });
        setResults(res.results);
      } catch (e) {
        console.error(e);
      } finally {
        setLoading(false);
      }
    }, 250);

    return () => clearTimeout(timer);
  }, [query, token]);

  // The modal renders an "ESC" affordance but never listened for the key.
  useEffect(() => {
    if (!isOpen) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onClose();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [isOpen, onClose]);

  // Start from a clean slate each time the palette opens, otherwise the previous
  // search's results flash before the new debounce fires.
  useEffect(() => {
    if (!isOpen) {
      setQuery('');
      setResults(null);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 bg-black/55 backdrop-blur-sm flex items-start justify-center pt-20 p-4 animate-fade-in"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-label="بحث سريع"
    >
      <div
        className="bg-surface-primary border border-border-primary rounded-2xl w-full max-w-2xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Search Input Bar */}
        <div className="p-4 border-b border-border-primary flex items-center gap-3 bg-surface-secondary">
          <svg className="w-5 h-5 text-text-tertiary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <input
            type="search"
            autoFocus
            placeholder="ابحث عن كابتن، راكب، رقم الهاتف، أو معرف الرحلة..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="w-full bg-transparent border-none text-text-primary font-bold text-sm focus:outline-none placeholder:text-text-tertiary placeholder:font-normal"
          />
          <button onClick={onClose} className="px-2 py-1 bg-surface-tertiary hover:bg-surface-active text-text-secondary font-bold text-xs rounded-lg transition-colors">
            ESC
          </button>
        </div>

        {/* Results Body */}
        <div className="max-h-96 overflow-y-auto p-4 space-y-4">
          {loading && <p className="text-center text-xs text-text-tertiary py-6">جاري البحث المباشر...</p>}

          {!loading && !query.trim() && (
            <p className="text-center text-xs text-text-tertiary py-8">اكتب اسم الكابتن، البريد الإلكتروني، أو رقم الرحلة للبحث الفوري.</p>
          )}

          {!loading && results && (
            <div className="space-y-4 text-right">
              {/* Captains Section */}
              {results.captains.length > 0 && (
                <div>
                  <h4 className="text-[11px] font-extrabold text-text-tertiary uppercase tracking-wider mb-2">الكباتن ({results.captains.length})</h4>
                  <div className="space-y-1.5">
                    {results.captains.map((c) => (
                      <div key={c.id} className="p-2.5 rounded-xl bg-surface-secondary border border-border-primary hover:bg-info-light/40 hover:border-primary-500/40 transition-all flex items-center justify-between">
                        <div>
                          <p className="font-bold text-xs text-text-primary">{c.name || 'كابتن بدون اسم'}</p>
                          <p className="text-[11px] text-text-tertiary font-mono">{c.phone || c.email}</p>
                        </div>
                        {c.vehicle_plate && (
                          <span className="px-2 py-0.5 rounded bg-warning-light text-warning-dark border border-warning-main/30 font-mono text-[10px] font-bold">
                            {c.vehicle_plate}
                          </span>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Riders Section */}
              {results.riders.length > 0 && (
                <div>
                  <h4 className="text-[11px] font-extrabold text-text-tertiary uppercase tracking-wider mb-2">الركاب ({results.riders.length})</h4>
                  <div className="space-y-1.5">
                    {results.riders.map((r) => (
                      <div key={r.id} className="p-2.5 rounded-xl bg-surface-secondary border border-border-primary hover:bg-info-light/40 transition-all">
                        <p className="font-bold text-xs text-text-primary">{r.name || 'راكب بدون اسم'}</p>
                        <p className="text-[11px] text-text-tertiary font-mono">{r.phone || r.email}</p>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Trips Section */}
              {results.trips.length > 0 && (
                <div>
                  <h4 className="text-[11px] font-extrabold text-text-tertiary uppercase tracking-wider mb-2">الرحلات ({results.trips.length})</h4>
                  <div className="space-y-1.5">
                    {results.trips.map((t) => (
                      <div key={t.id} className="p-2.5 rounded-xl bg-surface-secondary border border-border-primary hover:bg-info-light/40 transition-all flex items-center justify-between">
                        <div>
                          <p className="font-mono font-bold text-xs text-primary-500">#{t.id.slice(0, 12)}</p>
                          <p className="text-[11px] text-text-tertiary">المدينة: {t.city}</p>
                        </div>
                        <span className="px-2 py-0.5 rounded-full bg-surface-tertiary text-text-secondary text-[10px] font-bold">
                          {t.status}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {results.captains.length === 0 && results.riders.length === 0 && results.trips.length === 0 && (
                <p className="text-center text-xs text-text-tertiary py-6">لا توجد نتائج تطابق "{query}"</p>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}