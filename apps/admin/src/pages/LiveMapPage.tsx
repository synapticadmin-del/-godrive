import { useEffect, useState, useRef } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { MapPin, Loader2, RefreshCw, Car, Users, AlertTriangle } from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';
import { useTheme } from '../design/ThemeContext';
import { usePolling } from '../lib/usePolling';

interface LiveTrip {
  id: string; status: string; city: string; rider_id: string; captain_id: string | null;
  pickup_lat: number; pickup_lng: number; dropoff_lat: number; dropoff_lng: number;
  captain_lat: number | null; captain_lng: number | null; estimated_fare: number | null; created_at: string;
}

interface OnlineCaptain {
  id: string; name: string; email: string; phone: string | null;
  is_online: number; last_lat: number; last_lng: number;
  vehicle_make: string | null; vehicle_model: string | null; vehicle_plate: string | null;
  rating_avg: number; approval_status: string; last_seen_at: string | null;
}

declare global { interface Window { L?: any } }

export default function LiveMapPage() {
  const { token } = useAuth();
  const { resolved } = useTheme();
  const [trips, setTrips] = useState<LiveTrip[]>([]);
  const [captains, setCaptains] = useState<OnlineCaptain[]>([]);
  const [loading, setLoading] = useState(true);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [view, setView] = useState<'all' | 'trips' | 'captains'>('all');
  const mapRef = useRef<HTMLDivElement>(null);
  const mapObj = useRef<any>(null);
  const tileLayerRef = useRef<any>(null);
  const layerRef = useRef<any>(null);

  const fetchAll = async () => {
    try {
      const [tripsRes, capsRes] = await Promise.all([
        api<{ trips: LiveTrip[] }>('/admin/live-trips', { token }),
        api<{ captains: OnlineCaptain[] }>('/admin/online-captains', { token }),
      ]);
      setTrips(tripsRes.trips || []);
      setCaptains(capsRes.captains || []);
      updateMap(tripsRes.trips || [], capsRes.captains || []);
      setFetchError(null);
    } catch (e) {
      // Previously swallowed (`/* ignore */`), so a broken API left the admin
      // watching a frozen map with no idea it had stopped updating. Surface a
      // lightweight, dismissible indicator; the last good data stays on screen.
      setFetchError(e instanceof Error ? e.message : 'فشل تحديث البيانات الحية');
    }
    finally { setLoading(false); }
  };

  const loadLeaflet = async () => {
    if (window.L) return Promise.resolve();
    return new Promise<void>((resolve, reject) => {
      const css = document.createElement('link'); css.rel = 'stylesheet'; css.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'; document.head.appendChild(css);
      const s = document.createElement('script'); s.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'; s.onload = () => resolve(); s.onerror = reject; document.body.appendChild(s);
    });
  };

  const initMap = async () => {
    if (!mapRef.current || !window.L || mapObj.current) return;
    const L = window.L;
    mapObj.current = L.map(mapRef.current).setView([30.0444, 31.2357], 12);
    // Theme-aware tiles: dark in dark mode, light otherwise
    const tileUrl = resolved === 'dark'
      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
      : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
    tileLayerRef.current = L.tileLayer(tileUrl, { attribution: '&copy; OpenStreetMap & CARTO', maxZoom: 19, subdomains: 'abcd' }).addTo(mapObj.current);
    layerRef.current = L.layerGroup().addTo(mapObj.current);
  };

  useEffect(() => {
    if (tileLayerRef.current && window.L) {
      const tileUrl = resolved === 'dark'
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
      tileLayerRef.current.setUrl(tileUrl);
    }
  }, [resolved]);

  const updateMap = (tripsData: LiveTrip[], captainsData: OnlineCaptain[]) => {
    if (!mapObj.current || !layerRef.current || !window.L) return;
    const L = window.L;
    layerRef.current.clearLayers();
    const bounds: any[] = [];

    // Show online captains as green car markers
    if (view === 'all' || view === 'captains') {
      for (const cap of captainsData) {
        if (cap.last_lat == null || cap.last_lng == null) continue;
        const safeName = (cap.name || 'كابتن').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const safeMake = (cap.vehicle_make ?? '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const safeModel = (cap.vehicle_model ?? '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const safePlate = (cap.vehicle_plate ?? '—').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const marker = L.circleMarker([cap.last_lat, cap.last_lng], {
          radius: 9, color: '#80b445', fillColor: '#80b445', fillOpacity: 0.9, weight: 2,
        }).bindPopup(
          `<b>🚗 ${safeName}</b><br/>${safeMake} ${safeModel}<br/>` +
          `لوحة: ${safePlate}<br/>تقييم: ⭐${cap.rating_avg ?? '—'}<br/>` +
          `آخر ظهور: ${cap.last_seen_at ? new Date(cap.last_seen_at).toLocaleTimeString('ar-EG') : '—'}`
        );
        layerRef.current.addLayer(marker);
        bounds.push([cap.last_lat, cap.last_lng]);
      }
    }

    // Show active trips
    if (view === 'all' || view === 'trips') {
      for (const t of tripsData) {
        const pickup = L.circleMarker([t.pickup_lat, t.pickup_lng], {
          radius: 7, color: '#80b445', fillColor: '#80b445', fillOpacity: 0.8,
        }).bindPopup(`<b>انطلاق</b><br/>${t.status}<br/>${t.id.slice(0, 12)}`);
        layerRef.current.addLayer(pickup); bounds.push([t.pickup_lat, t.pickup_lng]);
        const drop = L.circleMarker([t.dropoff_lat, t.dropoff_lng], {
          radius: 7, color: '#f59e0b', fillColor: '#f59e0b', fillOpacity: 0.8,
        }).bindPopup(`<b>وصول</b><br/>${t.id.slice(0, 12)}`);
        layerRef.current.addLayer(drop); bounds.push([t.dropoff_lat, t.dropoff_lng]);
        if (t.captain_lat != null && t.captain_lng != null) {
          const cap = L.circleMarker([t.captain_lat, t.captain_lng], {
            radius: 8, color: '#334155', fillColor: '#80b445', fillOpacity: 1, weight: 3,
          }).bindPopup(`<b>كابتن الرحلة</b><br/>${t.id.slice(0, 12)}`);
          layerRef.current.addLayer(cap); bounds.push([t.captain_lat, t.captain_lng]);
        }
        L.polyline([[t.pickup_lat, t.pickup_lng], [t.dropoff_lat, t.dropoff_lng]], {
          color: '#64748b', weight: 2, dashArray: '6, 6',
        }).addTo(layerRef.current);
      }
    }

    if (bounds.length) mapObj.current.fitBounds(bounds, { padding: [30, 30], maxZoom: 14 });
  };

  useEffect(() => {
    loadLeaflet().then(() => {
      initMap();
      fetchAll();
    });
    return () => { if (mapObj.current) { mapObj.current.remove(); mapObj.current = null; } };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  // Live polling — pauses while the tab is hidden, resumes (with an immediate
  // refetch) when it becomes visible again.
  usePolling(fetchAll, 8000);

  // Re-render map markers when view changes
  useEffect(() => {
    if (mapObj.current) updateMap(trips, captains);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view]);

  // Re-init tile layer when theme changes
  useEffect(() => {
    if (mapObj.current && window.L) {
      mapObj.current.remove();
      mapObj.current = null;
      initMap();
      updateMap(trips, captains);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resolved]);

  return (
    <div className="space-y-4">
      <PageHeader
        title="الخريطة الحية"
        subtitle="متابعة الكباتن والرحلات في الوقت الفعلي"
        actions={
          <div className="flex items-center gap-2">
            <div className="flex bg-surface-secondary rounded-lg p-1 border border-border-primary">
              {(['all', 'trips', 'captains'] as const).map((v) => (
                <button key={v} onClick={() => setView(v)}
                  className={`px-3 py-1.5 text-xs font-medium rounded-md transition-all ${view === v ? 'bg-primary-500 text-white' : 'text-text-secondary hover:text-text-primary'}`}>
                  {v === 'all' ? 'الكل' : v === 'trips' ? 'الرحلات' : 'الكباتن'}
                </button>
              ))}
            </div>
            <button onClick={fetchAll} className="btn-secondary flex items-center gap-2">
              <RefreshCw className="w-4 h-4" /> تحديث
            </button>
          </div>
        }
      />

      {/* Lightweight, dismissible fetch-failure indicator. The last good data
          stays on the map; this just flags that live updates have stalled. */}
      {fetchError && (
        <div className="p-3 bg-error-main/10 border border-error-main/30 rounded-xl text-error-main text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0" />
          <span className="flex-1">تعذّر تحديث البيانات الحية: {fetchError}</span>
          <button onClick={() => setFetchError(null)} className="text-xs hover:underline shrink-0">إغلاق</button>
        </div>
      )}

      {/* Stats row */}
      <div className="grid grid-cols-2 gap-4">
        <div className="bg-surface-primary border border-border-primary rounded-xl p-4 flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-primary-500/10 flex items-center justify-center">
            <Car className="w-5 h-5 text-primary-500" />
          </div>
          <div>
            <p className="text-2xl font-bold text-text-primary">{captains.length}</p>
            <p className="text-xs text-text-tertiary">كابتن متصل</p>
          </div>
        </div>
        <div className="bg-surface-primary border border-border-primary rounded-xl p-4 flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-warning-light flex items-center justify-center">
            <Users className="w-5 h-5 text-warning-main" />
          </div>
          <div>
            <p className="text-2xl font-bold text-text-primary">{trips.length}</p>
            <p className="text-xs text-text-tertiary">رحلة نشطة</p>
          </div>
        </div>
      </div>

      <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden" style={{ height: '500px' }}>
        {loading ? <div className="flex items-center justify-center h-full"><Loader2 className="w-8 h-8 text-text-tertiary animate-spin" /></div> : null}
        <div ref={mapRef} className="w-full h-full" />
      </div>

      <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead><tr className="border-b border-border-primary bg-surface-secondary/50">
              <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">ID</th>
              <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الحالة</th>
              <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">المدينة</th>
              <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الأجرة</th>
              <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الوقت</th>
            </tr></thead>
            <tbody className="divide-y divide-border-primary/50">
              {trips.slice(0, 20).map((t) => (
                <tr key={t.id} className="hover:bg-surface-hover transition-colors">
                  <td className="px-4 py-3 text-sm text-text-primary truncate max-w-[120px]">{t.id.slice(0, 12)}…</td>
                  <td className="px-4 py-3"><span className="px-2 py-0.5 text-xs font-medium rounded-full bg-primary-500/10 text-primary-500">{t.status}</span></td>
                  <td className="px-4 py-3 text-sm text-text-primary">{t.city}</td>
                  <td className="px-4 py-3 text-sm text-text-primary">{t.estimated_fare || '—'}</td>
                  <td className="px-4 py-3 text-sm text-text-tertiary">{new Date(t.created_at).toLocaleTimeString('ar-EG')}</td>
                </tr>
              ))}
              {!trips.length && <tr><td colSpan={5} className="p-8 text-center text-text-tertiary"><MapPin className="w-8 h-8 mx-auto mb-2 text-text-tertiary" />لا توجد رحلات نشطة</td></tr>}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
