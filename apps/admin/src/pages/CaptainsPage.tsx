import { useEffect, useState, useRef } from 'react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { StatusBadge } from '../components/ui/Badge';
import { Search, Check, Ban, Loader2, Star, Car, MapPin, Navigation } from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';

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
  const [captains, setCaptains] = useState<Captain[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const [processingId, setProcessingId] = useState<string | null>(null);
  const [selectedCaptainId, setSelectedCaptainId] = useState<string | null>(null);
  const [mapLoaded, setMapLoaded] = useState(false);

  const mapRef = useRef<HTMLDivElement>(null);
  const mapObj = useRef<any>(null);
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
    L.tileLayer('https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png', {
      attribution: '&copy; Synaptic Go',
      maxZoom: 19,
      subdomains: ['a', 'b', 'c'],
    }).addTo(mapObj.current);

    layerRef.current = L.layerGroup().addTo(mapObj.current);
    setMapLoaded(true);
  };

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

      const popupContent = `
        <div style="text-align: right; direction: rtl; font-family: sans-serif; padding: 4px;">
          <h4 style="margin: 0; font-size: 14px; font-weight: bold; color: #0f172a;">${c.name || 'كابتن'}</h4>
          <p style="margin: 4px 0 0 0; font-size: 12px; color: #64748b;">📱 ${c.phone || c.email}</p>
          ${c.vehicle_plate ? `<p style="margin: 4px 0 0 0; font-size: 12px; font-weight: bold; color: #0ea5e9;">🚘 ${c.vehicle_make || ''} (${c.vehicle_plate})</p>` : ''}
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

  useEffect(() => {
    loadLeaflet().then(() => {
      initMap();
      fetchCaptains(true);
    });

    const interval = setInterval(() => {
      fetchCaptains(false);
    }, 10000);

    return () => {
      clearInterval(interval);
      if (mapObj.current) {
        mapObj.current.remove();
        mapObj.current = null;
      }
    };
  }, [token, filter]);

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
              {([
                ['', 'الكل'],
                ['approved', 'معتمد'],
                ['pending', 'بانتظار'],
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
          {loading && !mapLoaded && (
            <div className="absolute inset-0 z-10 bg-surface-primary/80 flex items-center justify-center">
              <Loader2 className="w-8 h-8 text-primary-500 animate-spin" />
            </div>
          )}
          <div ref={mapRef} className="w-full h-full" />
        </div>
      </div>

      <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden">
        {loading && captains.length === 0 ? (
          <div className="p-12 text-center">
            <Loader2 className="w-8 h-8 mx-auto text-text-tertiary animate-spin" />
            <p className="text-text-secondary mt-2">جاري تحميل بيانات الكباتن...</p>
          </div>
        ) : filteredCaptains.length === 0 ? (
          <div className="p-12 text-center">
            <Car className="w-12 h-12 mx-auto text-text-tertiary mb-4" />
            <p className="text-text-secondary">لا يوجد كباتن مطبق عليهم البحث</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border-primary bg-surface-secondary/50">
                  <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الكابتن</th>
                  <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">التواصل</th>
                  <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">السيارة</th>
                  <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">التقييم</th>
                  <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">الحالة / الموقع</th>
                  <th className="px-4 py-3 text-right text-sm font-medium text-text-secondary">إجراءات</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-primary/50">
                {filteredCaptains.map((c) => {
                  const isSelected = selectedCaptainId === c.user_id;
                  const lat = getCaptainLat(c);
                  const lng = getCaptainLng(c);
                  const hasLocation = lat != null && lng != null;

                  return (
                    <tr
                      key={c.user_id}
                      onClick={() => handleFocusCaptain(c)}
                      className={`cursor-pointer transition-colors ${
                        isSelected ? 'bg-primary-500/10 border-l-4 border-l-primary-500' : 'hover:bg-surface-hover'
                      }`}
                    >
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-3">
                          <div className="w-9 h-9 rounded-lg bg-primary-500/10 text-primary-500 font-bold flex items-center justify-center text-sm">
                            {(c.name || 'C')[0].toUpperCase()}
                          </div>
                          <div>
                            <p className="font-medium text-text-primary text-sm">{c.name || 'كابتن'}</p>
                            <p className="text-xs text-text-tertiary font-mono">{c.user_id.slice(0, 8)}</p>
                          </div>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <p className="text-sm text-text-primary font-mono">{c.phone || '—'}</p>
                        <p className="text-xs text-text-tertiary">{c.email}</p>
                      </td>
                      <td className="px-4 py-3">
                        <p className="text-sm text-text-primary">
                          {c.vehicle_make ? `${c.vehicle_make} ${c.vehicle_model || ''}` : '—'}
                        </p>
                        {c.vehicle_plate && (
                          <span className="inline-block mt-1 px-2 py-0.5 bg-warning-main/10 text-warning-main font-mono text-xs font-bold rounded">
                            {c.vehicle_plate}
                          </span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-1">
                          <Star className="w-4 h-4 fill-warning-main text-warning-main" />
                          <span className="text-sm font-bold text-text-primary">
                            {c.rating_avg ? c.rating_avg.toFixed(1) : '5.0'}
                          </span>
                          <span className="text-xs text-text-tertiary">({c.rating_count})</span>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <StatusBadge status={c.approval_status} />
                          {c.is_online ? (
                            <span className="inline-flex items-center gap-1 text-xs text-success-main font-bold">
                              <span className="w-2 h-2 rounded-full bg-success-main animate-pulse" /> متصل
                            </span>
                          ) : (
                            <span className="text-xs text-text-tertiary">مغلق</span>
                          )}
                        </div>
                      </td>
                      <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => handleFocusCaptain(c)}
                            title="تحديد موقعه على الخريطة"
                            className={`flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-lg transition-colors border ${
                              hasLocation && c.is_online
                                ? 'bg-primary-500/10 hover:bg-primary-500/20 text-primary-500 border-primary-500/30'
                                : 'bg-surface-secondary text-text-tertiary border-border-primary'
                            }`}
                          >
                            <Navigation className="w-3.5 h-3.5" /> موقع الكابتن
                          </button>
                          {c.approval_status === 'pending' && (
                            <button
                              disabled={processingId === c.user_id}
                              onClick={() => handleApprove(c.user_id)}
                              className="flex items-center gap-1 px-3 py-1.5 bg-success-main hover:bg-success-dark text-white text-xs font-medium rounded-lg transition-colors disabled:opacity-50"
                            >
                              {processingId === c.user_id ? (
                                <Loader2 className="w-3 h-3 animate-spin" />
                              ) : (
                                <Check className="w-3 h-3" />
                              )}{' '}
                              اعتماد
                            </button>
                          )}
                          {c.approval_status === 'approved' && (
                            <button
                              disabled={processingId === c.user_id}
                              onClick={() => handleSuspend(c.user_id)}
                              className="flex items-center gap-1 px-3 py-1.5 bg-error-main/10 hover:bg-error-main/20 text-error-main text-xs font-medium rounded-lg border border-error-main/30 transition-colors disabled:opacity-50"
                            >
                              <Ban className="w-3 h-3" /> إيقاف
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}