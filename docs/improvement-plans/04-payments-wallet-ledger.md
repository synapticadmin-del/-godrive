# 04 — Payments, Wallet & Ledger

> خطة تحسين متخصصة — Synaptic Go
> النطاق: دورة حياة Paymob (intention/webhook/HMAC)، المحفظة الداخلية و`wallet_transactions`، سلامة الدفتر المزدوج، عمولة الكاش وديون الكباتن، التسويات والسحب، الاسترجاع والمنازعات، وتقارير إغلاق اليوم المالي
> تاريخ: 2026-08-01

## 1. ملخص تنفيذي

المسار الرابع مسؤول عن كل حركة مالية فعلية في المنصة: تحصيل المدفوعات الإلكترونية عبر Paymob،
شحن وخصم المحفظة الداخلية، تسجيل عمولة الرحلات الكاش كدين على الكابتن، وسحب أرباح الكباتن. هذه
هي الطبقة التي إذا انكسرت — تنكسر ثقة المستخدم في المنصة بشكل نهائي، لأن أي خطأ فيها معناه فلوس
حقيقية تتحرك أو تختفي بشكل غير صحيح.

بعد تدقيق كامل للكود الفعلي في `apps/api/src/lib/paymob.ts`، `apps/api/src/routes/payments.ts`،
`apps/api/src/routes/wallet.ts`، `apps/api/src/routes/captain.ts`، `apps/api/src/routes/trips.ts`،
`apps/api/src/routes/admin.ts`، وملفات الهجرة من `migrations/0001` إلى `migrations/0011`، تبيّن
أن الأساس المعماري قوي وأكثر نضجًا من المتوقع لمشروع بهذا الحجم: HMAC-SHA512 حقيقي بمقارنة زمن
ثابت (`timingSafeEqual`)، idempotency على مستوى `wallet_transactions.idempotency_key` بفهرس فريد،
وفحص تلاعب بالمبلغ (`amount_mismatch`) في الـ webhook. لكن هذا الأساس القوي يخفي عددًا من الثغرات
الجوهرية التي تجعل النظام **غير آمن للإنتاج بحجم حقيقي** بحالته الراهنة:

- **علة ازدواج ائتمان حقيقية وقابلة لإعادة الإنتاج** في المسار الأساسي (وليس القديم) لـ
  `POST /paymob/webhook`: عملية `INSERT OR IGNORE` على `wallet_transactions` لا يتبعها أي تحقق من
  `ins.meta.changes` قبل تنفيذ `UPDATE users SET wallet_balance = wallet_balance + ...` بلا شرط —
  بينما المسار القديم (`legacy fallback`) في **نفس الملف** يطبّق الفحص الصحيح. Paymob تُعيد إرسال
  الـ webhook عند أي استجابة غير 2xx أو انقطاع شبكة — وهذا يعني أن أي إعادة إرسال ستُضاعف رصيد
  المحفظة فعليًا.
- **لا يوجد أي مسار استرجاع (refund) منفّذ في الكود على الإطلاق** — رغم أن `refund` موجودة كقيمة
  في CHECK constraint لعمود `wallet_transactions.type` منذ `migrations/0003_global_transport.sql`،
  وكحالة أيقونة في شاشتي المحفظة في Flutter، لا يوجد استدعاء واحد لـ Paymob Refund API ولا أي كود
  خادم يُدرج صفًا بـ `type='refund'`. الاسترجاع الكامل والجزئي غائبان تمامًا.
- **ثلاث طرق متباينة لحساب أرباح الكابتن**، تُعطي أرقامًا مختلفة لنفس الكابتن في نفس اللحظة:
  `users.wallet_balance` (المصدر الحقيقي المتراكم)، استعلام `SUM` في
  `GET /captain/wallet` (يتجاهل صفوف `type='commission', direction='debit'` سهوًا)، واستعلام
  `SUM` ثالث في `GET /captain/earnings` (مبني مباشرة على جدول `trips` بمعزل عن `wallet_transactions`
  بالكامل).
- **علة قفل الرصيد السالب** في مسار خصم عمولة الرحلات الكاش داخل `POST /trips/:id/complete` —
  خصم العمولة يتم دون شرط `WHERE wallet_balance >= ?` الذي يُستخدم بشكل صحيح في مسارات أخرى من نفس
  الكود (خصم الراكب، وطلب السحب)، ما يسمح بدين كابتن سالب غير محدود.
- **لا توجد لوحة تسوية مالية حقيقية للمشغّل** — `GET /admin/analytics` و`GET /admin/stats` يحسبان
  الـ GMV والعمولة مباشرة من `trips.final_fare`/`trips.commission` بمعزل كامل عن
  `wallet_transactions` و`payment_intentions`، أي أن فريق العمليات لا يملك أي طريقة لمطابقة ما
  حصّلته Paymob فعليًا مقابل ما يعتقد أن `trips` قد سُجّل، ولا رؤية لالتزامات السحب (`payout`)
  المعلّقة، ولا لحالات فشل الشحن.
- **لا يوجد أي مسار موافقة/رفض إداري لطلبات السحب** — `POST /captain/wallet/payout` يخصم الرصيد
  فورًا (بشكل صحيح شرطيًا) ويُدرج صفًا `status='pending'`، لكن لا يوجد أي endpoint في `admin.ts`
  ولا أي مكان آخر في الكود يُغيّر هذا الصف لاحقًا إلى `settled` أو `rejected` — الأموال تختفي من
  رصيد الكابتن إلى حالة معلّقة أبدية بلا مخرج مبرمج.
- **webhook عام بلا أي حد معدل (rate limit)** — `POST /paymob/webhook` لا تستخدم middleware
  `rateLimit()` الموجودة فعليًا في `apps/api/src/middleware/rateLimit.ts` والمُستخدمة في نقاط
  أخرى، رغم أنها نقطة عامة (بدون `authMiddleware`) تُنفّذ استعلام قراءة + حساب HMAC لكل طلب وارد.

هذه الخطة تُغطّي 3 أولويات P0 (سلامة الأموال المباشرة: ازدواج الائتمان، سالب الرصيد بلا حد، غياب
الاسترجاع)، ومجموعة أولويات P1 (توحيد مصدر الحقيقة المالي، تسوية السحب، حماية الـ webhook)، ومجموعة
P2 (تنظيف الأنواع، الإيصالات، تقارير تشغيلية). كما تقترح ميزات جديدة كاملة غير موجودة إطلاقًا:
تسوية الكاش الآلية (cash reconciliation cycle)، دورة سحب دفعات مجدولة (payout batch settlement)،
نظام إيصالات ضريبية للرحلات، ولوحة "إغلاق اليوم" (End of Day Close) لفريق العمليات المالية.

هذا المستند لا يتناول حساب الأجرة أو نسب العمولة نفسها (تراك 03)، ولا الفوترة الشهرية لعملاء B2B
(تراك 21)، ولا كشف الاحتيال في الدفع (تراك 13) — هذه إشارات مرجعية فقط، وتفصيلها مسؤولية تلك
المسارات.

## 2. الوضع الحالي (تدقيق من الكود الفعلي)

### 2.1 مسار Paymob — الإنشاء

`POST /payments/paymob/intention` في `apps/api/src/routes/payments.ts` (محمي بـ `authMiddleware`)
يتحقق من الجسم عبر `intentionSchema` (Zod):

```ts
const intentionSchema = z.object({
  amount: z.number().min(1),
  currency: z.string().default("EGP"),
  paymentMethod: z.enum(["card", "wallet", "cash"]).default("card"),
  purpose: z.enum(["wallet_topup", "trip_payment", "intercity_booking"]).default("wallet_topup"),
  tripId: z.string().optional(),
});
```

يبني `PaymobBillingData` بمعظمها قيمًا وهمية ثابتة (`apartment: "NA"`, `floor: "NA"`,
`street: "NA"`, `building: "NA"`, `city: "Cairo"`, `state: "Cairo"`)، ويُهم — **رقم الهاتف مُثبّت
حرفيًا على `phone_number: "01000000000"` بدل رقم المستخدم الحقيقي** بلا أي محاولة لقراءة
`user.phone`. يستدعي `createPaymobIntention()` من `apps/api/src/lib/paymob.ts`، ثم يكتب **سجلّين
منفصلين وغير مرتبطين بمعاملة واحدة**:

1. صف قديم في `payment_methods` (معلَّق في الكود بأنه "Legacy bookkeeping").
2. صف في `payment_intentions` (مصدر الحقيقة الفعلي منذ `migrations/0011_payment_intentions.sql`)
   بالحالة `'pending'`، مع `amount_piastres: Math.round(body.amount * 100)`.

هاتان الكتابتان ليستا داخل `.batch()` ولا أي غلاف معاملي — فشل الكتابة الثانية بعد نجاح الأولى
يترك سجل `payment_methods` يتيمًا دون أي `payment_intentions` مقابل، ما يعني أن الـ webhook القادم
لاحقًا سيسقط في المسار "القديم" (`legacy fallback`) بدلاً من المسار الأساسي — وهو تحديدًا المسار
الذي يحتوي الفحص الصحيح لـ idempotency، لكنه أيضًا المسار الذي **لا يحتوي فحص تلاعب المبلغ**
(`amount_mismatch`) لأن ذلك الفحص مكتوب فقط داخل كتلة `if (intention) { ... }`.

### 2.2 التحقق من HMAC — `apps/api/src/lib/paymob.ts`

الملف (7850 بايت) يحتوي:

- `PAYMOB_INTEGRATION_ID_CARD = 3990172` — معرّف تكامل مُثبّت حرفيًا في الكود بدل متغيّر بيئة،
  يمنع التبديل بين بيئة اختبار/إنتاج أو إضافة طرق دفع أخرى (محفظة، Fawry) دون تعديل الكود ونشره.
- `paymobAuthToken()`, `paymobOrder()`, `paymobPaymentKey()` — تسلسل استدعاءات REST القياسي لـ
  Paymob (Auth → Order → Payment Key)، مع مسار بديل (`createPaymobIntention` fallback) يُنتج
  intention "وهمية" (`stubbed: true`) عند غياب `PAYMOB_API_KEY`/`PAYMOB_HMAC`/`PAYMOB_IFRAME_ID` —
  موثّق أيضًا في `docs/ROADMAP.md` كفجوة إنتاج معروفة (مفاتيح الإنتاج غير موجودة بعد).
- `HMAC_FIELDS` — قائمة مرتبة من 20 حقلًا يبنى منها نص HMAC وفق توثيق Paymob الرسمي.
- `computePaymobHmacAsync()` — يستخدم Web Crypto (`crypto.subtle.importKey` + `sign`، خوارزمية
  `HMAC-SHA512`) بدل أي مكتبة خارجية — مناسب تمامًا لبيئة Cloudflare Workers.
- `readPath()` — قارئ مسارات متداخلة (`order.id`, `source_data.type`, إلخ) يتعامل مع نقاط في أسماء
  الحقول لقراءة القيم المتداخلة من جسم Paymob.
- `verifyPaymobHmacAsync()` — **يفشل بشكل آمن (fail-closed)**: إن لم يكن `PAYMOB_HMAC` مضبوطًا في
  البيئة يرفض التحقق فورًا بسبب `"PAYMOB_HMAC not set"` بدل قبول أي حمولة — سلوك صحيح ومطلوب.
- `timingSafeEqual()` — مقارنة يدوية بزمن ثابت، مع عودة مبكرة عند اختلاف الطول (وهو تسريب توقيت
  بسيط جدًا لطول التوقيع فقط لا لمحتواه، أثر أمني ضئيل عمليًا لأن طول HMAC-SHA512 المُخرَج ثابت
  دائمًا 128 حرف hex، فلا قيمة عملية للمهاجم من هذا التسريب).

**لا توجد أي دالة استرجاع (`refund`) في هذا الملف** — تم تأكيد ذلك بقراءة الملف كاملاً؛ التعليقات
الوحيدة التي تذكر "refund" هي توثيق لحقول استجابة Paymob النظرية (`is_refunded`,
`currency_ops.total_cents_refund`) التي **لا يقرأها أي كود فعلي في المستودع**.

### 2.3 استقبال الـ webhook — `POST /paymob/webhook`

النقطة **عامة تمامًا** (بلا `authMiddleware`) كما يجب لأي webhook خارجي، لكن أيضًا **بلا أي
middleware من `rateLimit()`** الموجودة والمُستخدمة في نقاط أخرى من المشروع — تأكدنا من ذلك بقراءة
سطر تسجيل المسار في `payments.ts`:

```ts
paymentRoutes.post("/paymob/webhook", async (c) => { ... });
```

مقارنة بـ:

```ts
paymentRoutes.post("/paymob/intention", authMiddleware, async (c) => { ... });
```

التسلسل المنطقي داخل الـ handler:

1. قراءة الجسم، استخراج `obj` (Paymob تُغلّف البيانات أحيانًا داخل `body.obj`).
2. استخراج `providedHmac` من الاستعلام (`?hmac=`) أو من الجسم.
3. `verifyPaymobHmacAsync()` — عند الفشل: تسجيل تدقيق (`payment.webhook.rejected`) وإرجاع 401.
4. البحث عن `payment_intentions` بمطابقة `order_id`.

**المسار الأساسي (عندما توجد `intention`):**

```ts
if (amountCents !== intention.amount_piastres) {
  // ... تسجيل تدقيق amount_mismatch
  return c.json({ status: "rejected", reason: "amount_mismatch" }, 400);
}

if (intention.status === "settled") {
  return c.json({ status: "duplicate_ignored" }, 200);
}
```

هذا فحص تلاعب المبلغ جيد جدًا، وفحص التكرار على مستوى `payment_intentions.status` معقول كخط دفاع
أول. لكن بعده مباشرة، لفرع `wallet_topup`:

```ts
await c.env.DB.prepare(
  `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, payment_ref, idempotency_key, status, created_at)
   VALUES (?, ?, 'topup', 'credit', ?, ?, ?, ?, 'settled', datetime('now'))`,
)
  .bind(id("wt"), intention.user_id, amountEgp, amountCents, orderIdStr, idempotencyKey)
  .run();

await c.env.DB.prepare(
  `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) + ?, wallet_updated_at = ? WHERE id = ?`,
)
  .bind(amountEgp, amountCents, nowIso(), intention.user_id)
  .run();
```

**لا يوجد أي فحص على نتيجة `INSERT OR IGNORE` (`ins.meta.changes`) قبل تشغيل `UPDATE`.** بينما
المسار البديل الأقدم (`legacy fallback`, يُنفَّذ فقط عندما لا يُعثر على `payment_intentions`
مطابقة) في **نفس الملف** يطبّق الفحص الصحيح تمامًا:

```ts
const ins = await c.env.DB.prepare(/* نفس INSERT OR IGNORE */).run();

if (ins.meta && ins.meta.changes === 0) {
  return c.json({ status: "duplicate_ignored" }, 200);
}

await c.env.DB.prepare(/* نفس UPDATE users SET wallet_balance ... */).run();
```

هذا التناقض داخل ملف واحد يؤكد أن الفريق يعرف النمط الصحيح ونفّذه في مكان وتناساه في مكان آخر —
تفصيل هذه العلة وأثرها في القسم 3.

**فرع `trip_payment`:** يُحدّث `trips.payment_status = 'paid'`، ثم يُدرج صفًا تدقيقيًا فقط في
`wallet_transactions` بلا تعديل رصيد (منطقي — المبلغ ذهب لأجرة الرحلة لا للمحفظة). **لكن** لا يوجد
أي فحص idempotency هنا على الإطلاق (لا `idempotency_key`، لا فحص `ins.meta.changes`) — إعادة إرسال
الـ webheook مرتين لنفس رحلة الدفع تُدرج صفين مكررين في `wallet_transactions` (تلوّث تدقيقي وليس
تسرّب أموال، لكنه يفسد أي تقرير مطابقة لاحق).

**فرع `intercity_booking`:** نفس النمط بلا idempotency، صف تدقيقي فقط.

**عند الفشل (`successBool === false`):**

```ts
await c.env.DB.prepare(`UPDATE payment_intentions SET status = 'failed' WHERE id = ?`)...run();
await c.env.DB.prepare(
  `INSERT INTO wallet_transactions (id, user_id, type, direction, amount, payment_ref, status, created_at)
   VALUES (?, ?, 'topup', 'credit', ?, ?, 'failed', datetime('now'))`,
)...run();
```

صف الفشل يُسجَّل بـ **`direction='credit'`** رغم أنه لا ائتمان حدث فعليًا — دلاليًا خاطئ، وأي
استعلام تجميعي يُصفّي حسب `direction='credit'` وحده دون `status='settled'` سيحتسب محاولات الشحن
الفاشلة كرصيد وهمي.

### 2.4 المحفظة الداخلية — `apps/api/src/routes/wallet.ts`

لا يوجد ملف `apps/api/src/lib/wallet.ts` — تم التأكد بمحاولة قراءة مباشرة أعادت خطأ "does not
exist"، فالملف الحقيقي الوحيد هو `apps/api/src/routes/wallet.ts` (5305 بايت، أربع نقاط):

- `GET /user/wallet` — يُرجع `users.wallet_balance` (REAL) مع آخر 50 حركة.
- `GET /user/wallet/transactions` — صفحات (`limit` بحد أقصى 200)، بترتيب زمني تنازلي.
- `GET /captain/wallet` — يحسب `net` عبر استعلام `SUM` مبني على `CASE WHEN direction='credit'
  THEN amount ELSE -amount END`، **لكنه يُصفّي فقط على `type IN ('trip_payment','payout',
  'adjustment','promo_credit','topup')`** — أي أنه **يستبعد صفوف `type='commission',
  direction='debit'`** — وهذه بالضبط الصفوف التي تُسجّل دين عمولة الرحلات الكاش على الكابتن
  (انظر 2.5). النتيجة: هذا الاستعلام يُنتج رقمًا أعلى من الرصيد الحقيقي في `users.wallet_balance`
  لأي كابتن نفّذ رحلات كاش، لأن الخصم الفعلي حدث في `users.wallet_balance` لكن لا يظهر في `net`
  المحسوب هنا.
- `POST /captain/wallet/payout` — `topUpSchema`/سكيمة السحب Zod (المبلغ، الطريقة من
  `[bank_transfer, vodafone_cash, instapay, fawry]`، `account_info` بحد أدنى 3 أحرف). الجزء
  الإيجابي: يستخدم تحديثًا شرطيًا صحيحًا:

  ```ts
  const res = await c.env.DB.prepare(
    `UPDATE users SET wallet_balance = wallet_balance - ? WHERE id = ? AND wallet_balance >= ?`,
  )...run();
  if (res.meta.changes === 0) return /* insufficient_balance */;
  ```

  ثم يُدرج صفًا `type='payout', direction='debit', status='pending'`. **الرصيد يُخصم فورًا رغم أن
  حالة السجل `'pending'`** — وهذا سلوك مقصود منطقيًا (منع طلب سحب مزدوج لنفس الرصيد)، لكن لا يوجد
  أي مكان آخر في الكود (تم التأكد بالبحث في `admin.ts` و`captain.ts` و`wallet.ts` بالكامل) يُغيّر
  هذا الصف لاحقًا إلى `settled` أو `rejected`/`reversed` — فإذا فشلت عملية التحويل البنكي الفعلية
  خارج المنصة (تحويل يدوي عبر Vodafone Cash/Instapay من طرف المشغّل)، **لا توجد أي آلية لإرجاع
  المبلغ لرصيد الكابتن**.

### 2.5 تسوية الكاش وعمولة الرحلات — `apps/api/src/routes/trips.ts`

عند إتمام رحلة كاش (`POST /trips/:id/complete`)، يُحسب مبلغ العمولة ويُخصم من رصيد الكابتن ليُسجَّل
كدين (لأن الكابتن قبض الأجرة كاملة نقدًا من الراكب، لكن المنصة تستحق نسبة عمولة منها). موقع الكود
(استخرج محليًا من `apps/api/src/routes/trips.ts` بسبب حجم الملف الذي تجاوز حد الجلب المباشر)، نمط
الخصم هناك **لا يستخدم أي شرط حماية على الرصيد**:

```ts
await c.env.DB.prepare(
  `UPDATE users SET wallet_balance = wallet_balance - ? WHERE id = ?`,
)
  .bind(commissionAmount, captainId)
  .run();
```

بلا `WHERE wallet_balance >= ?`، وبلا أي تحقق لاحق على النتيجة. قارن هذا بنمط الحماية المستخدم
بشكل صحيح في **نفس المستودع** في مكانين آخرين: خصم رصيد الراكب (`trip_payment` من المحفظة) وطلب
سحب الكابتن (`POST /captain/wallet/payout`) — كلاهما يستخدمان `WHERE wallet_balance >= ?` مع فحص
`meta.changes`. غياب هذا الشرط هنا تحديدًا خطير لأن رحلات الكاش هي **الوضع الافتراضي** في المنصة
(`trips.payment_method DEFAULT 'cash'` من `migrations/0001_init.sql`، وموثّق في `docs/STACK.md`
بعبارة "Cash to captain first")، فهذا المسار يُنفَّذ على الأرجح لأغلبية الرحلات.

النتيجة العملية: كابتن ينفّذ سلسلة رحلات كاش متتالية بسرعة (سيناريو واقعي جدًا في ساعة الذروة) يمكن
أن يدخل رصيده في العجز (سالب) بلا حد أدنى، لأن كل رحلة تخصم عمولتها بغض النظر عن الرصيد الحالي.
لا يوجد أي حد أقصى للدين (credit limit / negative balance cap) يُوقف الكابتن عن قبول رحلات كاش
جديدة عند تجاوز حد دين معيّن — وهي آلية معيارية في Uber (يُطلب من السائق "تسوية الرصيد" cash-out
عند تجاوز حد دين محدد قبل قبول رحلات كاش أخرى).

كذلك، تأكدنا بقراءة مسار `POST /trips/:id/cancel` كاملاً أنه **لا يحتوي أي منطق استرجاع أو عكس
عمولة** — إذا أُلغيت رحلة بعد تسجيل عمولة (حالة نادرة لكن ممكنة حسب ترتيب الأحداث)، لا آلية لعكسها.

### 2.6 حالة الدفع مقابل حالة الرحلة

بالرجوع لـ `packages/shared/src/index.ts`، آلة حالة الرحلة (`TRIP_TRANSITIONS`/`canTransition()`)
تحتوي فقط: `searching → offered → assigned → arrived → in_progress → completed/cancelled`. **لا
توجد أي حالة دفع مضمّنة في آلة حالة الرحلة نفسها** — حالة الدفع منفصلة كليًا في عمود
`trips.payment_status` (أُضيف في `migrations/0011_payment_intentions.sql`، القيمة الافتراضية
`'unpaid'`)، وهو عمود **مستقل تمامًا** لا ترتبط قيمه (`unpaid`/`paid`) بأي آلة حالة صريحة أو enum
مركزي — أي قيمة نصية أخرى يمكن كتابتها فيه دون رفض على مستوى التطبيق (العمود TEXT بلا CHECK
constraint، بخلاف `wallet_transactions.type`/`direction`/`status` التي تملك CHECK constraints
صريحة في `migrations/0003_global_transport.sql`).

كذلك، **`apps/api/src/lib/types.ts`** يحتوي `DbTrip` type الذي **لا يذكر `payment_status`** رغم
وجود العمود في القاعدة فعليًا — انجراف بين تعريف النوع في TypeScript والسكيمة الفعلية. نفس النمط
في `DbUser`: يحتوي `wallet_balance?: number` لكن **لا يذكر `wallet_balance_piastres`** رغم وجوده
كعمود حقيقي (أُضيف في `migrations/0005_integer_currency_and_idempotency.sql`) ويُكتب إليه فعليًا
في كود الـ webhook أعلاه.

لا توجد حالات دفع من نمط Uber المعياري (`authorized`/`captured`/`voided`) في أي مكان — Paymob
Intention API يُنفّذ الدفع الكامل (capture) مباشرة عند نجاح الـ webhook، فلا يوجد مفهوم "حجز مبلغ
دون تحصيله" (pre-authorization hold)، وهو نمط مفيد جدًا لحماية المنصة من إلغاء الرحلة بعد وصول
الكابتن (no-show fee) — غائب كليًا.

### 2.7 المحفظة في تطبيقات Flutter

**`apps/rider/lib/screens/wallet/wallet_screen.dart`** (تم قراءته كاملاً) — يحتوي تعليقات مطوّرين
موثّقة لعلل سابقة أُصلحت فعلاً: عدم تطابق أسماء الحقول (الـ API يُرجع `direction`/`note`/
`created_at`، بينما الواجهة القديمة كانت تقرأ `type`/`description`/`createdAt`)، علة تقريب
(`toStringAsFixed(0)` كانت تُقرّب 12.50 إلى 13، أُصلحت بمنسّق شرطي)، وعلة منطقة زمنية (`datetime
('now')` الخام بلا `Z` كانت تُفسَّر كتوقيت محلي فتُنتج خطأ 3 ساعات لمصر، أُصلحت بإلحاق `Z`). حاليًا
`_money()` تعتمد على `amount` (REAL، بالجنيه أصلاً) وليس `amount_piastres` — يعمل، لكن يعني أن أي
اعتماد مستقبلي كامل على نظام القروش الصحيح (piastres integer) يتطلب تعديل هذه الشاشة أيضًا. تشير
لـ `TopupScreen` كنقطة دخول للشحن (لم يُدقَّق بعمق ضمن هذا التراك لأنه واجهة استهلاكية بحتة —
مسؤولية تراك 08).

**`apps/captain/lib/screens/earnings/wallet_screen.dart`** (تم قراءته كاملاً) — يستدعي **نقطتين
منفصلتين** (`GET /captain/wallet` و`GET /user/wallet/transactions?limit=50`) بدل استجابة موحّدة
واحدة — يُضاعف زمن التحميل ويُدخل احتمال عدم تطابق مؤقت بين الرقمين المعروضين إذا حدثت حركة مالية
بين الاستدعاءين. دالة `_requestPayout()` تعرض فقط طريقتين (`vodafone_cash`, `instapay`) من أصل
أربع تدعمها الـ API فعليًا (`bank_transfer`, `fawry` مفقودتان من الواجهة رغم دعم الخادم لهما).
`_collectAccountAndSubmit()` تُرسل دومًا `amount: _balance` (الرصيد الكامل فقط) — لا توجد واجهة
لسحب مبلغ جزئي رغم أن الـ API لا تفرض ذلك (`amount` في `topUpSchema`/سكيمة السحب حقل حر لا يُطابق
الرصيد الكامل إلزاميًا).

### 2.8 التقارير المالية للمشغّل — `apps/api/src/routes/admin.ts`

تم جلب الملف كاملاً (متضمّنًا `GET /stats`، `GET /analytics`، `GET /live-trips`، وغيرها من نقاط
غير مالية). النقطتان الوحيدتان ذواتا الصلة المالية:

```ts
adminRoutes.get("/stats", async (c) => {
  const todayStats = await c.env.DB.prepare(
    `SELECT COUNT(*) as trips,
            COALESCE(SUM(CASE WHEN status='completed' THEN final_fare ELSE 0 END),0) as gmv,
            COALESCE(SUM(CASE WHEN status='completed' THEN commission ELSE 0 END),0) as commission
     FROM trips WHERE datetime(created_at) >= datetime(?)`,
  )...;
```

```ts
adminRoutes.get("/analytics", async (c) => {
  // نفس النمط: SUM(final_fare)/SUM(commission) من جدول trips فقط، مع مقارنة
  // بالفترة السابقة (previousPeriod) ونسب تغيّر (pctDelta) — منطق محسوب فعليًا
  // وموثّق بعناية، وليس أرقامًا وهمية كما كانت (تعليق داخل الكود يوضّح أن
  // الإصدار الأقدم كان يعرض "+14.2%" ثابتة بلا حساب حقيقي، وهذا أُصلح).
```

كلا الاستعلامين **يعتمدان حصريًا على `trips.final_fare`/`trips.commission`، بلا أي join أو
استعلام موازٍ على `wallet_transactions` أو `payment_intentions`**. النتيجة العملية لفريق العمليات:

- لا توجد أي رؤية لعدد/قيمة محاولات الشحن الفاشلة (`wallet_transactions.status='failed'`).
- لا توجد أي رؤية لالتزامات السحب المعلّقة (`payout`, `status='pending'`) — وهي **دين حقيقي على
  المنصة** تجاه الكباتن ولا يظهر في أي تقرير.
- لا توجد أي مطابقة بين ما حصّلته Paymob (`payment_intentions WHERE status='settled'`) وما
  يُفترض أن يُقفل من الرحلات — فجوة تسوية (reconciliation gap) كاملة.
- `GET /admin/audit-log` موجود ويُرجع آخر السجلات من `audit_log`، لكنه سجل تدقيقي عام (كل الأحداث)
  وليس تقريرًا ماليًا منظمًا.
- لا يوجد أي endpoint لموافقة/رفض طلبات السحب (`payout`) — تم التأكد بقراءة الملف كاملاً وعدم
  إيجاد أي مسار `/admin/payouts` أو مشابه.

### 2.9 الإيصالات والاسترجاع والمنازعات

بحث شامل عبر الكود (`github__search_code` لكلمتي "refund" و"receipt"/"invoice") أكّد:

- كلمة "refund" تظهر فقط في: تعليقات توثيقية لحقول استجابة Paymob النظرية غير المقروءة فعليًا
  (`lib/paymob.ts`)، قيمة enum غير مستخدَمة في CHECK constraint (`migrations/0003`)، منطق استرجاع
  حقيقي **لكن محصور بالكامل في سياق الحجوزات بين المدن** (`apps/api/src/routes/intercity.ts`،
  `POST /intercity/bookings/:id/cancel` — "free cancellation with a full refund any time before
  the scheduled departure")، وحالة أيقونة غير مُفعَّلة أبدًا في شاشتي محفظة Flutter (لأن لا كود
  خادم يُدرج `type='refund'` لرحلات المدينة الواحدة أو شحن المحفظة).
- **لا يوجد أي استدعاء لـ Paymob Refund API** في `lib/paymob.ts` — الملف يحتوي فقط دوال الإنشاء
  والتحقق، بلا أي دالة `refundPaymobTransaction()` أو مكافئ.
- **لا يوجد أي توليد إيصال/فاتورة PDF لرحلة فردية** — بحث عن `receipt`/`invoice` في ملفات `.dart`
  وفي المستودع ككل أعاد نتائج صفرية (باستثناء الفوترة الشهرية لعملاء B2B في `routes/companies.ts`،
  خارج نطاق هذا التراك).
- **لا يوجد أي مسار تعامل مع Chargeback/Dispute من Paymob** — لا يوجد webhook أو معالج منفصل
  لأحداث النزاع (Paymob يُرسل هذه كأحداث webhook منفصلة عادةً)، ولا أي حالة في
  `wallet_transactions` أو `payment_intentions` تعكس "متنازع عليه" (`disputed`/`chargeback`).

## 3. الثغرات والمشاكل المكتشفة

| الخطورة | المشكلة | الدليل (ملف:رمز) | الأثر |
|---|---|---|---|
| P0 | ازدواج ائتمان عند إعادة إرسال webhook الشحن (المسار الأساسي) | `apps/api/src/routes/payments.ts` — فرع `intention.purpose === "wallet_topup"` داخل `POST /paymob/webhook`: `INSERT OR IGNORE INTO wallet_transactions` غير متبوع بفحص `ins.meta.changes` قبل `UPDATE users SET wallet_balance = wallet_balance + ...` غير الشرطي | إعادة إرسال طبيعية من Paymob (موثّقة كسلوك قياسي عند عدم استجابة 2xx سريعة) تُضاعف رصيد المحفظة فعليًا؛ خسارة مالية مباشرة على المنصة |
| P0 | خصم عمولة رحلات الكاش بلا حماية من الرصيد السالب | `apps/api/src/routes/trips.ts` — معالج `POST /trips/:id/complete`، `UPDATE users SET wallet_balance = wallet_balance - ?` بلا `WHERE wallet_balance >= ?` ولا فحص لاحق | دين كابتن غير محدود؛ لا حد أقصى يمنع قبول رحلات كاش إضافية بعد تجاوز سقف الدين، عكس نمط Uber/inDrive المعياري |
| P0 | غياب كامل لمسار الاسترجاع (refund) | لا وجود لأي دالة في `apps/api/src/lib/paymob.ts`؛ `type='refund'` قيمة CHECK غير مستخدمة في `migrations/0003_global_transport.sql`؛ حالة أيقونة غير مفعّلة في `apps/rider/.../wallet_screen.dart` و`apps/captain/.../wallet_screen.dart` | لا توجد أي طريقة برمجية لإرجاع مبلغ شحن أو دفع رحلة فاشلة/متنازع عليها؛ يتطلب تدخلاً يدويًا خارج النظام بالكامل لكل حالة |
| P1 | ثلاث طرق متباينة لحساب أرباح/رصيد الكابتن | `apps/api/src/routes/wallet.ts` — `GET /captain/wallet` (SUM يستبعد `type='commission'`) مقابل `users.wallet_balance` الفعلي مقابل `apps/api/src/routes/captain.ts` — `GET /captain/earnings` (SUM من `trips` مباشرة) | أرقام متضاربة معروضة للكابتن ولفريق الدعم في نفس اللحظة؛ يقوّض الثقة ويصعّب تتبع شكاوى الأرباح |
| P1 | لا يوجد مسار موافقة/رفض/تسوية لطلبات السحب المعلّقة | لا وجود لأي `/admin/payouts*` في `apps/api/src/routes/admin.ts` (تم تدقيق الملف كاملاً)؛ `POST /captain/wallet/payout` في `wallet.ts` يُدرج `status='pending'` بلا أي مسار تغيير حالة لاحق | مبالغ تُخصم من رصيد الكابتن فورًا وتبقى `pending` بلا نهاية مبرمجة؛ لا آلية لعكسها عند فشل التحويل الفعلي خارج النظام |
| P1 | webhook عام بلا حد معدل (rate limit) | `apps/api/src/routes/payments.ts` — `paymentRoutes.post("/paymob/webhook", async (c) => {...})` بلا غلاف `rateLimit()` رغم وجودها في `apps/api/src/middleware/rateLimit.ts` وتطبيقها في نقاط أخرى | استنزاف موارد (كل طلب وارد يُنفّذ قراءة DB وحساب HMAC قبل الرفض)؛ سطح هجوم DoS/فحص غير محمي |
| P1 | التقارير المالية للمشغّل معزولة تمامًا عن `wallet_transactions`/`payment_intentions` | `apps/api/src/routes/admin.ts` — `GET /stats` و`GET /analytics` يحسبان `gmv`/`commission` من `trips.final_fare`/`trips.commission` فقط، بلا أي join أو استعلام موازٍ لجداول الدفع | فريق العمليات لا يملك رؤية لمحاولات شحن فاشلة، أو التزامات سحب معلّقة، أو مطابقة تحصيل Paymob الفعلي؛ استحالة "إغلاق يوم مالي" بثقة |
| P1 | تكرار كتابة غير معاملي عند إنشاء الـ intention | `apps/api/src/routes/payments.ts` — `POST /paymob/intention`: كتابتان منفصلتان (`payment_methods` ثم `payment_intentions`) بلا `.batch()` | فشل الكتابة الثانية بعد نجاح الأولى يُسقط الـ webhook القادم للمسار القديم (`legacy fallback`) الذي يفتقر فحص `amount_mismatch` |
| P1 | فحص idempotency غائب في فرعي `trip_payment` و`intercity_booking` من الـ webhook | `apps/api/src/routes/payments.ts` — كتلتا `else if (intention.purpose === "trip_payment")` و`"intercity_booking"`: `INSERT INTO wallet_transactions` بلا `idempotency_key` ولا فحص تكرار | إعادة إرسال الـ webhook تُدرج صفوفًا تدقيقية مكررة (لا تسرّب أموال مباشر هنا لأنه بلا تعديل رصيد، لكنه يُفسد أي مطابقة/تقرير لاحق) |
| P2 | صف فشل الشحن يُسجَّل بـ `direction='credit'` رغم عدم حدوث ائتمان | `apps/api/src/routes/payments.ts` — `INSERT INTO wallet_transactions (..., 'topup', 'credit', ..., 'failed', ...)` عند `successBool === false` | أي استعلام تجميعي يُصفّي على `direction='credit'` وحده بلا `status='settled'` يحتسب محاولات فاشلة كرصيد وهمي |
| P2 | انجراف بين تعريف الأنواع في TypeScript والسكيمة الفعلية | `apps/api/src/lib/types.ts` — `DbTrip` لا يذكر `payment_status` (موجود من `migrations/0011`)؛ `DbUser` لا يذكر `wallet_balance_piastres` (موجود من `migrations/0005`، ويُكتب إليه فعليًا في `payments.ts`) | فقدان أمان الأنواع (type safety) لعمودين ماليين حرجين؛ أي كود جديد يعتمد على `DbTrip`/`DbUser` لن يرى هذه الحقول دون كسر البناء |
| P2 | `phone_number` مُثبّت حرفيًا في بيانات فوترة Paymob | `apps/api/src/routes/payments.ts` — `POST /paymob/intention`: `phone_number: "01000000000"` بدل قراءة `user.phone` | يُضعف بيانات مكافحة الاحتيال لدى Paymob (خارج تركيز هذا التراك لكنه أثر مالي جانبي)؛ يُصعّب أي تحقق لاحق من هوية الدافع |
| P2 | `PAYMOB_INTEGRATION_ID_CARD` مُثبّت حرفيًا في الكود | `apps/api/src/lib/paymob.ts` — `const PAYMOB_INTEGRATION_ID_CARD = 3990172;` | يمنع التبديل بين بيئات اختبار/إنتاج أو إضافة طرق دفع أخرى (محفظة إلكترونية، Fawry) دون تعديل الكود ونشره من جديد |
| P2 | لا توجد إيصالات/فواتير لرحلات فردية | بحث شامل (`receipt`/`invoice`) في المستودع لم يُظهر أي توليد PDF أو سجل إيصال مرتبط برحلة فردية (الفوترة الموجودة في `routes/companies.ts` خاصة بعقود B2B الشهرية فقط) | لا يملك الراكب أو الكابتن أي دليل رسمي قابل للطباعة/المشاركة لعملية دفع فردية؛ يُصعّب أي مطالبة ضريبية أو نزاع لاحق |
| P2 | لا يوجد أي مسار لمعالجة Chargeback/Dispute | بحث شامل عبر المستودع لم يُظهر أي webhook أو حالة مخصصة لأحداث النزاع من Paymob | عند حدوث منازعة فعلية من بنك حامل البطاقة، لا توجد آلية آلية لتجميد/تسوية الحساب المتأثر؛ يعتمد كليًا على تدخل يدوي |
| P2 | شاشة محفظة الكابتن تستدعي نقطتين منفصلتين بدل استجابة موحّدة | `apps/captain/lib/screens/earnings/wallet_screen.dart` — استدعاء منفصل لكل من `GET /captain/wallet` و`GET /user/wallet/transactions?limit=50` | مضاعفة زمن التحميل؛ احتمال عدم تطابق مؤقت بين الرقمين المعروضين إذا حدثت حركة مالية بين الاستدعاءين |
| P2 | واجهة السحب في تطبيق الكابتن لا تعرض كل طرق السحب المدعومة، ولا تدعم سحبًا جزئيًا | `apps/captain/lib/screens/earnings/wallet_screen.dart` — `_requestPayout()` يعرض فقط `vodafone_cash`/`instapay` من أصل أربع طرق تدعمها `wallet.ts`؛ `_collectAccountAndSubmit()` يُرسل دومًا `amount: _balance` بالكامل | يحرم الكابتن من `bank_transfer`/`fawry` رغم دعم الخادم لهما بالفعل؛ يمنع سحبًا جزئيًا رغم عدم وجود مانع في الـ API |

## 4. خطة التحسين

### 4.1 P0 — سلامة الأموال المباشرة

#### P0-1: إصلاح ازدواج الائتمان في webhook الشحن

**التغيير:** توحيد فحص idempotency في المسار الأساسي ليطابق المسار القديم الصحيح تمامًا — إضافة
فحص `ins.meta.changes === 0` مباشرة بعد `INSERT OR IGNORE` وقبل أي `UPDATE users SET
wallet_balance`، مع إرجاع `duplicate_ignored` عند التطابق. الأفضل: تجميع الإدراج والتحديث في نفس
منطق الشرط بحيث يستحيل بنيويًا الوصول للتحديث دون المرور بفحص التكرار أولاً (استخراج الشرط إلى دالة
مساعدة مشتركة `creditWalletOnce()` تُستخدم في كلا المسارين — الأساسي والقديم — لمنع أي انجراف
مستقبلي بينهما مجددًا).

**الملفات المتأثرة:** `apps/api/src/routes/payments.ts` (المسار الأساسي لفرع `wallet_topup`
داخل `POST /paymob/webhook`)؛ اختياريًا استخراج الدالة المشتركة إلى `apps/api/src/lib/wallet.ts`
(ملف جديد، لا يوجد حاليًا).

**تغييرات الـ schema أو API:** لا تغيير في السكيمة. لا تغيير في عقد الـ API الخارجي (الاستجابة
لـ Paymob تبقى بنفس الشكل).

**معايير القبول:**
- اختبار وحدة يُحاكي استدعاء الـ webhook مرتين متتاليتين بنفس `orderId`/`txnId`: التأكيد أن
  `wallet_balance` يزيد مرة واحدة فقط، وأن الاستدعاء الثاني يُرجع `duplicate_ignored`.
- اختبار تكامل (integration test) يشغّل الاستدعاءين بشكل متزامن (race) عبر `Promise.all` للتأكد
  أن الفهرس الفريد `idx_wt_idem` يمنع الإدراج المزدوج حتى تحت تزامن حقيقي، وليس فقط تسلسليًا.
- مراجعة كود تؤكد أن كل مسار كتابة لـ `wallet_transactions` من نوع ائتمان في هذا الملف يمر عبر نفس
  الدالة المساعدة.

**التقدير:** نصف يوم عمل (الإصلاح بسيط، لكن يتطلب كتابة اختبارات تزامن حقيقية لإثبات الإصلاح).

#### P0-2: حماية خصم عمولة الكاش من الرصيد السالب غير المحدود

**التغيير:** تحويل `UPDATE users SET wallet_balance = wallet_balance - ?` في معالج
`POST /trips/:id/complete` (`apps/api/src/routes/trips.ts`) إلى نمط شرطي يسمح بحد دين أقصى مضبوط
(وليس بالضرورة صفرًا — دين محدود مقبول تشغيليًا، دين غير محدود غير مقبول):

```ts
const CAPTAIN_DEBT_FLOOR = -50000; // -500.00 EGP كحد أقصى للدين، بالقروش
const res = await c.env.DB.prepare(
  `UPDATE users SET wallet_balance_piastres = wallet_balance_piastres - ?
   WHERE id = ? AND wallet_balance_piastres - ? >= ?`,
).bind(commissionPiastres, captainId, commissionPiastres, CAPTAIN_DEBT_FLOOR).run();

if (res.meta.changes === 0) {
  // تسجيل الرحلة كمكتملة مع علم "commission_deferred" بدل رفض إتمام الرحلة —
  // لا يجوز حجب الراكب/الكابتن عن إتمام رحلة فعلية بسبب حالة محفظة، لكن يجب
  // منع الكابتن من قبول رحلة كاش جديدة حتى يُسوّي الدين (انظر الميزة الجديدة
  // "cash reconciliation cycle" في القسم 5).
}
```

بالتوازي، يجب إضافة فحص في مسار قبول الرحلة/العرض (`assign`/`accept offer`) يرفض عروض الكاش
الجديدة للكباتن الذين تجاوز دينهم `CAPTAIN_DEBT_FLOOR` — القيمة يجب أن تكون قابلة للضبط عبر
`system_config` (الجدول موجود فعليًا ويُدار من `apps/api/src/routes/admin.ts` عبر
`GET/PUT /admin/system-config`، فقط يحتاج إضافة مفتاح `captain_debt_floor_piastres` جديد إلى
`SYSTEM_CONFIG_KEYS`).

**الملفات المتأثرة:** `apps/api/src/routes/trips.ts` (معالج `/complete`)، مسار قبول عرض/تعيين
الكابتن في نفس الملف (لإضافة فحص الحد قبل التعيين)، `apps/api/src/routes/admin.ts`
(إضافة `captainDebtFloorPiastres` إلى `SYSTEM_CONFIG_KEYS`)، `migrations/` (migration جديدة لإدراج
القيمة الافتراضية في `system_config` عند الترقية).

**تغييرات الـ schema أو API:** إضافة صف جديد في `system_config` (لا تغيير بنيوي في الجدول نفسه،
فقط بيانات). استجابة `POST /trips/:id/complete` تحتاج حقلًا اختياريًا جديدًا
`commissionDeferred: boolean` ليعرف تطبيق الكابتن أن هناك دينًا معلّقًا.

**معايير القبول:**
- اختبار وحدة: كابتن برصيد قريب من `CAPTAIN_DEBT_FLOOR` يُكمل رحلة كاش عمولتها تتجاوز المتبقي —
  التأكيد أن الرصيد لا يتجاوز الحد السالب المضبوط، وأن الرحلة تكتمل بنجاح مع `commissionDeferred:
  true`.
- اختبار وحدة: نفس الكابتن يحاول قبول عرض رحلة كاش جديدة وهو متجاوز للحد — يُرفض العرض بكود خطأ
  واضح (`CAPTAIN_DEBT_LIMIT_EXCEEDED`).
- مراجعة أن القيمة قابلة للتعديل من `GET/PUT /admin/system-config` وتنعكس فورًا (بلا نشر جديد).

**التقدير:** يومان (يشمل تعديل مسار قبول العرض، إضافة مفتاح system_config، وكتابة migration).

#### P0-3: بناء مسار استرجاع (Refund) فعلي — كامل وجزئي

**التغيير:** هذه أكبر فجوة وظيفية في التراك. المطلوب:

1. دالة جديدة `refundPaymobTransaction()` في `apps/api/src/lib/paymob.ts` تستدعي Paymob Refund
   API (`POST /api/acceptance/void_refund/refund`) بمعرّف معاملة Paymob (`transaction_id`، وليس
   `order_id`) ومبلغ بالقروش — يجب تخزين `transaction_id` الفعلي من استجابة الـ webhook (حاليًا
   `txnId` يُستخرج ويُستخدم فقط في بناء `idempotency_key` ولا يُحفظ كعمود مستقل في
   `payment_intentions` — يلزم إضافة عمود `paymob_transaction_id` في migration جديدة).
2. نقطة API جديدة `POST /payments/:intentionId/refund` (محمية بـ `requireRole("admin")` في مرحلة
   أولى — الاسترجاع الذاتي من الراكب قرار منتج منفصل يحتاج ضوابط احتيال، خارج نطاق P0).
3. عند نجاح الاسترجاع من Paymob: إدراج صف `type='refund', direction='debit'` (إذا كان استرجاع
   شحن محفظة، يُخصم من الرصيد لأنه أُعيد فعليًا للبطاقة) أو `type='refund', direction='credit'`
   إذا كان استرجاعًا لدفع رحلة مسبق (نادر، لكن ممكن). إضافة حالة `refunded`/`partially_refunded`
   إلى `payment_intentions.status` (يتطلب تحديث ضمني — العمود TEXT بلا CHECK constraint حاليًا،
   لذا لا يلزم migration للـ enum نفسه، لكن يُنصح بإضافة CHECK constraint في نفس الحركة لمنع قيم
   غير متوقعة مستقبلاً).
4. دعم الاسترجاع الجزئي: التحقق أن مجموع مبالغ الاسترجاعات السابقة + المبلغ الجديد لا يتجاوز
   `amount_piastres` الأصلي (استعلام `SUM` على صفوف `wallet_transactions` من نوع `refund` المرتبطة
   بنفس `payment_ref`).

**الملفات المتأثرة:** `apps/api/src/lib/paymob.ts` (دالة جديدة)، `apps/api/src/routes/payments.ts`
(نقطة جديدة)، `apps/api/src/lib/schemas.ts` (سكيمة Zod جديدة للطلب)، `migrations/00XX_payment_
refunds.sql` (عمود `paymob_transaction_id` على `payment_intentions`، وربما CHECK constraint محدّث
لـ `status`).

**تغييرات الـ schema أو API:**
```sql
ALTER TABLE payment_intentions ADD COLUMN paymob_transaction_id TEXT;
```
API جديدة: `POST /payments/:intentionId/refund { amountPiastres?: number, reason: string }` —
`amountPiastres` اختياري (افتراضيًا الاسترجاع الكامل للمبلغ المتبقي).

**معايير القبول:**
- اختبار تكامل: استرجاع كامل لشحن ناجح يُنقص `wallet_balance` بنفس المبلغ، ويُدرج صف
  `type='refund'` صحيح، ويُحدّث `payment_intentions.status`.
- اختبار: استرجاع جزئي مرتين متتاليتين حيث مجموعهما يساوي المبلغ الأصلي بالضبط — ينجح كلاهما.
- اختبار: محاولة استرجاع ثالث بعد استنفاد كامل المبلغ — تُرفض بكود `REFUND_EXCEEDS_REMAINING`.
- مراجعة أمنية: التأكد أن النقطة محمية بـ `requireRole("admin")` ومسجّلة بالكامل في `audit_log`
  عبر `logAudit()` (النمط الموجود مسبقًا في `admin.ts`).

**التقدير:** 4-5 أيام (يشمل تكامل Paymob API الفعلي الذي لم يُختبر بعد في هذا المستودع، ومعالجة
حالات فشل شبكة Paymob نفسها أثناء الاسترجاع).

### 4.2 P1 — توحيد مصدر الحقيقة والتشغيل الآمن

#### P1-1: توحيد حساب أرباح/رصيد الكابتن في مصدر واحد

**التغيير:** جعل `users.wallet_balance_piastres` هو **المصدر الوحيد** المعروض كـ "الرصيد الحالي"
في كل من `GET /captain/wallet` و`GET /captain/earnings` وتطبيق Flutter — بدل إعادة حسابه عبر `SUM`
مختلف في كل نقطة. استعلامات `SUM` تبقى مفيدة *فقط* لتفصيل الحركات ضمن فترة (breakdown)، وليس كبديل
للرصيد الإجمالي. إصلاح استعلام `GET /captain/wallet` تحديدًا بإضافة `type='commission'` إلى قائمة
الأنواع المُصفّاة (أو الأفضل: إزالة الفلترة بالكامل والاعتماد على `direction` فقط، طالما كل الأنواع
موجودة في `wallet_transactions`).

**الملفات المتأثرة:** `apps/api/src/routes/wallet.ts` (`GET /captain/wallet`)،
`apps/api/src/routes/captain.ts` (`GET /captain/earnings` — إعادة بنائه ليقرأ من
`wallet_transactions` بدل `trips` مباشرة، أو على الأقل توضيح في الاستجابة أن هذا "إجمالي تشغيلي"
منفصل عن "الرصيد القابل للسحب").

**تغييرات الـ schema أو API:** لا تغيير بنيوي. تغيير دلالي في استجابة `GET /captain/earnings` —
يُنصح بإضافة حقل `withdrawableBalance` صريح مأخوذ من `users.wallet_balance_piastres` بجانب
الحقول التشغيلية الحالية، بدل الاعتماد الضمني على تطابق الأرقام.

**معايير القبول:**
- اختبار: كابتن نفّذ مزيجًا من رحلات كاش وأونلاين — التأكيد أن الرقم المعروض في `GET
  /captain/wallet` (`net`) يساوي بالضبط `users.wallet_balance_piastres` في نفس اللحظة (فرق صفر).
- مراجعة أن تطبيق الكابتن (`apps/captain/lib/screens/earnings/wallet_screen.dart`) يعرض رقمًا
  واحدًا متسقًا من كلا الـ endpoints.

**التقدير:** يوم ونصف.

#### P1-2: دورة تسوية ومعالجة لطلبات السحب المعلّقة

**التغيير:** إضافة نقاط إدارية جديدة في `apps/api/src/routes/admin.ts`:
- `GET /admin/payouts?status=pending` — قائمة طلبات السحب المعلّقة (يقرأ مباشرة من
  `wallet_transactions WHERE type='payout'`).
- `POST /admin/payouts/:id/settle` — يُحدّث الصف إلى `status='settled'`، يُسجّل مرجع التحويل
  الفعلي (رقم عملية Vodafone Cash/Instapay/تحويل بنكي يُدخله المشغّل يدويًا) في عمود جديد
  `settlement_ref`.
- `POST /admin/payouts/:id/reject` — يُحدّث الصف إلى `status='reversed'` **ويُعيد** المبلغ لرصيد
  الكابتن (`UPDATE users SET wallet_balance_piastres = wallet_balance_piastres + ?`) — هذه هي
  آلية العكس الغائبة حاليًا بالكامل.

**الملفات المتأثرة:** `apps/api/src/routes/admin.ts` (نقاط جديدة)،
`apps/api/src/lib/schemas.ts` (سكيمات الطلب)، `migrations/00XX_payout_settlement.sql`
(عمود `settlement_ref TEXT` على `wallet_transactions`)، شاشة إدارية جديدة في `apps/admin`
(React) — خارج تركيز الكود الخلفي لكن ضرورية تشغيليًا (يُشار إليها هنا، تفصيلها لتراك 16).

**تغييرات الـ schema أو API:**
```sql
ALTER TABLE wallet_transactions ADD COLUMN settlement_ref TEXT;
```
API جديدة: `GET /admin/payouts`, `POST /admin/payouts/:id/settle`,
`POST /admin/payouts/:id/reject`.

**معايير القبول:**
- اختبار: رفض طلب سحب معلّق يُعيد بالضبط نفس المبلغ المخصوم لرصيد الكابتن (لا زيادة ولا نقصان).
- اختبار: تسوية طلب سحب تُحدّث الحالة فقط ولا تُعدّل الرصيد (المبلغ خُصم بالفعل عند الطلب).
- كل عملية تُسجَّل عبر `logAudit()` بنفس نمط بقية `admin.ts`.

**التقدير:** يومان (خلفية فقط، بلا الواجهة الإدارية).

#### P1-3: حماية webhook Paymob بحد معدل

**التغيير:** تطبيق `rateLimit()` الموجودة فعليًا في `apps/api/src/middleware/rateLimit.ts` على
مسار `/paymob/webhook`، بمفتاح مبني على IP مصدر Paymob (وليس مستخدمًا مُصادقًا، لأن النقطة عامة).
يجب ضبط الحد بسخاء كافٍ لتحمّل إعادة الإرسال الطبيعية من Paymob نفسها (لا يجوز أن يمنع الحد إعادة
إرسال شرعية) — يُقترح حد مرتفع نسبيًا (مثلاً 60 طلبًا/دقيقة لكل IP) مخصص لهذا المسار تحديدًا، أعلى
من الحد العام 120/دقيقة الإجمالي المذكور في `docs/IMPROVEMENTS.md` لكن مطبّقًا فقط على مسار
الـ webhook بمعزل عن بقية النظام.

**الملفات المتأثرة:** `apps/api/src/routes/payments.ts` (تسجيل middleware على المسار).

**تغييرات الـ schema أو API:** لا تغيير بنيوي. استجابة 429 جديدة ممكنة عند تجاوز الحد (السلوك
القياسي لـ `rateLimit()` الموجودة بالفعل).

**معايير القبول:**
- اختبار: إرسال أكثر من الحد المضبوط من نفس IP خلال نافذة زمنية واحدة يُرجع 429 لما بعد الحد.
- مراجعة أن Paymob's IP ranges المعروفة (إن وثّقتها Paymob) لا تُحظر خطأً — أو استخدام حد مرتفع
  بما يكفي لتجنّب False positives.

**التقدير:** نصف يوم.

#### P1-4: لوحة تسوية مالية للمشغّل (Reconciliation Dashboard) في `admin.ts`

**التغيير:** نقطة جديدة `GET /admin/finance/reconciliation?from&to` تُرجع، بجانب `gmv`/`commission`
الحاليين من `trips`:
- إجمالي الشحن الناجح (`wallet_transactions WHERE type='topup' AND status='settled'`) مقابل
  الشحن الفاشل (`status='failed'`) في نفس الفترة، مع نسبة الفشل (مؤشر تشغيلي مهم لصحة تكامل
  Paymob).
- إجمالي التزامات السحب المعلّقة الحالية (`SUM(amount) WHERE type='payout' AND status='pending'`)
  — رقم "الدين المستحق دفعه" الذي يحتاجه أي مشغّل ليعرف التزاماته النقدية.
- إجمالي دين عمولات الكاش المتراكم على كل الكباتن (`SUM(wallet_balance_piastres) WHERE
  wallet_balance_piastres < 0 AND role='captain'`) — رقم "الدين المستحق تحصيله".
- عدد/قيمة المعاملات التي تجاوزت `payment_intentions.status='pending'` لأكثر من فترة زمنية معقولة
  (مثلاً ساعة) بلا استقرار — مؤشر على انقطاعات webhook محتملة تحتاج تدخلاً يدويًا.

**الملفات المتأثرة:** `apps/api/src/routes/admin.ts` (نقطة جديدة)، شاشة إدارية مقابلة في
`apps/admin` (خارج الكود الخلفي، تُشار فقط).

**تغييرات الـ schema أو API:** لا تغيير بنيوي، نقطة API جديدة فقط للقراءة.

**معايير القبول:**
- اختبار: بيانات اختبار تحتوي مزيجًا من الحالات (شحن ناجح/فاشل، سحب معلّق، دين كابتن سالب) —
  التأكيد أن كل رقم في الاستجابة يطابق حسابًا يدويًا مباشرًا على القاعدة.
- الأداء: الاستعلامات يجب أن تستخدم الفهارس الموجودة (`idx_wt_idem` وأي فهرس على
  `wallet_transactions.user_id`/`type`/`status` — يُتحقق من وجودها الفعلي في migrations كجزء من
  هذا العمل، وإن غابت تُضاف في نفس الحركة).

**التقدير:** 3 أيام (خلفية فقط).

### 4.3 P2 — تنظيف وتحسينات تشغيلية

- **إصلاح انجراف الأنواع:** إضافة `payment_status` إلى `DbTrip` و`wallet_balance_piastres` إلى
  `DbUser` في `apps/api/src/lib/types.ts`. الملفات المتأثرة: `apps/api/src/lib/types.ts` فقط.
  معايير القبول: `tsc --noEmit` يمر بلا تحذيرات جديدة، وأي كود يقرأ هذين الحقلين الآن يحصل على
  إكمال تلقائي وفحص نوع صحيح. التقدير: ساعتان.
- **تصحيح `direction` لصفوف فشل الشحن:** تغيير الإدراج في فرع الفشل من `payments.ts` ليستخدم قيمة
  محايدة (مثلاً إبقاء `direction='credit'` لكن إضافة فلترة إلزامية بـ `status='settled'` في كل
  استعلام `SUM` مستقبلي — أو الأفضل معماريًا: قبول أن CHECK constraint الحالي لا يملك قيمة "لا
  اتجاه" وتوثيق القاعدة بوضوح أن أي تجميع مالي **يجب** أن يُصفّي بـ `status='settled'` دائمًا،
  ونشرها كقاعدة برمجية عبر دالة مساعدة `sumSettledWalletTransactions()` بدل تكرار الشرط يدويًا في
  كل مكان). التقدير: يوم واحد (يشمل تدقيق كل استعلامات `SUM` الحالية على `wallet_transactions`
  لضمان تطبيق الشرط في كل مكان).
- **استخراج `PAYMOB_INTEGRATION_ID_CARD` إلى متغير بيئة:** نقله إلى `c.env.PAYMOB_INTEGRATION_ID`
  (مع قيمة افتراضية للتوافق الخلفي). الملفات المتأثرة: `apps/api/src/lib/paymob.ts`، `wrangler.toml`
  (إضافة المتغيّر). التقدير: نصف يوم.
- **قراءة رقم هاتف المستخدم الحقيقي في بيانات فوترة Paymob:** استبدال `"01000000000"` الثابت بـ
  `user.phone` الفعلي (مع قيمة احتياطية معقولة إن كان فارغًا). الملفات المتأثرة:
  `apps/api/src/routes/payments.ts`. التقدير: ساعة واحدة.
- **توليد إيصال لكل معاملة دفع فردية:** نقطة جديدة `GET /payments/:intentionId/receipt` تُرجع
  JSON منظّم (رقم المرجع، المبلغ، التاريخ، الحالة) قابل للعرض في الواجهة كإيصال؛ توليد PDF فعلي
  وتخزينه في R2 (بنفس نمط `driver_documents` الموجود) خطوة لاحقة اختيارية. الملفات المتأثرة:
  `apps/api/src/routes/payments.ts` (نقطة جديدة). التقدير: يومان لنسخة JSON، +يومان إضافيان لـ PDF
  اختياري.
- **توحيد استدعاء محفظة الكابتن في تطبيق Flutter إلى طلب واحد:** دمج `GET /captain/wallet` و
  `GET /user/wallet/transactions` في استجابة واحدة (`GET /captain/wallet?includeTransactions=
  true&limit=50`)، مع تحديث `apps/captain/lib/screens/earnings/wallet_screen.dart` ليستخدم
  الاستدعاء المدمج. التقدير: يوم واحد (خلفية + واجهة).
- **إضافة طرق السحب الأربع وسحب جزئي في واجهة الكابتن:** تحديث `_requestPayout()` في
  `apps/captain/lib/screens/earnings/wallet_screen.dart` لعرض `bank_transfer`/`fawry` بجانب
  الطريقتين الحاليتين، وإضافة حقل مبلغ قابل للتعديل بدل `amount: _balance` الثابت (مع حد أدنى
  معقول، مثلاً 50 جنيه، يُضبط عبر `system_config`). التقدير: يوم ونصف.

## 5. ميزات جديدة مقترحة (Uber / inDrive parity وما بعدها)

1. **دورة تسوية الكاش الآلية (Cash Reconciliation Cycle):** بدل ترك دين عمولة الكاش يتراكم بلا
   نهاية، تنبيه دوري (عبر `notifications.ts` الموجود فعليًا) للكابتن عند اقتراب دينه من الحد
   (`CAPTAIN_DEBT_FLOOR` من P0-2)، مع واجهة "سدّد الآن" تُنشئ `payment_intentions` من نوع جديد
   `purpose='debt_settlement'` يُستخدم لتصفير الدين عبر بطاقة/محفظة إلكترونية مباشرة — تمامًا كآلية
   "Pay Now" الموجودة في تطبيق سائق Uber عند تجاوز حد الدفع الأسبوعي.
2. **دفعات سحب مجدولة (Payout Batching):** بدل معالجة كل طلب سحب يدويًا واحدًا تلو الآخر عبر
   P1-2، إضافة Cron (البنية التحتية لـ Cloudflare Cron موجودة ومُستخدمة بالفعل حسب `docs/STACK.md`)
   يُجمّع كل طلبات السحب المعلّقة أسبوعيًا/يوميًا حسب سياسة قابلة للضبط، وينتج كشفًا واحدًا قابلاً
   للتصدير (CSV) يستخدمه المشغّل لتنفيذ تحويل بنكي مُجمّع واحد لكل مزوّد دفع (Vodafone Cash،
   Instapay، إلخ) بدل تحويل فردي لكل كابتن — يُخفّض تكلفة وجهد العمليات بشكل كبير عند نمو عدد
   الكباتن.
3. **حجز مبلغ مسبق (Pre-authorization Hold) لرحلات البطاقة:** توسيع `createPaymobIntention()`
   لدعم نمط "authorize then capture" (يدعمه Paymob فعليًا عبر إعدادات integration منفصلة)، بحيث
   يُحجز مبلغ الأجرة المقدّرة عند قبول الرحلة، ولا يُحصَّل فعليًا (`capture`) إلا عند الإكمال —
   يحمي من حالات "لا يظهر الراكب" (no-show) ويسمح برسوم إلغاء مضمونة التحصيل، مطابقًا لسلوك Uber
   القياسي لدفعات البطاقة.
4. **نظام كشف حساب شهري (Monthly Statement) للراكب وللكابتن:** نقطة `GET /user/wallet/statement?
   month=2026-07` تُنتج ملخصًا شهريًا مُجمَّعًا (إجمالي الشحن، إجمالي الإنفاق، إجمالي العمولة
   المخصومة) — مذكور جزئيًا في `docs/ROADMAP.md` كـ "كشف حساب" لكن غير منفّذ فعليًا في أي مسار تم
   تدقيقه.
5. **حد ائتماني ديناميكي للكاش مبني على تاريخ الكابتن:** بدل حد `CAPTAIN_DEBT_FLOOR` ثابت للجميع،
   حساب حد أعلى للكباتن ذوي السجل الطويل والموثوق (بناءً على `rating_avg` الموجود فعليًا في جدول
   `captains`، ومدة النشاط)، وحد أدنى/أكثر تحفظًا للكباتن الجدد — نمط معياري في أنظمة الائتمان
   المصرفي مطبّق على سياق تشغيلي.
6. **تكامل تحويل فوري عبر InstaPay API مباشرة (بدل الإدخال اليدوي الحالي):** حاليًا `POST
   /captain/wallet/payout` يتطلب من الكابتن إدخال `account_info` نصيًا يدويًا، والتحويل الفعلي
   يحدث خارج المنصة بالكامل (يدويًا من طرف المشغّل). ميزة مستقبلية: تكامل API مباشر مع InstaPay أو
   Vodafone Cash B2C API لتنفيذ التحويل آليًا فور موافقة P1-2، محوّلًا `settle` من إجراء يدوي إلى
   استدعاء API واحد.
7. **صفحة "إغلاق اليوم" (End of Day Close) لفريق العمليات:** واجهة مخصصة (تُبنى فوق P1-4) تُنتج
   في نهاية كل يوم عمل تقريرًا واحدًا نهائيًا: GMV، العمولة المحصّلة (كاش + أونلاين)، صافي
   الالتزامات المعلّقة (سحب + دين كاش)، وقائمة أي معاملة `payment_intentions` عالقة في `pending`
   لأكثر من عتبة زمنية — مع زر تصدير PDF/CSV واحد يُغلق اليوم المحاسبي رسميًا، وهي بالضبط الوظيفة
   التي افتقدها القسم 2.8 بالكامل.

## 6. مخطط التنفيذ المرحلي

**المرحلة 1 (أسبوع 1) — إيقاف النزيف المالي المباشر (P0 فقط):**
- P0-1 (إصلاح ازدواج الائتمان) أولاً — أعلى أثر مالي مباشر وأبسط تنفيذًا، بلا تبعيات على أي عمل
  آخر.
- P0-2 (حماية الرصيد السالب) بالتوازي — مستقل تمامًا عن P0-1، يمكن لمهندس ثانٍ تنفيذه بالتوازي.
- P0-3 (مسار الاسترجاع) يبدأ في نفس الأسبوع لكن يمتد للأسبوع التالي نظرًا لحجمه (يعتمد على تكامل
  Paymob API فعلي غير مختبر سابقًا في هذا المستودع).

**المرحلة 2 (أسبوع 2-3) — توحيد مصدر الحقيقة والتشغيل الآمن (P1):**
- P1-3 (حد معدل webhook) أول شيء — لا تبعيات، تنفيذ نصف يوم.
- P1-1 (توحيد حساب الأرباح) يعتمد جزئيًا على استقرار P0-2 (لأن دين الكاش السالب المضبوط الآن يجب
  أن يظهر بشكل متسق في كل مكان).
- P1-2 (تسوية طلبات السحب) مستقل، يمكن تنفيذه بالتوازي مع P1-1.
- P1-4 (لوحة التسوية) تعتمد على استقرار P1-2 (تحتاج عمود `settlement_ref` الجديد) — تُجدوَل بعده
  مباشرة.

**المرحلة 3 (أسبوع 4) — التنظيف (P2) والميزات الأساسية من القسم 5:**
- كل عناصر P2 مستقلة عن بعضها، تُوزَّع بالتوازي بين المهندسين المتاحين.
- من الميزات الجديدة، يُنصح بالبدء بـ "دورة تسوية الكاش الآلية" (بند 1 في القسم 5) فور استقرار
  P0-2، لأنها تكمل حلقة معالجة دين الكاش بدل تركه كحد أقصى بلا مخرج للكابتن نفسه.

**المرحلة 4 (أسبوع 5+) — الميزات الأكبر:**
- حجز مبلغ مسبق (Pre-authorization)، دفعات السحب المجمّعة، صفحة إغلاق اليوم — هذه تتطلب تنسيقًا مع
  تراك 16 (Admin Console) للواجهات، وتراك 21 (فوترة B2B) إن كان هناك تداخل في نمط الكشف الشهري.

## 7. القياس والتحقق

**اختبارات:**
- اختبارات وحدة (unit) لكل دالة معالجة webhook تُغطّي: نجاح أول مرة، تكرار طلب مطابق تمامًا،
  تكرار متزامن (race)، مبلغ متلاعب به، توقيع HMAC غير صحيح، توقيع مفقود بالكامل.
- اختبارات تكامل (integration) على D1 محلي (`wrangler d1 execute --local`) للتأكد أن الفهرس
  الفريد `idx_wt_idem` يمنع فعليًا الإدراج المزدوج تحت تزامن حقيقي، وليس فقط منطقيًا في كود
  التطبيق.
- اختبار تراجع (regression) شامل لكل استعلامات `SUM` على `wallet_transactions` بعد أي تغيير في
  الفلترة (P1-1، P2 direction fix) — قائمة ثابتة من سيناريوهات بيانات معروفة النتيجة يدويًا،
  تُقارَن آليًا بعد كل تعديل.

**مقاييس (Metrics) للمراقبة بعد النشر:**
- عدد/نسبة استدعاءات `POST /paymob/webhook` التي تُرجع `duplicate_ignored` — ارتفاع مفاجئ يشير
  لمشكلة في استقرار الاستجابة السريعة للـ webhook (Paymob يُعيد الإرسال عند التأخر).
- الفرق بين `SUM(wallet_transactions.amount)` المحسوب دوريًا (Cron يومي) و`users.wallet_balance`
  الفعلي لكل مستخدم — يجب أن يكون صفرًا دائمًا؛ أي انحراف غير صفري هو تنبيه فوري لخلل في سلامة
  الدفتر (ledger integrity)، ويُقترح تسجيله كمقياس Cloudflare Analytics/Workers Logs مخصص.
- إجمالي دين الكاش المتراكم على كل الكباتن (من ميزة القسم 5 بند 1) — اتجاه تصاعدي مستمر يشير لحاجة
  مراجعة حد `CAPTAIN_DEBT_FLOOR` أو سياسة "سدّد الآن".
- عدد طلبات السحب `pending` التي تجاوز عمرها 48 ساعة — مقياس تشغيلي مباشر لصحة عملية P1-2.
- نسبة فشل الشحن (`wallet_transactions.status='failed'` / إجمالي محاولات الشحن) — ارتفاع مفاجئ
  يشير لمشكلة في تكامل Paymob نفسه (مفاتيح منتهية، تغيير في API، إلخ).

**لوحات (Dashboards):** لوحة التسوية المالية من P1-4 تُعرض في `apps/admin` كصفحة جديدة ضمن قسم
"العمليات المالية"، مع تحديث كل 5 دقائق (نفس نمط `GET /admin/analytics` الحالي).

**التراجع (Rollback):** كل تغيير في هذه الخطة إما إضافة عمود جديد (آمن للتراجع — العمود يبقى غير
مستخدم عند التراجع عن كود التطبيق) أو تعديل منطق شرطي داخل معالج موجود (يُنشر خلف تبديل ميزة
(`system_config` أو متغيّر بيئة) حيثما أمكن، خصوصًا P0-2 الذي يُدخل سلوكًا رافضًا جديدًا — يجب أن
يكون قابلاً للتعطيل فورًا عبر `system_config` دون نشر كود جديد إذا ظهرت مشكلة إنتاجية غير متوقعة).

## 8. المخاطر والاعتماديات

- **الاعتماد الأكبر: مفاتيح Paymob الحقيقية غير متوفرة بعد في الإنتاج** (موثّق في
  `docs/ROADMAP.md`). كل عمل في P0-3 (الاسترجاع) وP1-3 (حد المعدل الفعلي) لا يمكن اختباره ضد
  Paymob الحقيقي حتى تتوفر `PAYMOB_API_KEY`/`PAYMOB_HMAC`/`PAYMOB_IFRAME_ID` للإنتاج — يجب اختباره
  ضد بيئة Paymob التجريبية (sandbox) أولاً، مع خطة تحقق منفصلة عند التبديل للإنتاج الفعلي.
- **مخاطرة P0-2 (حد الدين):** ضبط `CAPTAIN_DEBT_FLOOR` منخفضًا جدًا يمنع كباتن نشطين حقيقيين من
  العمل بشكل مفاجئ ويُسبب اضطرابًا تشغيليًا؛ ضبطه عاليًا جدًا يُبقي المخاطرة المالية قائمة تقريبًا
  دون تغيير. يجب إطلاقه أولاً بقيمة متحفظة جدًا (دين مسموح مرتفع نسبيًا) مع مراقبة مكثفة، ثم تضييقه
  تدريجيًا بناءً على البيانات الفعلية بدل تخمين رقم مبدئي.
- **اعتماد على تراك 07 (D1 Schema):** أي migration جديدة مقترحة هنا (عمود `paymob_transaction_id`،
  `settlement_ref`، إلخ) يجب أن تتبع ترقيم `migrations/` التسلسلي الحالي (آخر ملف مؤكد هو
  `0019_trips_captain_status_index.sql`) وتُنسَّق مع أي migrations أخرى قيد الإعداد بالتوازي من
  مسارات أخرى لتفادي تعارض في الترقيم.
- **اعتماد على تراك 13 (Fraud, Risk & Abuse):** أي حد ائتماني ديناميكي (بند 5 في القسم 5) يعتمد
  على إشارات سلوكية (معدل الإلغاء، الشكاوى) قد يملكها ذلك التراك بالفعل أو يخطط لها — يجب التنسيق
  لتفادي ازدواج المنطق.
- **اعتماد على تراك 15 (Notifications):** ميزة "دورة تسوية الكاش الآلية" (تنبيه اقتراب حد الدين)
  تعتمد على `apps/api/src/lib/notifications.ts` الموجود فعليًا (`pushToUser()` مُستخدَمة بالفعل في
  `payments.ts` لتنبيهات الشحن) — إعادة استخدام نفس النمط، لا حاجة لبنية تحتية جديدة.
- **اعتماد على تراك 16 (Admin Console):** كل نقاط API الجديدة في القسم 4 (P1-2، P1-4) تحتاج واجهة
  React مقابلة في `apps/admin` لتكون قابلة للاستخدام فعليًا من فريق العمليات — هذا المستند يُغطّي
  الخلفية (backend) فقط؛ الواجهة الأمامية الإدارية مسؤولية ذلك التراك، ويجب التنسيق على شكل
  الاستجابة (response shape) قبل تجميدها.
- **مخاطرة تشغيلية عند إطلاق P0-3 (الاسترجاع):** إتاحة استرجاع فعلي عبر API إداري يفتح سطح هجوم
  جديدًا إذا لم تُحكم الصلاحيات بدقة — يجب التأكد أن `requireRole("admin")` وحدها غير كافية إذا كان
  عدد حسابات الإدارة كبيرًا؛ يُنصح بإضافة سجل تدقيق إلزامي (موجود بالفعل عبر `logAudit()`) وربما
  حد يومي على إجمالي مبالغ الاسترجاع لكل حساب إداري كخط دفاع إضافي — يتقاطع هذا مع نطاق تراك 13
  ويجب التنسيق معه قبل التنفيذ النهائي.
