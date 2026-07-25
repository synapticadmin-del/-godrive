// api.ts
const API_URL = import.meta.env.VITE_API_URL || 'https://api.synapticstudio.tech';

export async function api<T>(
  path: string,
  options: RequestInit & { token?: string | null } = {}
): Promise<T> {
  const { token, ...init } = options;

  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init.headers || {}),
    },
  });

  const data = await res.json().catch(() => ({}));
  if (res.status === 401) {
    localStorage.removeItem('sg_admin_token');
    localStorage.removeItem('sg_admin_refresh_token');
    if (window.location.pathname !== '/login') {
      window.location.href = '/login';
    }
  }
  if (!res.ok) {
    throw new Error((data as { error?: string }).error || `HTTP ${res.status}`);
  }
  return data as T;
}

export function getApiUrl() {
  return API_URL;
}