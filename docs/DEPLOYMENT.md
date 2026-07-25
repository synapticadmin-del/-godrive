# Synaptic Go — Deployment

## Domains

| Host | Product | Status |
|------|---------|--------|
| `https://api.synapticstudio.tech` | Workers API | ✅ linked |
| `https://synaptic-go-api.lolelarap.workers.dev` | Workers fallback | ✅ live |
| `https://admin.synapticstudio.tech` | Pages Admin | ⏳ needs CNAME |
| `https://synaptic-go-admin.pages.dev` | Pages fallback | ✅ live |

Domain is on the **same Cloudflare account** used by Wrangler (`lolelarap@gmail.com`).

## Prerequisites

```bash
npm install -g wrangler
wrangler login
```

Confirm account:
```bash
wrangler whoami
```

## 1) Create Cloudflare resources

From `apps/api`:

```bash
# D1
wrangler d1 create synaptic-go

# KV
wrangler kv namespace create SESSIONS

# R2
wrangler r2 bucket create synaptic-go-files
```

Copy returned IDs into `apps/api/wrangler.toml`.

## 2) Apply migrations

```bash
# local
wrangler d1 migrations apply synaptic-go --local

# remote
wrangler d1 migrations apply synaptic-go --remote
```

## 3) Secrets

```bash
cd apps/api
wrangler secret put JWT_SECRET
# optional later:
# wrangler secret put SMTP_API_KEY
# wrangler secret put FCM_SERVER_KEY
```

Set vars in `wrangler.toml`:
- `DEV_OTP = "false"` in production
- `APP_URL = "https://admin.synapticstudio.tech"`

## 4) Deploy API

```bash
cd apps/api
wrangler deploy
```

Attach custom domain in dashboard:
**Workers & Pages → synaptic-go-api → Settings → Domains & Routes**
→ Add `api.synapticstudio.tech`

Or routes in wrangler:
```toml
routes = [
  { pattern = "api.synapticstudio.tech/*", zone_name = "synapticstudio.tech" }
]
```

## 5) Deploy Admin (Pages)

```bash
cd apps/admin
npm install
npm run build
npx wrangler pages project create synaptic-go-admin
npx wrangler pages deploy dist --project-name=synaptic-go-admin
```

Custom domain:
**Pages → synaptic-go-admin → Custom domains → admin.synapticstudio.tech**

Build env:
```
VITE_API_URL=https://api.synapticstudio.tech
```

## 6) DNS checklist (Cloudflare DNS)

### API
Already attached as Workers custom domain:
`api.synapticstudio.tech` → `synaptic-go-api`

### Admin (required once)
In Cloudflare Dashboard → **DNS** → `synapticstudio.tech` → Add record:

| Type | Name | Target | Proxy |
|------|------|--------|-------|
| CNAME | `admin` | `synaptic-go-admin.pages.dev` | Proxied (orange cloud) |

Then Pages → **synaptic-go-admin** → Custom domains should show `admin.synapticstudio.tech` as active.

> Note: Wrangler OAuth token may lack `zone` write scope, so create the CNAME from the dashboard.

## 7) CORS

API allowlist includes:
- `https://admin.synapticstudio.tech`
- `http://localhost:5173`
- `http://127.0.0.1:5173`

Flutter mobile apps call API directly (no browser CORS).

## 8) Flutter apps

```bash
# after Flutter installed
cd apps/rider
flutter pub get
flutter run

cd apps/captain
flutter pub get
flutter run
```

Configure API base URL:
- debug: `http://10.0.2.2:8787` (Android emulator → host)
- release: `https://api.synapticstudio.tech`

## 9) Smoke test

1. `GET https://api.synapticstudio.tech/health`
2. Admin login with seeded admin email OTP
3. Create captain + approve in admin
4. Rider request trip
5. Captain accept + complete

## Troubleshooting

| Issue | Fix |
|-------|-----|
| 1027 / free limit | Upgrade Workers Paid ($5) |
| D1 not found | Re-check database_id in wrangler.toml |
| CORS error | Confirm admin origin in API CORS list |
| Domain not resolving | Ensure domain on same CF account + proxy on |
