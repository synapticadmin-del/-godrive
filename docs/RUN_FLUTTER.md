# تشغيل تطبيقات Flutter — Synaptic Go

## جاهزية الجهاز
- Flutter: `C:\Users\kayf\flutter-sdk\flutter`
- Android Studio + SDK: جاهزين
- API المنشور: `https://api.synapticstudio.tech`

## ملاحظة مهمة عن المسار العربي
Gradle على ويندوز قد يفشل مع مجلد اسمه عربي (`تطبيق التوصيل`).

**الحل الموصى به للبناء/التشغيل:**
استخدم النسخة على مسار إنجليزي:
```
C:\Users\kayf\synaptic-go\rider\rider
C:\Users\kayf\synaptic-go\captain\captain
```

أو انقل/انسخ المشروع إلى:
```
C:\dev\synaptic-go
```

## APKs جاهزة للتجربة الآن
على سطح المكتب:
```
C:\Users\kayf\Desktop\SynapticGo-APKs\synaptic-go-rider-debug.apk
C:\Users\kayf\Desktop\SynapticGo-APKs\synaptic-go-captain-debug.apk
```

ثبّتهم على الموبايل/الإيموليتر:
```bash
adb install -r "C:\Users\kayf\Desktop\SynapticGo-APKs\synaptic-go-rider-debug.apk"
adb install -r "C:\Users\kayf\Desktop\SynapticGo-APKs\synaptic-go-captain-debug.apk"
```

## تشغيل من المصدر (Android)

أضف Flutter للـ PATH في الجلسة:
```bash
set PATH=C:\Users\kayf\flutter-sdk\flutter\bin;%PATH%
```

### تطبيق العميل
```bash
cd C:\Users\kayf\synaptic-go\rider\rider
flutter pub get
flutter run
```

### تطبيق الكابتن
```bash
cd C:\Users\kayf\synaptic-go\captain\captain
flutter pub get
flutter run
```

## سيناريو اختبار كامل
1. افتح Admin: https://synaptic-go-admin.pages.dev
2. ادخل بـ `admin@synapticstudio.tech` (OTP يظهر في وضع DEV)
3. من تطبيق الكابتن: سجّل → املأ بيانات السيارة
4. من Admin: وافق على الكابتن
5. الكابتن: Online
6. الراكب: اطلب رحلة
7. الكابتن: قبول → وصل → بدء → إنهاء
8. الراكب: تقييم

## API Base URL
التطبيقات متصلة حاليًا بـ:
`https://api.synapticstudio.tech`

للتطوير المحلي غيّر في:
- `lib/services/app_state.dart`
