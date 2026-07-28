# Synaptic Go

تطبيق توصيل (Ride-hailing) اقتصادي لمصر — مبني على **Cloudflare** + **Flutter** + **Admin Dashboard**.

## التطبيقات

| التطبيق | التقنية | الرابط / النشر |
|---------|---------|----------------|
| **API** | Cloudflare Workers + Hono | `https://api.synapticstudio.tech` |
| **Admin** | React + Vite → Cloudflare Pages | `https://admin.synapticstudio.tech` |
| **Rider** | Flutter | APK / Play Store |
| **Captain** | Flutter | APK / Play Store |

## هيكل المشروع

```text
├── apps/
│   ├── api/          # Backend (Workers)
│   ├── admin/        # لوحة تحكم الشركة
│   ├── rider/        # تطبيق العميل
│   └── captain/      # تطبيق الكابتن
├── packages/
│   ├── shared/       # Types + fare math (TypeScript)
│   └── flutter_shared/
├── migrations/       # D1 SQL
├── scripts/          # سكربتات مساعدة (bat / pdf)
├── docs/             # التوثيق
│   └── assets/       # الشعار + لقطات الشاشة والفيديو
└── .github/          # CI workflows
```

## البدء السريع

> **ملاحظة:** الـ API يحتاج أسرارًا (JWT, Turnstile, Paymob, FCM, WhatsApp, …). انسخ `apps/api/.dev.vars.example` إلى `apps/api/.dev.vars` واملأ القيم محليًا — التفاصيل داخل الملف.

### المتطلبات
- Node.js 20+
- npm
- Cloudflare account + `wrangler login`
- Flutter SDK (لتطبيقات الموبايل)
- Android Studio (لبناء APK)

### 1) تثبيت الحزم
```bash
npm install
```

### 2) إعداد قاعدة البيانات محليًا
```bash
npm run db:migrate:local
```

### 3) تشغيل API محليًا
```bash
npm run dev:api
```

### 4) تشغيل Admin محليًا
```bash
npm run dev:admin
```

### 5) Deploy
```bash
# API
npm run deploy:api

# Admin
npm run deploy:admin
```

## التوثيق

- [الاستاك](docs/STACK.md)
- [المعمارية](docs/ARCHITECTURE.md)
- [API](docs/API.md)
- [النشر](docs/DEPLOYMENT.md)
- [التكلفة](docs/COST.md)
- [Checklist المطلوب منك](docs/CHECKLIST.md)

## Trip Status Flow

```text
searching → offered → assigned → arrived → in_progress → completed
                ↘ cancelled ↙
```

## Brand

**Synaptic Go** — by Synaptic Studio  
Domain: `synapticstudio.tech`
