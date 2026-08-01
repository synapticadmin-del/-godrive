# فيتشرز وقدرات الـ API (Backend)

> **النطاق:** Cloudflare Workers API — `apps/api/`
> **المصدر:** قراءة مباشرة من الكود (routes + middleware + Durable Objects + migrations)
> **آخر تحديث:** 2026-08-01

---

## 1. المعمارية التقنية

| المكوّن | التقنية | الغرض |
|---------|---------|-------|
| Runtime | Cloudflare Workers | Edge computing — استجابة عالمية منخفضة الكمون |
| Framework | Hono | Lightweight routing مع TypeScript |
| Database | Cloudflare D1 (SQLite) | تخزين علائقي managed |
| Cache/Session | Cloudflare KV | Rate limiting + OTP + ETA cache + cleanup gates |
| Realtime | Durable Objects (4) | WebSocket rooms + scheduling + geo matching |
| Storage | Cloudflare R2 | مستندات الكباتن + صور المستخدمين |
| Queue | Cloudflare Queues | إشعارات batch مع retry/DLQ |
| Routing | OSRM (self-hosted أو public) | حساب المسافات والأزمنة الحقيقية |

---

## 2. المصادقة والأمان

| الميزة | التفاصيل | المصدر |
|--------|----------|--------|
| OTP | 6 أرقام، 10 دقائق صلاحية، 5 محاولات قصوى | `auth.ts` |
| Turnstile | Cloudflare anti-bot — إجباري قبل OTP | `turnstile.ts` |
| JWT | access (قصير) + refresh (30 يوم) مع rotation | `jwt.ts` |
| Password | PBKDF2 salted — ترقية تلقائية من SHA-256 legacy | `utils.ts` |
| Rate limiting | fixed-window على KV — عام 120/دقيقة + خاص بكل endpoint | `rateLimit.ts` |
| Zod validation | كل الـ inputs مع schemas مشددة | `schemas.ts` |
| CORS | allowlist محددة — لا wildcard لـ *.pages.dev | `index.ts` |
| Security headers | nosniff + no-store + attachment للـ PDF | `captain.ts` + `admin.ts` |

---

## 3. نظام الرحلات الأساسي

| الميزة | التفاصيل | المصدر |
|--------|----------|--------|
| State machine | searching → offered → assigned → arrived → in_progress → completed + cancelled | `packages/shared` |
| Fare estimation | OSRM routing + pricing rules per city | `trips.ts` + `routing.ts` |
| Surge pricing | multiplier من pricing_rules (comment field) | `trips.ts` |
| Promo codes | نسبة/ثابت مع max_uses + expires_at | `promo.ts` |
| Scheduled trips | cron كل دقيقة — يفعل الرحلات المجدولة | `index.ts` scheduled |
| Waypoints | حتى 5 نقاط توقف | `createTripSchema` |
| B2B billing | رحلات الشركات تُجمّع للفوترة الشهرية | `companies.ts` |

---

## 4. نظام المزايدة (Bidding)

| الميزة | التفاصيل | المصدر |
|--------|----------|--------|
| Captain counter-offer | الكابتن يزايد على السعر المقترح | `trips.ts` `/bid` |
| Staged rollout | 3 كباتن كل 15 ثانية — يمنع السباق | `OfferScheduler.ts` |
| ETA per bid | OSRM table service + KV cache 60 ثانية | `trips.ts` `attachCaptainEtas` |
| Atomic acceptance | conditional UPDATE — لا double-assign | `trips.ts` `/accept-bid` |
| Real-time updates | WebSocket broadcast لكل الأحداث | `TripRoom.ts` |

---

## 5. التتبع اللحظي (Realtime)

| المكون | الغرض | المصدر |
|--------|-------|--------|
| TripRoom DO | WebSocket لكل رحلة نشطة — fanout للتحديثات | `TripRoom.ts` |
| CaptainInbox DO | WebSocket شخصي لكل كابتن — العروض والإلغاءات | `CaptainInbox.ts` |
| GeoCell DO | geohash matching للكباتن القريبين | `GeoCell.ts` |
| OfferScheduler DO | staged rollout للعروض مع alarm | `OfferScheduler.ts` |
| Auth handshake | first-message JWT للـ WebSocket (10s timeout) | `TripRoom.ts` |

---

## 6. نظام المدفوعات

| الميزة | التفاصيل | المصدر |
|--------|----------|--------|
| Paymob integration | intention → iframe → webhook | `payments.ts` + `paymob.ts` |
| HMAC verification | SHA-512 على webhook payload | `paymob.ts` |
| Amount tamper check | ما دُفع = ما طُلب — لا أكثر لا أقل | `payments.ts` |
| Idempotency | intention-level + transaction-level | `payments.ts` |
| Wallet ledger | سجل كامل مع piastres للدقة | `wallet.ts` |
| Payout requests | كابتن يطلب سحب — مراجعة يدوية | `wallet.ts` |

---

## 7. نظام الأمان (Safety)

| الميزة | التفاصيل | المصدر |
|--------|----------|--------|
| SOS alerts | إشعار فوري لكل الأدمنز + تسجيل | `safety.ts` |
| Trip sharing | رابط عام بصلاحية محددة (TTL) | `safety.ts` |
| In-trip chat | رسائل بدون كشف هواتف | `safety.ts` |
| Typing indicator | ephemeral — لا يُخزن | `safety.ts` |
| Ratings | 1–5 لكل طرف — مرة واحدة لكل رحلة | `trips.ts` |

---

## 8. الإشعارات

| القناة | الاستخدام | المصدر |
|--------|-----------|--------|
| FCM Push | كل أحداث الرحلة للطرفين | `notifications.ts` |
| WhatsApp OTP | تسجيل الدخول برقم مصري | `notifications.ts` |
| Email OTP | بديل للإيميل | `notifications.ts` |
| Queue batch | fanout للإشعارات الكثيفة مع retry | `index.ts` queue |
| WebSocket | تحديثات لحظية داخل التطبيق | Durable Objects |

---

## 9. الرحلات بين المحافظات

| الميزة | التفاصيل | المصدر |
|--------|----------|--------|
| Routes | مسارات محددة (مدينة → مدينة) | `intercity.ts` |
| Schedules | مواعيد مغادرة بمقاعد محدودة | `intercity.ts` |
| Seat claiming | conditional UPDATE — لا overbooking | `intercity.ts` |
| QR boarding | token فريد لكل حجز | `intercity.ts` |
| Free cancellation | استرداد كامل قبل المغادرة | `intercity.ts` |

---

## 10. الشركات (B2B)

| الميزة | التفاصيل | المصدر |
|--------|----------|--------|
| Employee binding | ربط مستخدم بشركة + cost center | `companies.ts` |
| Spend limits | حد شهري لكل موظف — يُتحقق قبل الرحلة | `companies.ts` |
| Monthly invoicing | cron يوم 1 + يدوي — تجميع رحلات الشهر | `companies.ts` + `index.ts` |
| Company portal | view محدود للشركة نفسها | `companies.ts` |

---

## 11. المهام المجدولة (Cron)

| التوقيت | المهمة | المصدر |
|---------|--------|--------|
| كل دقيقة | تفعيل الرحلات المجدولة | `index.ts` scheduled |
| يومي (24h gate) | تنظيف البيانات المنتهية | `cleanup.ts` |
| يوم 1 من كل شهر | إصدار فواتير الشركات | `index.ts` scheduled |
| عند كل request (admin) | تنظيف جلسات الكباتن القديمة (5 دقائق) | `admin.ts` |

---

## 12. نقاط النهاية (Endpoints) الرئيسية

| المسار | الوصف | Auth |
|--------|-------|------|
| `POST /auth/request-otp` | طلب رمز OTP | Turnstile |
| `POST /auth/verify-otp` | تحقق + تسجيل دخول | - |
| `POST /auth/refresh` | تجديد access token | refresh token |
| `POST /trips` | إنشاء رحلة | rider |
| `GET /trips/:id/bids` | عروض الكباتن | rider/admin |
| `POST /trips/:id/accept-bid` | قبول عرض | rider/admin |
| `POST /trips/:id/cancel` | إلغاء | rider/captain/admin |
| `POST /captain/online` | الذهاب أونلاين | captain |
| `POST /captain/location` | تحديث الموقع | captain |
| `POST /payments/paymob/intention` | إنشاء دفعة | any |
| `POST /payments/paymob/webhook` | Paymob callback | HMAC |
| `GET /admin/stats` | إحصائيات | admin |
| `GET /admin/analytics` | تحليلات | admin |
| `POST /admin/captains/:id/approve` | اعتماد كابتن | admin |
| `GET /ws/trips/:id` | WebSocket رحلة | JWT |
| `GET /ws/captain/offers` | WebSocket كابتن | JWT |

---

## 13. قاعدة البيانات (D1 Schema)

| الجدول | الغرض | migration |
|--------|-------|-----------|
| users | كل المستخدمين (rider/captain/admin) | 0001 |
| captains | بيانات الكابتن الإضافية | 0001 |
| trips | الرحلات | 0001 |
| trip_events | سجل أحداث الرحلة | 0001 |
| trip_bids | عروض المزايدة | 0004 |
| trip_path_points | نقاط المسار | 0002 |
| ratings | التقييمات | 0001 |
| otp_codes | رموز OTP | 0001 |
| refresh_tokens | جلسات | 0001 |
| wallet_transactions | سجل المحفظة | 0002 |
| payment_intentions | نوايا الدفع Paymob | 0011 |
| device_tokens | FCM tokens | 0002 |
| driver_documents | مستندات الكباتن | 0002 |
| document_types | كتالوج المستندات | 0014 |
| pricing_rules | قواعد التسعير | 0001 |
| promo_codes | البروموكودات | 0002 |
| sos_alerts | إنذارات الطوارئ | 0002 |
| trip_share_tokens | روابط المشاركة | 0002 |
| trip_chat_messages | دردشة الرحلة | 0002 |
| companies + employees | B2B | 0003 |
| intercity_* | الرحلات بين المحافظات | 0003 |
| system_config | إعدادات المنصة | 0016 |
| audit_log | سجل التدقيق | 0001 |

---

## ملخص القدرات

| الفئة | العدد |
|-------|-------|
| Durable Objects | 4 |
| Cron jobs | 4 |
| API endpoints | ~60 |
| Database tables | 23 |
| Security features | 8 |
| Realtime channels | 3 |

---

> **ملاحظة:** كل قدرة مذكورة هنا مستخرجة من الكود الفعلي في `apps/api/src/` و`migrations/`. لا توجد قدرات مخططة — فقط ما هو منفَّذ ويعمل.
