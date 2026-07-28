// api.ts
const API_URL = import.meta.env.VITE_API_URL || 'https://api.synapticstudio.tech';

const TOKEN_KEY = 'sg_admin_token';
const USER_KEY = 'sg_admin_user';
const REFRESH_KEY = 'sg_admin_refresh';

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function getApiUrl() {
  return API_URL;
}

/**
 * Fetch a protected document/file as an authenticated Blob URL.
 * The file endpoint requires the JWT in the Authorization header — it must NOT
 * be appended to the URL as a query param (which leaks it into logs/history).
 * The caller is responsible for revoking the returned object URL.
 */
export async function fetchDocumentBlobUrl(docId: string): Promise<string> {
  const res = await fetch(`${API_URL}/admin/documents/${docId}/file`, {
    headers: { Authorization: `Bearer ${getToken()}` },
  });
  if (!res.ok) throw new Error(`فشل تحميل المستند (${res.status})`);
  return URL.createObjectURL(await res.blob());
}

type RefreshResponse = { accessToken: string; refreshToken?: string };

function clearSessionAndRedirect() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
  localStorage.removeItem(REFRESH_KEY);
  if (window.location.pathname !== '/login') {
    window.location.href = '/login';
  }
}

// Guard against concurrent refresh attempts: share one in-flight promise so a
// burst of parallel 401s triggers exactly one /auth/refresh call.
let refreshPromise: Promise<string | null> | null = null;

async function refreshAccessToken(): Promise<string | null> {
  const refreshToken = localStorage.getItem(REFRESH_KEY);
  if (!refreshToken) return null;

  if (!refreshPromise) {
    refreshPromise = (async () => {
      try {
        const res = await fetch(`${API_URL}/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken }),
        });
        const data = (await res.json().catch(() => ({}))) as Partial<RefreshResponse>;
        if (!res.ok || !data.accessToken) return null;
        localStorage.setItem(TOKEN_KEY, data.accessToken);
        if (data.refreshToken) localStorage.setItem(REFRESH_KEY, data.refreshToken);
        return data.accessToken;
      } catch {
        return null;
      } finally {
        // Reset so a later 401 can attempt a fresh refresh.
        refreshPromise = null;
      }
    })();
  }
  return refreshPromise;
}

export async function api<T>(
  path: string,
  options: RequestInit & { token?: string | null } = {}
): Promise<T> {
  const { token, ...init } = options;

  const doFetch = (authToken: string | null) =>
    fetch(`${API_URL}${path}`, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
        ...(init.headers || {}),
      },
    });

  let res = await doFetch(token ?? null);

  // On 401, try to refresh the session once and retry the original request
  // with the new access token. Only if refresh fails do we tear down the session.
  if (res.status === 401) {
    const newToken = await refreshAccessToken();
    if (newToken) {
      res = await doFetch(newToken);
    }
    if (res.status === 401) {
      clearSessionAndRedirect();
    }
  }

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error((data as { error?: string }).error || `HTTP ${res.status}`);
  }
  return data as T;
}
