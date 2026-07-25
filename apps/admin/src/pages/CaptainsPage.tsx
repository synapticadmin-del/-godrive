import { useEffect, useState, useRef } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { StatusBadge } from '../components/ui/Badge';
import { DataTable, type Column } from '../components/ui/DataTable';
import { Search, Check, Ban, Loader2, Star, MapPin, Navigation, AlertTriangle } from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';
import { useTheme } from '../design/ThemeContext';

/**
 * First character of a display name, safe for non-ASCII.
 *
 * `str[0]` splits a surrogate pair, so an emoji or an astral-plane character
 * yields half a code point and renders as a replacement glyph. Array.from
 * iterates by code point instead.
 */
function initialOf(name: string | null): string {
  const trimmed = (name ?? '').trim();
  if (!trimmed) return 'ك'; // "kaptin" — matches the Arabic fallback label
  return Array.from(trimmed)[0].toUpperCase();
}

interface Captain {
  user_id: string;
  email: string;
  name: string | null;
  phone: string | null;
  vehicle_make: string | null;
  vehicle_model: string | null;
  vehicle_plate: string | null;
  approval_status: string;
  is_online: number;
  lat?: number | null;
  lng?: number | null;
  last_lat?: number | null;
  last_lng?: number | null;
  rating_avg: number;
  rating_count: number;
}

declare global {
  interface Window {
    L?: any;
  }
}

export default function CaptainsPage() {
  const { token } = useAuth();
  const { resolved } = useTheme();
  const [captains, setCaptains] = useState<Captain[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const [processingId, setProcessingId] = useState<string | null>(null);
  const [selectedCaptainId, setSelectedCaptainId] = useState<string | null>(null);
  const [mapLoaded, setMapLoaded] = useState(false);
  const [mapError, setMapError] = useState<string | null>(null);

  const mapRef = useRef<HTMLDivElement>(null);
  const mapObj = useRef<any>(null);
  const tileLayerRef = useRef<any>(null);
  const markersRef = useRef<{ [key: string]: any }>({});
  const layerRef = useRef<any>(null);

  const getCaptainLat = (c: Captain): number | null => c.last_lat ?? c.lat ?? null;
  const getCaptainLng = (c: Captain): number | null => c.last_lng ?? c.lng ?? null;

  const fetchCaptains = async (showLoading = false) => {
    try {
      if (showLoading) setLoading(true);
      const res = await api<{ captains: Captain[] }>(`/admin/captains${filter ? `?status=${filter}` : ''}`, { token });
      const data = res.captains || [];
      setCaptains(data);
      setError(null);
      updateMapMarkers(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'فشل التحميل');
    } finally {
      setLoading(false);
    }
  };

  const loadLeaflet = async () => {
    if (window.L) return Promise.resolve();
    return new Promise<void>((resolve, reject) => {
      const css = document.createElement('link');
      css.rel = 'stylesheet';
      css.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
      document.head.appendChild(css);

      const s = document.createElement('script');
      s.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
      s.onload = () => resolve();
      s.onerror = reject;
      document.body.appendChild(s);
    });
  };

  const initMap = () => {
    if (!mapRef.current || !window.L || mapObj.current) return;
    const L = window.L;

    mapObj.current = L.map(mapRef.current).setView([30.0444, 31.2357], 12);
    const tileUrl = resolved === 'dark'
      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
      : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
    tileLayerRef.current = L.tileLayer(tileUrl, {
      attribution: '&copy; Synaptic Go',
      maxZoom: 19,
      subdomains: ['a', 'b', 'c'],
    }).addTo(mapObj.current);

    layerRef.current = L.layerGroup().addTo(mapObj.current);
    setMapLoaded(true);
  };

  // Dynamically switch map tiles whenever theme changes (light/dark)
  useEffect(() => {
    if (tileLayerRef.current && window.L) {
      const tileUrl = resolved === 'dark'
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
      tileLayerRef.current.setUrl(tileUrl);
    }
  }, [resolved]);

  const updateMapMarkers = (captainsList: Captain[]) => {
    if (!mapObj.current || !layerRef.current || !window.L) return;
    const L = window.L;
    layerRef.current.clearLayers();
    markersRef.current = {};

    const bounds: any[] = [];
    const onlineCaptains = captainsList.filter((c) => {
      const lat = getCaptainLat(c);
      const lng = getCaptainLng(c);
      return c.is_online === 1 && lat != null && lng != null;
    });

    onlineCaptains.forEach((c) => {
      const lat = getCaptainLat(c)!;
      const lng = getCaptainLng(c)!;
      bounds.push([lat, lng]);

      const customIcon = L.divIcon({
        className: 'custom-captain-pin',
        html: `
          <div style="position: relative; width: 36px; height: 36px; display: flex; align-items: center; justify-content: center; background: #22c55e; border: 3px solid #ffffff; border-radius: 50%; box-shadow: 0 0 15px rgba(34, 197, 94, 0.8);">
            <span style="color: white; font-weight: bold; font-size: 16px;">🚗</span>
          </div>
        `,
        iconSize: [36, 36],
        iconAnchor: [18, 18],
        popupAnchor: [0, -18],
      });

      const safeName = (c.name || 'كابتن').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      const safePhone = (c.phone || c.email || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      const safeMake = (c.vehicle_make || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      const safePlate = (c.vehicle_plate || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');

      const popupContent = `
        <div style="text-align: right; direction: rtl; font-family: sans-serif; padding: 4px;">
          <h4 style="margin: 0; font-size: 14px; font-weight: bold; color: #0f172a;">${safeName}</h4>
          <p style="margin: 4px 0 0 0; font-size: 12px; color: #64748b;">📱 ${safePhone}</p>
          ${c.vehicle_plate ? `<p style="margin: 4px 0 0 0; font-size: 12px; font-weight: bold; color: #0ea5e9;">🚘 ${safeMake} (${safePlate})</p>` : ''}
          <div style="margin-top: 6px; padding: 2px 6px; background: #dcfce7; color: #166534; border-radius: 4px; font-size: 11px; display: inline-block; font-weight: bold;">🟢 متصل الآن</div>
        </div>
      `;

      const marker = L.marker([lat, lng], { icon: customIcon }).bindPopup(popupContent);
      layerRef.current.addLayer(marker);
      markersRef.current[c.user_id] = marker;
    });

    if (bounds.length > 0 && !selectedCaptainId) {
      mapObj.current.fitBounds(bounds, { padding: [40, 40], maxZoom: 14 });
    }
  };

  // Map lifecycle — mount ONCE.
  //
  // This was previously fused with the data effect and keyed on [token, filter],
  // so every click on a status pill ran the cleanup: the Leaflet instance was
  // destroyed and rebuilt from scratch. The map flickered and the admin's zoom
  // and pan were discarded on each filter change. Map creation does not depend
  // on `filter` at all, so it is now its own effect with an empty dependency
  // list and the teardown runs only on unmount.
  useEffect(() => {
    let cancelled = false;
    loadLeaflet()
      .then(() => {
        if (cancelled) return;
        initMap();
      })
      .catch(() => {
        // Leaflet is loaded from a CDN. If it cannot be fetched, say so instead
        // of leaving a permanently blank rectangle with a spinner over it.
        if (!cancelled) setMapError('تعذّر تحميل الخريطة. تحقق من الاتصال بالإنترنت.');
      });

    return () => {
      cancelled = true;
      if (mapObj.current) {
        mapObj.current.remove();
        mapObj.current = null;
      }
    };
  }, []);

  // Data lifecycle — refetch when the token or the server-side filter changes,
  // and poll on an interval. Separate from the map so filtering never disturbs it.
  useEffect(() => {
    fetchCaptains(true);
    const interval = setInterval(() => fetchCaptains(false), 10000);
    return () => clearInterval(interval);
  }, [token, filter]);

  // The map and the data now load independently, so whichever finishes second
  // has to reconcile them. updateMapMarkers() is a no-op until the map exists,
  // so a fetch that lands first would otherwise leave the map empty until the
  // next 10s poll. Redrawing when either side changes closes that window.
  useEffect(() => {
    if (mapLoaded) updateMapMarkers(captains);
  }, [mapLoaded, captains]);

  const handleFocusCaptain = (captain: Captain) => {
    setSelectedCaptainId(captain.user_id);
    if (!mapObj.current) return;

    const lat = getCaptainLat(captain);
    const lng = getCaptainLng(captain);

    if (lat != null && lng != null) {
      mapRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });

      mapObj.current.flyTo([lat, lng], 16, {
        animate: true,
        duration: 1.5,
      });

      const marker = markersRef.current[captain.user_id];
      if (marker) {
        setTimeout(() => marker.openPopup(), 1000);
      }
    } else {
      alert(`الكابتن ${captain.name || ''} لم يقم بتحديث موقعه على الجي بي إس بعد.`);
    }
  };

  const handleApprove = async (id: string) => {
    setProcessingId(id);
    try {
      await api(`/admin/captains/${id}/approve`, { method: 'POST', token });
      fetchCaptains(false);
    } catch {
      alert('فشل اعتماد الكابتن');
    } finally {
      setProcessingId(null);
    }
  };

  const handleSuspend = async (id: string) => {
    setProcessingId(id);
    try {
      await api(`/admin/captains/${id}/suspend`, { method: 'POST', token });
      fetchCaptains(false);
    } catch {
      alert('فشل إيقاف الكابتن');
    } finally {
      setProcessingId(null);
    }
  };

  const filteredCaptains = captains.filter((c) => {
    if (!searchTerm) return true;
    const term = searchTerm.toLowerCase();
    return (
      c.name?.toLowerCase().includes(term) ||
      c.email?.toLowerCase().includes(term) ||
      c.phone?.includes(term) ||
      c.vehicle_plate?.toLowerCase().includes(term)
    );
  });

  const onlineCaptainsCount = captains.filter((c) => {
    const lat = getCaptainLat(c);
    const lng = getCaptainLng(c);
    return c.is_online === 1 && lat != null && lng != null;
  }).length;

  const captainColumns: Column<Captain>[] = [
    {
      key: 'name',
      header: 'الكابتن',
      sortable: true,
      accessor: (c) => (
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-lg bg-primary-500/10 text-primary-500 font-bold flex items-center justify-center text-sm shrink-0">
            {initialOf(c.name)}
          </div>
          <div className="min-w-0">
            <p className="font-medium text-text-primary text-sm truncate">{c.name || 'كابتن'}</p>
            <p className="text-xs text-text-tertiary font-mono">{c.user_id.slice(0, 8)}</p>
          </div>
        </div>
      ),
    },
    {
      key: 'phone',
      header: 'التواصل',
      sortable: true,
      accessor: (c) => (
        <div className="min-w-0">
          <p className="text-sm text-text-primary font-mono" dir="ltr">{c.phone || '—'}</p>
          <p className="text-xs text-text-tertiary truncate" dir="ltr">{c.email}</p>
        </div>
      ),
    },
    {
      key: 'vehicle_make',
      header: 'السيارة',
      sortable: true,
      accessor: (c) => (
        <div>
          <p className="text-sm text-text-primary">
            {c.vehicle_make ? `${c.vehicle_make} ${c.vehicle_model || ''}`.trim() : '—'}
          </p>
          {c.vehicle_plate && (
            <span className="inline-block mt-1 px-2 py-0.5 bg-warning-main/10 text-warning-main font-mono text-xs font-bold rounded">
              {c.vehicle_plate}
            </span>
          )}
        </div>
      ),
    },
    {
      key: 'rating_avg',
      header: 'التقييم',
      sortable: true,
      accessor: (c) => {
        // A captain with no ratings yet is NOT a five-star captain.
        // The previous `c.rating_avg ? ... : '5.0'` printed a fabricated 5.0
        // both for unrated captains AND for a genuine 0.0 rating, because 0 is
        // falsy — so the worst-rated captain on the platform displayed as
        // perfect. Distinguish "no ratings" from a real score.
        const hasRatings = (c.rating_count ?? 0) > 0 && c.rating_avg != null;
        if (!hasRatings) {
          return <span className="text-xs text-text-tertiary">لا تقييمات بعد</span>;
        }
        return (
          <div className="flex items-center gap-1">
            <Star className="w-4 h-4 fill-warning-main text-warning-main" />
            <span className="text-sm font-bold text-text-primary">{c.rating_avg.toFixed(1)}</span>
            <span className="text-xs text-text-tertiary">({c.rating_count})</span>
          </div>
        );
      },
    },
    {
      key: 'approval_status',
      header: 'الحالة / الموقع',
      sortable: true,
      accessor: (c) => (
        <div className="flex items-center gap-2 flex-wrap">
          <StatusBadge status={c.approval_status} />
          {/* StatusBadge already ships online/offline variants with the right
              Arabic labels and colours; this page was hand-rolling its own,
              and used "مغلق" (closed) where the design system says
              "غير متصل" (offline). */}
          <StatusBadge status={c.is_online ? 'online' : 'offline'} />
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="إدارة وتتبع الكباتن"
        subtitle="خريطة مباشرة ومتابعة حسابات الكباتن والاعتماد والإيقاف"
        actions={
          <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
            <div className="relative">
              <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-tertiary" />
              <input
                type="search"
                placeholder="بحث عن كابتن..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full sm:w-56 pl-9 pr-3 py-2 bg-surface-secondary border border-border-primary rounded-lg text-sm text-text-primary placeholder:text-text-tertiary focus:border-primary-500 focus:outline-none"
              />
            </div>
            <div className="flex bg-surface-secondary p-1 rounded-lg border border-border-primary">
              {/* 'rejected' was missing, so captains in that state could not be
                  filtered to from this screen even though the API accepts the
                  value and StatusBadge renders it. */}
              {([
                ['', 'الكل'],
                ['approved', 'معتمد'],
                ['pending', 'بانتظار'],
                ['rejected', 'مرفوض'],
                ['suspended', 'موقوف'],
              ] as const).map(([st, label]) => (
                <button
                  key={st}
                  onClick={() => setFilter(st)}
                  className={`px-3 py-1.5 text-xs font-medium rounded-md transition-all ${
                    filter === st ? 'bg-primary-500 text-white' : 'text-text-secondary hover:text-text-primary'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>
        }
      />

      {error && <div className="p-4 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main">{error}</div>}

      <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden shadow-lg relative">
        <div className="p-4 border-b border-border-primary/50 flex items-center justify-between bg-surface-secondary/40">
          <div className="flex items-center gap-2">
            <MapPin className="w-5 h-5 text-primary-500" />
            <h3 className="font-bold text-text-primary text-sm">خريطة مواقع الكباتن الحية</h3>
          </div>
          <span className="px-3 py-1 bg-success-main/10 border border-success-main/30 text-success-main text-xs font-bold rounded-full flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-success-main animate-pulse" />
            {onlineCaptainsCount} كابتن متصل على الخريطة
          </span>
        </div>
        <div className="relative w-full h-[360px]">
          {/* Three distinct states, previously collapsed into one spinner that
              could spin forever if the Leaflet CDN was unreachable. */}
          {mapError ? (
            <div className="absolute inset-0 z-10 bg-surface-primary flex flex-col items-center justify-center gap-2 px-6 text-center">
              <AlertTriangle className="w-7 h-7 text-warning-main" />
              <p className="text-sm text-text-secondary">{mapError}</p>
              <p className="text-xs text-text-tertiary">
                بيانات الكباتن في الجدول أدناه لا تزال متاحة.
              </p>
            </div>
          ) : (
            !mapLoaded && (
              <div className="absolute inset-0 z-10 bg-surface-primary/80 flex items-center justify-center">
                <Loader2 className="w-8 h-8 text-primary-500 animate-spin" />
              </div>
            )
          )}
          <div ref={mapRef} className="w-full h-full" />
        </div>
      </div>

      {/* Captains table.
          Now backed by the shared DataTable, which supplies sorting, paging,
          a page-size selector, skeleton loading and an empty state. This page
          previously hand-rolled a raw <table> that rendered EVERY row with no
          pagination at all. */}
      <DataTable<Captain>
        data={filteredCaptains}
        keyAccessor={(c) => c.user_id}
        loading={loading && captains.length === 0}
        emptyMessage={
          searchTerm || filter
            ? 'لا يوجد كباتن مطابقون لهذا البحث'
            : 'لا يوجد كباتن مسجلون بعد'
        }
        defaultSortKey="approval_status"
        pageSize={25}
        onRowClick={handleFocusCaptain}
        columns={captainColumns}
        rowActions={[
          {
            label: 'تحديد موقعه على الخريطة',
            icon: <Navigation className="w-4 h-4" />,
            onClick: handleFocusCaptain,
          },
          {
            label: 'اعتماد الكابتن',
            icon: <Check className="w-4 h-4" />,
            onClick: (c) => handleApprove(c.user_id),
            show: (c) => c.approval_status === 'pending',
            disabled: (c) => processingId === c.user_id,
          },
          {
            label: 'إيقاف الكابتن',
            icon: <Ban className="w-4 h-4" />,
            variant: 'danger',
            onClick: (c) => handleSuspend(c.user_id),
            show: (c) => c.approval_status === 'approved',
            disabled: (c) => processingId === c.user_id,
          },
        ]}
      />
    </div>
  );
}