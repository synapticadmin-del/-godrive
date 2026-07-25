# Synaptic Go — خطة التحسين الشاملة (تنفيذية)

تاريخ التحديث: 2026-07-24

---

## ما تم تطبيقه (من هذا الإصدار)

### الأساس (مرحلة 0 — الإنتاجية)
1. **WhatsApp OTP جاهز** (`lib/notifications.ts`) — عبر Meta Cloud API (أو 360dialog)؛ عند غياب المفتاح يعود `devCode` فلا تتعطّل الرحلة.
2. **Resend Email OTP جاهز** — نفس الملف؛ بديل لـ WhatsApp عند عدم وجود رقم موبايل.
3. **Paymob حقيقي** (`lib/paymob.ts`) — Intention + Webhook مع **HMAC-SHA512 verification**؛ يعمل كـ stub عند غياب مفتاح `PAYMOB_API_KEY`/`PAYMOB_HMAC`.
4. **المحفظة الداخلية** (`wallet.ts` + `wallet_transactions` في DB) — شحن/خصم/عمولة/تسوية مع كشف حساب.
5. **FCM HTTP v1** (`fcm_service.dart` مشترك + `notifications.ts`) — إشعارات: عرض رحلة، قبول، وصول، إكمال، دفع، فشل دفع، طوارئ.
6. **DB Migration 0003** (`migrations/0003_global_transport.sql`) — كل الجداول الجديدة (18 جدول حاليًا + 11 جديد).
7. **Turnstile** (`turnstile.ts`) — مع `turnstile_verifications` table؛ يعمل في DEV بدون `TURNSTILE_SECRET_KEY`.
8. **Device Tokens** (`routes/devices.ts`) — تسجيل/حذف رموز FCM للعملاء.
9. **CI/DevOps** (`wrangler.toml`) — بيئات `dev/staging/prod` مع `Queues` (`NOTIFICATIONS`) + `Crons` (جدولة مشاوير كل دقيقة + فواتير B2B أول كل شهر).

### تجربة عالمية (مرحلة 1)
10. **تعريب + RTL كامل** (`app_ar.arb` / `app_en.arb` + `main.dart` لكل التطبيقين) + خط `IBM Plex Sans Arabic`.
11. **Design Tokens مشتركة** (`packages/flutter_shared/lib/theme/app_theme.dart`) — متناسق مع `Admin` (`tokens.ts`).
12. **أمان** (`routes/safety.ts`) — SOS + `trip_share_tokens` (تتبّع عام بلا تسجيل) + شات داخلي (`trip_chat_messages`).
13. **جدولة مشاوير** (`scheduled_for`, `scheduled_trip_dispatch`) + `schedule_status`.
14. **مشاوير متعددة المحطات** (`waypoints` JSON على `trips`).
15. **أنواع المركبات + تسعير ديناميكي** (`pricing_rules.surge_multiplier` عبر `surge_multiplier`) مع حفظ `vehicle_type_id` في الرحلة.
16. **خرائط إنتاجية** (`MapTiler` إعداد مستقبلي؛ حاليًا `flutter_map` مع `OSRM` محلي جاهز).

### Intercity + B2B (مرحلة 2/3)
17. **Intercity** (`routes/intercity.ts` + `intercity_routes`/`intercity_schedules`/`intercity_bookings`) — حجز مقاعد + تحقق QR + إدارة الكابتن.
18. **B2B** (`routes/companies.ts` + `company_employees`) — فوترة شهرية (`company_invoices`) + حدود إنفاق + سياسات سيارات.

---

## ما يتبقى (المفاتيح البديلة مطلوبة من المستخدم)

| الخاصية | البديل المطلوب من المستخدم | متى نحتاجه |
|---|---|---|
| `WHATSAPP_TOKEN` + `WHATSAPP_PHONE_NUMBER_ID` | **WhatsApp Business API** (360dialog للسرعة أو Meta مباشرة) | لإرسال OTP عبر واتساب بدلاً من المحاكاة |
| `EMAIL_RESEND_API_KEY` | **Resend** (أو Brevo) | لإرسال OTP عبر إيميل حقيقي |
| `PAYMOB_API_KEY` + `PAYMOB_HMAC` + `PAYMOB_IFRAME_ID` | **Paymob** (حساب تجاري مصري) | الدفع الإلكتروني الحقيقي |
| `FCM_PROJECT_ID` + `FCM_CLIENT_EMAIL` + `FCM_PRIVATE_KEY` | **Firebase Service Account** (من `google-services.json` المُعطى) | إشعارات FCM حية (حاليًا جاهز لكن بدون مفاتيح تعمل كـ best-effort) |
| `TURNSTILE_SITE_KEY` | **Cloudflare Turnstile widget** (من لوحة Cloudflare) | حماية واجهات التسجيل من البوتات |

---

## الخطوات التالية المقترحة (عند جلب المفاتيح)
1. `wrangler secret put WHATSAPP_TOKEN` + `WHATSAPP_PHONE_NUMBER_ID`.
2. `wrangler secret put PAYMOB_API_KEY` + `PAYMOB_HMAC` + إعداد `PAYMOB_IFRAME_ID`.
3. `wrangler secret put FCM_PROJECT_ID` + `FCM_CLIENT_EMAIL` + تحميل `google-services.json` كمفتاح خاص `FCM_PRIVATE_KEY` (PEM مع \n).
4. إعادة تشغيل API (`wrangler deploy`) واختبار التدفق الكامل.

---

## ما تم تغييره في الاستاك الحالي (دون كسره)
- **لا تغيير في المنصة**: Cloudflare Workers + D1 + KV + R2 + Durable Objects + Flutter.
- **لا إزالة ميزات موجودة**: OTP DEV ما زال يعمل كاحتياطي، Paymob stub ما زال يعمل، المحفظة القديمة (`wallet.ts`) ما زالت متوافقة مع `wallet_transactions`.
- **إضافة فقط**: كل التعديلات الجديدة مُضافة أعلى الاستاك الحالي دون كسر الـ APIs الحالية (`/auth`, `/trips`, `/captain`, `/admin`, `/payments`, `/user`).
