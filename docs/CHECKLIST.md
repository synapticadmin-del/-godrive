# Checklist — المطلوب منك

## الآن (للنشر)

- [x] Cloudflare account access (`lolelarap@gmail.com`)
- [x] `wrangler login` على الجهاز
- [x] الدومين `synapticstudio.tech` على **نفس** حساب Cloudflare
- [x] إنشاء: Workers, Pages, D1, KV, R2
- [x] Node.js 20+ 
- [ ] **إضافة CNAME يدويًا:** `admin` → `synaptic-go-admin.pages.dev` (Proxied)
- [ ] بعد تفعيل admin domain: افتح `https://admin.synapticstudio.tech`

## لتطبيقات الموبايل

- [x] تثبيت Flutter SDK (stable)
- [x] Android Studio + Android SDK
- [ ] جهاز أندرويد أو emulator للتجربة

## قريبًا (مش يوم 1)

- [ ] Firebase project (FCM push)
- [ ] SMTP provider (Resend / Brevo) لـ OTP حقيقي
- [ ] VPS صغير لـ OSRM مصر (routing دقيق)
- [ ] Map tiles key احتياطي (MapTiler free)
- [ ] Google Play Console ($25) عند النشر
- [ ] Apple Developer عند iOS

## أسرار هطلبها وقت الربط

- [ ] تأكيد Account ID
- [ ] JWT secret (أو نولّده ونحفظه)
- [ ] SMTP API key (لاحقًا)
- [ ] FCM credentials (لاحقًا)

## Domains المعتمدة

- [x] `api.synapticstudio.tech` — **شغّال**
- [ ] `admin.synapticstudio.tech` — مربوط في Pages، ينتظر CNAME من DNS
- [x] Admin fallback: `https://synaptic-go-admin.pages.dev`
- [x] API fallback: `https://synaptic-go-api.lolelarap.workers.dev`

## روابط حالية

| خدمة | URL |
|------|-----|
| API Health | https://api.synapticstudio.tech/health |
| Admin | https://synaptic-go-admin.pages.dev |
| Admin login email | `admin@synapticstudio.tech` (OTP يظهر في وضع DEV) |


## Flutter build status
- [x] Rider APK debug built
- [x] Captain APK debug built
- APKs folder: `Desktop/SynapticGo-APKs`
