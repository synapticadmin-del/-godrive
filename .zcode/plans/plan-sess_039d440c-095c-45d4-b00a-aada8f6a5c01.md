# خطة التحسين الشاملة لتطبيقَي GoDrive (Rider + Captain)

الهدف: رفع مستوى التطبيقَين ليقارب Uber/Careem في الصفحات والمكوّنات والتجربة، مع الالتزام بنفس الاستاك (Flutter + flutter_map + provider + Cloudflare API) والهوية البصرية GoDrive (أخضر #80B445 + أبيض/أسود نقي).

---

## أولاً: الشريط السفلي (Bottom Navigation) المطلوب

**الشكل:** مسطّح نظيف، خلفية الثيم الحالي (أبيض/أسود)، 5 عناصر، الحالة النشطة بالأخضر #80B445.

**تطبيق الراكب (5 عناصر مع زر وسط بارز):**
```
[ الرئيسية ]  [ رحلاتي ]  [ ● طلب رحلة ● ]  [ المحفظة ]  [ حسابي ]
```
- الزر الأوسط دائري بارز (FAB notch) بخلفية خضراء + أيقونة سيارة/تنقّل
- عند وجود رحلة نشطة يتحوّل لزر "الرحلة الحالية" بدل "طلب رحلة"

**تطبيق الكابتن (5 عناصر مع زر وسط بارز):**
```
[ الخريطة ]  [ الرحلات ]  [ ● متصل/غير متصل ● ]  [ الأرباح ]  [ حسابي ]
```
- الزر الأوسط يبدّل حالة الاتصال (online/offline) بلون دلالي (أخضر متصل / رمادي غير متصل)

**التنفيذ:** `packages/flutter_shared/lib/widgets/main_bottom_nav.dart` مكوّن مشترك يقبَل `items` + `centerIndex` + `onCenterTap` + حالة نشطة. يُحقن في `Scaffold.bottomNavigationBar` في كلا التطبيقَين.

---

## ثانيًا: تطبيق الراكب — صفحات ومكونات جديدة

### الصفحات الموجودة (تبقى وتُحسَّن)
| الحالية | التحسين |
|---|---|
| `splash_screen` | جاهز (لوجو GoDrive) |
| `login_screen` | إضافة تبويب بريد/واتساب + تحسين بصري |
| `home/home_screen` | إعادة هيكلة: خريطة + شريط سفلي + bottom sheet متدرّج الحالات |
| `home/fare_estimate_sheet` | إضافة تقدير زمني + أنواع مركبات بصرية |
| `home/vehicle_selector` | بطاقات أنواع (اقتصادية/مريحة/بريميوم) بصور + ETA |
| `trip/trip_screen` | إعادة تصميم: حالة البحث، حالة القبول، تتبّع حي، شريط تقدّم |
| `trip/trip_chat_screen` | شات داخل التطبيق (جاهز في API) |
| `history/history_screen` | فلترة بالحالة + تفاصيل قابلة للتوسيع |
| `wallet/wallet_screen` | جاهز + Paymob WebView |
| `wallet/topup_screen` | مبسّط |
| `places/saved_places_screen` | اختيار على الخريطة + بحث عنوان |
| `profile/profile_screen` | بطاقة مستخدم + إحالات + كود دعوة |
| `profile/settings_screen` | تبديل لغة/ثيم + حذف حساب |
| `safety/sos_screen` | زر SOS + مشاركة رحلة + جهات اتصال طوارئ |

### صفحات/مكوّنات جديدة (مستوحاة من Uber/Careem)
1. **`screens/home/where_to_sheet.dart`** — الصفحة الأولى بعد فتح التطبيق: حقل بحث وجهة + "المنزل"/"العمل" + آخر رحلاتك + اقتراحات أماكن
2. **`screens/ride/ride_options_sheet.dart`** — اختيار نوع المركبة + طريقة الدفع + كود خصم + خيارات (موسيقى، حرارة، محادثة) قبل التأكيد
3. **`screens/ride/payment_methods_screen.dart`** — إدارة طرق الدفع (كاش/محفظة/بطاقة) + إضافة بطاقة Paymob
4. **`screens/ride/promo_screen.dart`** — قائمة أكواد الخصم النشطة + إدخال كود
5. **`screens/ride/schedule_screen.dart`** — جدولة رحلة لوقت لاحق (منتقي تاريخ/وقت)
6. **`screens/ride/trip_detail_screen.dart`** — تفاصيل الرحلة بعد الإكمال: مسار، أجرة، تقييم، إيصال PDF
7. **`screens/ride/rating_sheet.dart`** — تقييم + تعليق + إكرامية اختيارية
8. **`screens/profile/invite_screen.dart`** — كود إحالة + مشاركة + رصيد مكافآت
9. **`screens/profile/help_screen.dart`** — مركز المساعدة: FAQ + شات دعم + رحلات سابقة
10. **`screens/notifications_screen.dart`** — مركز إشعارات داخل التطبيق
11. **`widgets/trip_status_badge.dart`** — شريط حالة علوي متحرك (بحث→قبول→وصول→رحلة)
12. **`widgets/driver_info_card.dart`** — بطاقة الكابتن (صورة، اسم، سيارة، لوحة، تقييم)
13. **`widgets/location_search_field.dart`** — حقل بحث عناوين + autocomp
14. **`widgets/map_markers.dart`** — علامات مخصّصة (موقف/وجهة/كابتن متحرك)

### إعادة هيكلة Home Screen
من `home_screen.dart` واحد كبير إلى:
- `MainShell` يحتوي الخريطة + الشريط السفلي + `IndexedStack` للتبويبات
- كل تبويب صفحة مستقلة: HomeTab, HistoryTab, WalletTab, ProfileTab
- الـ "Where to" sheet يظهر عند الضغط على زر الوسط

---

## ثالثًا: تطبيق الكابتن — صفحات ومكونات جديدة

### الموجودة (تُحسَّن)
| الحالية | التحسين |
|---|---|
| `home/home_screen` | خريطة + لوحة حالة + عروض + شريط سفلي |
| `home/offer_card` | بطاقة عرض بصري أفضل + مؤقّت قبول + صوت |
| `home/active_trip_panel` | لوحة رحلة نشطة: معلومات الراكب + تنقّل + حالة |
| `documents/document_upload_screen` | رفع + حالة مراجعة |
| `earnings/earnings_screen` | أرباح يومية/أسبوعية + رسوم بيانية |
| `earnings/wallet_screen` | رصيد + سحب + سجل |
| `profile/settings_screen` | ملف الكابتن + إعدادات |
| `safety/sos_screen` | طوارئ |

### جديدة (مستوحاة من Uber Driver)
1. **`screens/home/demand_heatmap.dart`** — طبقة حرارة الطلب على الخريطة (مناطق عليها طلب مرتفع)
2. **`screens/home/online_toggle_card.dart`** — بطاقة الحالة (متصل/غير متصل) مع مؤقّت اليوم
3. **`screens/trips/trip_history_screen.dart`** — سجل رحلات الكابتن + فلترة
4. **`screens/earnings/daily_goals_screen.dart`** — أهداف يومية + شريط تقدّم + bonuses
5. **`screens/earnings/weekly_report_screen.dart`** — تقرير أسبوعي بياني
6. **`screens/profile/vehicle_settings_screen.dart`** — مركبات متعددة + وثائق + حالة
7. **`screens/profile/ratings_screen.dart`** — تقييمات الراكبين للكابتن + تعليقات
8. **`screens/notifications_screen.dart`** — مركز إشعارات الكابتن
9. **`widgets/offer_timer.dart`** — مؤقّت تنازلي لقبول العرض + اهتزاز
10. **`widgets/navigation_button.dart`** — زر "تنقّل" يفتح Google Maps/Waze بـ deep-link
11. **`widgets/rider_preview.dart`** — معاينة الراكب + تقييمه قبل القبول
12. **`widgets/earnings_today_widget.dart`** — بطاقة أرباح اليوم العائمة

---

## رابعًا: مكوّنات مشتركة جديدة في `packages/flutter_shared`

1. **`widgets/main_bottom_nav.dart`** — الشريط السفلي الموحّد (5 عناصر + زر وسط)
2. **`widgets/network_status_banner.dart`** — شريط حالة الشبكة
3. **`widgets/loading_overlay.dart`** — overlay تحميل شفاف
4. **`widgets/empty_state.dart`** — حالة فارغة موحّدة (أيقونة + نص + CTA)
5. **`widgets/error_state.dart`** — حالة خطأ موحّدة + إعادة محاولة
6. **`widgets/skeleton_loader.dart`** — هيكل تحميل بدل spinner
7. **`widgets/status_chip.dart`** — شارة حالة ملوّنة
8. **`models/notification.dart`** — نموذج الإشعارات
9. **`services/deep_link_service.dart`** — فتح Google Maps/Waze
10. **`services/audio_service.dart`** — أصوات تنبيه العروض

---

## خامسًا: تحسينات بصرية وتجربة (عامة)

1. **انتقالات صفحات** متّسقة (slideUp/fade) عبر `PageTransitionsTheme`
2. **Haptics** اهتزاز خفيف عند القبول/الوصول/الإكمال
3. **Skeleton loaders** بدل spinners في كل الشاشات
4. **Empty/Error states** عربية موحّدة في كل القوائم
5. **Pull-to-refresh** في History/Wallet/Earnings
6. **Snackbar موحّد** (نجاح/خطأ/تحذير) بالألوان الدلالية
7. **Map styling**: أزرار تكبير/تصغير عائمة + زر تحديد موقعي + إخفاء علامات iOS
8. **Live location sharing**: مؤشر كابتن متحرّك على الخريطة أثناء الرحلة (interpolation بين نقاط WS)
9. **Dynamic status bar**: لون يتكيّف مع الخريطة
10. **RTL/LTR** كامل + أرقام عربية في السياق المالي

---

## سادسًا: ترتيب التنفيذ (مراحل)

### المرحلة 1 — الأساس البصري (1-2 يوم)
1. `main_bottom_nav.dart` مشترك + زر وسط بارز
2. إعادة هيكلة Rider Home إلى MainShell + تبويبات
3. إعادة هيكلة Captain Home إلى MainShell + تبويبات
4. مكوّنات مشتركة: empty_state, error_state, skeleton, status_chip

### المرحلة 2 — تجربة الراكب (3-4 أيام)
5. `where_to_sheet` + بحث عناوين
6. `ride_options_sheet` (مركبة + دفع + برومو)
7. إعادة تصميم `trip_screen` بحالات متدرّجة
8. `rating_sheet` + `trip_detail_screen`
9. `payment_methods_screen` + `promo_screen`
10. `schedule_screen`

### المرحلة 3 — تجربة الكابتن (2-3 أيام)
11. `online_toggle_card` + `demand_heatmap`
12. تحسين `offer_card` + مؤقّت + صوت
13. تحسين `active_trip_panel` + زر تنقّل
14. `daily_goals` + `weekly_report`
15. `trip_history` + `ratings`

### المرحلة 4 — اللمسات النهائية (1-2 يوم)
16. `invite_screen` + `help_screen`
17. `notifications_screen` (كلاهما)
18. مركز مساعدة + FAQ
19. Haptics + انتقالات + skeleton في كل مكان
20. اختبار شامل + بناء release

---

## ملاحظات تنفيذية
- لا تغيير في الاستاك أو الـ API (كل الميزات لها endpoints جاهزة أو تُضاف لاحقًا)
- التحسينات التركيز على طبقة UI/UX فقط دون كسر المنطق الحالي
- كل مكوّن مشترك جديد في `packages/flutter_shared` ليُعاد استخدامه
- الحفاظ على الثيم الأبيض/الأسود + الأخضر #80B445 + RTL عربي
- كل النصوص الجديدة تُضاف لملفات ARB (ar + en)

---

هل أبدأ التنفيذ بالمرحلة 1 (الشريط السفلي + إعادة هيكلة Home)؟