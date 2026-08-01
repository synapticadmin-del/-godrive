# 06 — Realtime Infrastructure (Durable Objects & WebSockets)

> خطة تحسين متخصصة — Synaptic Go
> النطاق: طبقة النقل الحي — `TripRoom` / `GeoCell` / `CaptainInbox` Durable Objects، دورة حياة اتصالات الـ WebSocket، بث الموقع، وضمانات الترتيب/التسليم
> تاريخ: 2026-08-01

## 1. ملخص تنفيذي

الـ realtime layer في Synaptic Go شغّالة فعليًا — مش prototype. عندنا 4 Durable Objects (`TripRoom`, `GeoCell`, `CaptainInbox`, `OfferScheduler`) كلها SQLite-backed (hibernatable) حسب `apps/api/wrangler.toml`، وعندنا 3 عملاء WebSocket في Flutter (`apps/rider/lib/services/trip_ws.dart`, `apps/captain/lib/services/offers_ws.dart`, `apps/captain/lib/services/trip_ws.dart`) بنفس نمط الـ backoff والـ heartbeat. فيه تعليقات كود ممتازة (خصوصًا في `TripRoom.ts`) بتشرح قرارات هندسية دقيقة زي سبب استخدام `idFromName` بدل `ctx.id.toString()`. المستوى التقني للفريق اللي كتب الكود ده عالي.

لكن اللي بنيته هنا هو نظام **"live view" وليس نظام تسليم مضمون**. مفيش أي رقم تسلسلي (sequence number) على أي حدث بيتبعت من السيرفر — لا في `TripRoom.broadcast()`، ولا في `trip_events` (الـ schema فيها `id, trip_id, actor_id, type, payload, created_at` من غير عمود `seq`)، ولا في `trip_path_points`. لو الاتصال اتقطع لحظة وحصل حدث فيها (مثلاً `trip.cancelled` أو `location.captain`)، الراكب أو الكابتن **مش هيعرف إنه فاته حاجة** لحد ما حدث تاني يوصل، أو أسوأ من كده — ممكن ميوصلش أي حدث تاني لو كانت دي آخر حالة (مثال: trip اتلغت والطرفين فاتحين سوكيت ميت). الـ reconnect logic بترجع تفتح سوكيت جديد وتستنى event جديد — مفيش "replay من آخر نقطة معروفة".

بالإضافة لكده، فيه فئة كاملة من الـ bugs معروفة ومكتوب عنها في تعليقات الكود نفسه (id-derivation bug في `TripRoom.resolveTripId()`) وده مؤشر إن الفريق داس على المشكلة دي قبل كده وحلّها جزئيًا لكن السبب الجذري (استخدام DO name كـ business key) لسه قائم ولازم معالجة بنيوية مش ترقيع.

**أكتر 3 لقطات خطيرة:**

1. **مفيش idempotency ولا sequence أي حدث حي** — `TripRoom.broadcast()`, `trip_path_points`, و `trip_events` كلها من غير رقم ترتيب أو مفتاح تكرار. أي إعادة إرسال (retry) من الكابتن أو السيرفر ممكن تتكرر أو تتفقد من غير ما حد يلاحظ.
2. **`GeoCell.nearby()` بتعمل full unbounded scan** (`storage.list<CaptainPresence>({prefix:"captain:"})`) من غير حد أعلى، وفيه تعارض في نافذة الـ staleness: الاستعلام بيعتبر الكابتن "طازة" لغاية دقيقتين لكن التنظيف (`alarm()`) بيمسحه بعد 3 دقايق — يعني فيه نافذة دقيقة كاملة ممكن كابتن يظهر "قريب" وهو أوفلاين فعليًا.
3. **`captain_state.dart`: `pushLocationCoordinates()` بتبلع كل الأخطاء `catch (_) {}`** من غير أي retry queue أو تخزين مؤقت أوفلاين — يعني في أي شبكة ضعيفة (سيناريو شائع جدًا في مصر) الموقع يضيع بصمت والراكب يشوف الكابتن "واقف" على الخريطة.

الخطة دي بتغطي 8 P0، مجموعة P1 وP2 لبناء نظام تسليم موثوق (sequence numbers + replay buffer)، تحسين تكلفة وكفاءة الـ DOs (خصوصًا `CaptainInbox` proxy pattern اللي بيكلف DO instance مزدوجة)، وميزات جديدة (dead-reckoning، presence دقيق، admin live map موحّد) للوصول لمستوى Uber/inDrive في القوة والاعتمادية.

## 2. الوضع الحالي (تدقيق من الكود الفعلي)

### 2.1 الـ Durable Objects الأربعة

كل الـ DOs مسجلة في `apps/api/wrangler.toml`:

```toml
[durable_objects]
bindings = [
  { name = "TRIP_ROOM", class_name = "TripRoom" },
  { name = "GEO_CELL", class_name = "GeoCell" },
  { name = "CAPTAIN_INBOX", class_name = "CaptainInbox" },
  { name = "OFFER_SCHEDULER", class_name = "OfferScheduler" },
]
```

وبناءً على `[[migrations]]`:

```
v1: new_sqlite_classes = ["TripRoom", "GeoCell"]
v2: new_sqlite_classes = ["CaptainInbox"]
v3: new_sqlite_classes = ["OfferScheduler"]
```

الأربعة كلهم **SQLite-backed** — يعني بيدعموا الـ hibernation API (`ctx.acceptWebSocket`, `webSocketMessage`, `webSocketClose`, `webSocketError`, `ctx.getWebSockets()`) بدل النمط القديم اللي بيفضل الـ isolate live طول ما فيه socket مفتوح (وده بيكلف compute time حتى وقت الـ idle). `compatibility_date = "2025-04-01"` مع `compatibility_flags = ["nodejs_compat"]`.

#### `TripRoom` — `apps/api/src/durable-objects/TripRoom.ts`

الـ instance واحدة لكل رحلة، الاسم هو `tripId` (مثل `trip_<32hex>` من `lib/utils.ts: id("trip_")`). مسؤولة عن:

- بث state الرحلة الحي (`type: "trip.updated"`, `type: "location.captain"`) للراكب والكابتن.
- تخزين `lastLocation` في `ctx.storage` عشان أي عميل يتصل متأخر ياخد آخر موقع فورًا.
- الـ auth handshake: إما الـ Worker يبعت `role`/`userId` مباشرة (بعد التحقق من JWT في `index.ts`)، أو (لو مفيش token واضح) يبعت `pendingAuth=1` والعميل لازم يبعت `{"type":"auth","token":"<jwt>"}` كأول رسالة خلال `AUTH_TIMEOUT_MS = 10_000`.

أهم جزء تقني هنا هو `resolveTripId()`، وتعليق الكود بيشرح بالظبط الـ bug class:

> "Deliberately NOT `ctx.id.toString()`: that returns the 64-hex DurableObjectId, never the name passed to `idFromName(tripId)`, because `idFromName` is one-way. Trip ids look like `trip_<32 hex>` (lib/utils.ts `id()`), so a D1 lookup keyed on the hex id matches no row — which is what made every first-message auth handshake fail closed with 4401 and left riders with no live socket for the whole trip."

ترتيب الحل الحالي: `?tripId=` query param (authoritative) → `ctx.storage` (بيعيش بعد الـ hibernation) → `ctx.id.name` (متاح بس على compatibility dates أحدث) → hex id كـ fallback أخير (يعني ممكن يفشل بصمت لو الطريقين التانيين مش متوفرين).

`fetch()` بتتعامل مع: `POST /broadcast`, `GET /state`, `PUT /state` (وكمان بتنادي `resolveTripId(body.id)` بشكل انتهازي هنا)، وWebSocket upgrade.

`webSocketMessage()`: السيشنز اللي لسه `pendingAuth` بس بتقبل `{"type":"auth"}`؛ غير كده بتتعامل مع `ping`→`pong` و`{"type":"location", lat, lng, heading}` واللي بتتخزن في `ctx.storage.put("lastLocation", payload)` وتتبث كـ `location.captain` لكل السوكيتات التانية.

`broadcast()` بتعمل loop على `this.sessions` (Map محلي) **و** `this.ctx.getWebSockets()` (الـ hibernation API) مع منطق لتفادي العدّ المزدوج — نقطة تنفيذ دقيقة لكنها معقدة وعرضة لأخطاء مستقبلية لو حد ضاف مصدر سيشنز تالت.

#### `GeoCell` — `apps/api/src/durable-objects/GeoCell.ts`

Instance واحدة لكل geohash cell (دقة 5، تقريبًا 4.9×4.9 كم)، الاسم مبني من `cellKey(city, lat, lng, precision=5)` في `apps/api/src/lib/pricing.ts`. بتخزن `CaptainPresence { userId, lat, lng, lastSeen, name? }` تحت مفتاح `captain:{userId}`.

- `/heartbeat`: تخزين presence + تسليح alarm بعد 60 ثانية (بس لو `currentAlarm == null` — يعني مفيش إعادة تسليح لو فيه واحدة شغالة أصلًا).
- `/offline`: مسح المفتاح فورًا.
- `/nearby`: **full scan** `storage.list<CaptainPresence>({prefix:"captain:"})` من غير أي حد أعلى، فلترة بعمر أقصى `maxAgeMs` (افتراضي 120000 = دقيقتين)، حساب haversine لكل entry، ترتيب، وقص لـ `limit` (افتراضي 10).
- `alarm()`: مسح كل الـ entries اللي `now - lastSeen > 180_000` (3 دقايق)، إعادة تسليح بس لو فاضل entries.

**التعارض:** `/nearby` بيعتبر الكابتن صالح لغاية دقيقتين، لكن التنظيف مش بيمسحه إلا بعد 3 دقايق — نافذة دقيقة كاملة (بين 2 و3 دقايق) الكابتن يفضل "موجود" في نتائج `/nearby` رغم إنه فعليًا outdated (لو الكود بيفلتر صح على `maxAgeMs`، ده مش bug تسليم خاطئ، لكنه معناه الـ storage نفسه بيحتفظ بـ stale entries لفترة أطول من اللازم — تكلفة تخزين + قراءة زيادة).

#### `CaptainInbox` — `apps/api/src/durable-objects/CaptainInbox.ts`

Instance واحدة لكل كابتن (الاسم = `userId`)، بتستقبل عروض الرحلات (`trip.offer`) وتحديثات (`trip.assigned`, `trip.cancelled`). فيها نمط **proxy مزدوج** غير معتاد:

> "When no token is supplied the route instead forwards to a well-known 'pending-auth' inbox instance with `?pendingAuth=1`; the client must then send `{"type":"auth","token":"<jwt>"}` as its first message... On success this instance proxies the socket pair through to the captain's real inbox."

يعني: كابتن يفتح سوكيت من غير `Authorization` header → الطلب يوصل لـ instance اسمها الحرفي `"pending-auth"` (well-known/shared بين كل الكباتن غير الموثقين لحظيًا) → بعد نجاح الـ auth، الـ instance دي تفتح WebSocketPair جوّاني تاني وتعمل `fetch` لـ `CAPTAIN_INBOX.get(idFromName(user.id))` (الـ instance الحقيقية بتاعة الكابتن) وتربط الاتنين ببعض عن طريق event listeners بيعملوا forward للرسايل في الاتجاهين (`session.relay`).

هذا معناه: **كل اتصال بدون token مباشر يكلف 2 DO instance فعّالة طول عمر الاتصال، وكل رسالة تعدي مرتين (hop مزدوج)**. الطريق الوحيد اللي بيتفادى ده هو التوكن المباشر عبر `Authorization` header في `index.ts`.

#### `OfferScheduler` — `apps/api/src/durable-objects/OfferScheduler.ts` (ملف إضافي داخل النطاق)

مش مذكور صراحة في الـ scope بتاعي، لكنه موجود تحت `durable-objects/` وبالتالي دورة حياته (lifecycle/alarm/storage) داخلة في تدقيقي — منطق الـ matching نفسه (مين يتختار) خارج نطاقي (track 02).

بينفذ نمط "wave dispatch": `WAVE_SIZE = 3`, `WAVE_DELAY_MS = 15_000`. `/schedule` بيخزن `tripId`, `captains[]`, `offer`, `waveIndex=0` وينادي `pushWave()`. `pushWave()` بيبعت الموجة الحالية لكل كباتنها عبر `CAPTAIN_INBOX` DOs بالتوازي (`Promise.all`, best-effort لكل كابتن)، بيسلّح alarm للموجة الجاية أو يعمل `teardown()` لو خلص. `alarm()` بيعيد قراءة حالة الرحلة من D1 قبل ما يبعت الموجة الجاية — بيوقف لو الحالة خرجت من `searching`/`offered`. هذا نمط سليم ومصمم كويس لمنع "thundering herd" على عرض واحد، ودورة حياته عبر alarms هي بالظبط الطريقة الصح للتايمرز في DOs (لأن `ctx.waitUntil` بيقف بعد حوالي 30 ثانية من انتهاء الـ response حسب تعليق الكود في الملف).

### 2.2 توصيل الـ WebSocket في `apps/api/src/index.ts`

فيه مسارين للـ WS:

```
GET /ws/trips/:id       → TRIP_ROOM.idFromName(tripId)
GET /ws/captain/offers  → CAPTAIN_INBOX.idFromName(userId | "pending-auth")
```

كل مسار بيدعم نفس نمط الـ dual-auth:
- التوكن جاي في `Authorization: Bearer` أو (deprecated) `?token=` query — لو موجود، الـ Worker يتحقق من JWT محليًا، يتأكد من العضوية (`rider_id`/`captain_id`/admin للرحلة، أو دور captain/admin للعروض)، ويمرر `role`/`userId` كـ query params للـ DO مباشرة.
- لو مفيش توكن واضح، يتبعت `pendingAuth=1` (و`tripId=` لحالة TripRoom) والـ DO نفسه يعمل الـ auth handshake بأول رسالة.

النمط ده منطقي كحل بديل لمشكلة `web_socket_channel` على الموبايل (مش بيدعم custom headers بشكل موثوق — موضح في تعليق `apps/captain/lib/services/trip_ws.dart`)، لكنه معناه فيه **مسارين مختلفين تمامًا للتحقق من نفس العملية** (auth في الـ Worker مقابل auth في الـ DO) لازم يفضلوا متزامنين — أي تغيير في منطق التحقق من العضوية (زي إضافة دور جديد أو حالة رحلة جديدة) لازم يتعمل في المكانين.

### 2.3 عملاء الـ WebSocket في Flutter — الثلاثة متطابقين هيكليًا

- `apps/rider/lib/services/trip_ws.dart` — `TripWebSocketService`.
- `apps/captain/lib/services/offers_ws.dart` — `OffersWebSocketService`.
- `apps/captain/lib/services/trip_ws.dart` — `CaptainTripWebSocketService` (اكتُشف أثناء التدقيق كملف إضافي واضح دخوله في النطاق — سوكيت الكابتن الخاص بغرفة الرحلة، منفصل عن `offers_ws.dart`).

الثلاثة بيشتركوا في نفس الأنماط بالظبط:

1. **Auth بالرسالة الأولى**: `_open()` بيفتح `WebSocketChannel`، يبعت `{"type":"auth","token":token}` كأول frame.
2. **Backoff أُسّي مع jitter**: `_scheduleReconnect()` بيحسب `(1 << _attempt.clamp(0,4))` ثانية (يعني 1, 2, 4, 8, 16 ثانية) + `Random().nextInt(1000)` مللي ثانية jitter، و`_attempt++` بيزيد مع كل محاولة فاشلة.
3. **Heartbeat**: `Timer.periodic` كل 25 ثانية بيبعت `ping`.
4. **مفيش أي sequence number أو "آخر event ID معروف" بيتبعت وقت الـ reconnect.** العميل ببساطة يفتح سوكيت جديد ويستنى event جديد — أي event حصل أثناء الانقطاع ضاع.

تعليق الكود في `CaptainTripWebSocketService` بيشرح سبب وجود السوكيت ده أصلًا:

> "The captain opens this the moment a trip is assigned so rider-side events — cancellations, status flips, and in-trip chat messages — arrive in real time instead of on the next offers poll, which was the root of the 'الرسايل مش بتظهر' complaint: the messages were saved, but the captain's app never listened for them."

هذا مؤشر مباشر إن الفريق قابل مشكلة تسليم حقيقية قبل كده (رسايل محفوظة في DB لكن محدش بلّغ عنها realtime) وحلّها بفتح قناة جديدة — لكن الحل معالج الـ symptom (مفيش listener) مش الـ root cause (مفيش ضمان تسليم/replay).

### 2.4 مسار إرسال الموقع — `apps/captain/lib/services/captain_state.dart`

الملف ده (47 كيلوبايت) هو "location-send path" المطلوب صراحة في نطاقي. أهم عناصره:

- **GPS stream واحد مشترك**: `_positionCtrl` هو `StreamController<Position>.broadcast()` واحد بيغذي كل من كاميرا الخريطة وبث الموقع للسيرفر — تعليق الكود بيوضح إن ده كان قبل كده "two independent `getPositionStream` subscriptions used to keep the GPS radio hot twice over" (يعني كان فيه استهلاك بطارية مضاعف اتحل بالفعل).
- **Adaptive accuracy profiles**: `_idleLocationSettings` (accuracy: medium, distanceFilter: 50م) مقابل `_tripLocationSettings` (accuracy: high, distanceFilter: 10م)، التبديل بناءً على `_hasActiveTrip` (الحالة ضمن `['assigned','accepted','arrived','in_progress']`).
- **كل GPS fix بيطلق HTTP POST**: `_startLocationStream()` بينادي `pushLocationCoordinates(lat, lng)` مع كل fix جديد طول ما `online || activeTrip != null` — يعني معدل الإرسال مربوط بـ `distanceFilter` بس، مش بأي حد زمني (time-based debounce) على مستوى العميل.
- **بلع الأخطاء بصمت**:

```dart
Future<void> pushLocationCoordinates(double lat, double lng) async {
  if (!online && activeTrip == null) return;
  try {
    await _post('/captain/location', {
      'lat': lat,
      'lng': lng,
      'city': 'cairo',
      if (activeTrip != null) 'tripId': activeTrip!['id'],
    });
  } catch (_) {}
}
```

لا retry، لا queue أوفلاين، لا أي إشارة مرئية للمستخدم أو للـ state إن آخر تحديث فشل.

- **آلية تعافي ذاتي جزئية**: `refreshOffers()` بتتحقق لو `_tripWs == null` بينما فيه رحلة نشطة، وتعيد فتح `CaptainTripWebSocketService` — تعليق الكود:

> "The socket can die silently: reconnect backoff gives up after a long outage... without this check a captain whose app briefly lost network would stay on the 8s poll for the rest of the trip."

هذا نمط جيد لكنه مبني يدويًا لسوكيت واحد بس (trip WS)، ومفيش نمط مطابق لـ offers WS خارج تبديل الـ polling interval نفسه.

- **Polling كـ fallback موثّق**: `_offersPollInterval = 8` ثانية (لما الـ WS واقعة) مقابل `_offersPollIntervalWsUp = 60` ثانية (لما متصلة) — تبديل عبر `_restartOffersTimer()` بـ debounce 600 مللي ثانية على `onStatus` callback. هذا موجود لـ offers فقط؛ TripRoom WS مالوش backstop مكافئ موثّق بنفس الوضوح (الاعتماد الوحيد هو نفس آلية الـ reconnect العامة).

### 2.5 مسار الكتابة في السيرفر — `apps/api/src/routes/captain.ts`

`POST /captain/location` (rate-limited عبر `rateLimit({prefix:"captain-loc", limit:30, windowSec:60, keyFn: user.id})`) بينفذ حتى 5 عمليات I/O لكل استدعاء:

```
1. UPDATE captains SET last_lat/last_lng/last_seen_at/is_online=1/city/updated_at
2. GEO_CELL.get(idFromName(cellKey)).fetch("https://cell/heartbeat", ...)
3. (لو tripId موجود وحالة الرحلة ضمن [assigned, arrived, in_progress]):
   a. UPDATE trips SET captain_lat/captain_lng/updated_at
   b. SELECT recorded_at FROM trip_path_points ... ORDER BY recorded_at DESC LIMIT 1
      → لو (!last || now - lastMs >= 30_000): INSERT INTO trip_path_points (...)
   c. TRIP_ROOM.get(idFromName(trip.id)).fetch("https://room/broadcast", {type:"location.captain",...})
```

مهم: البند 3.b هو الـ debounce الوحيد الزمني الحقيقي في كل المسار (30 ثانية لكتابة trip_path_points)، لكن البنود 1، 2، و3.c بتتنفذ **في كل استدعاء ناجح** مقيدة فقط بـ 30 طلب/دقيقة (KV rate limit) — مش بأي معدل زمني للـ write نفسه.

`GET /captain/nearby-requests` و`GET /captain/offers` (مسارين تانيين لمعرفة "مين قريب") بيستخدموا `haversineKm` على بيانات D1 (`last_lat`/`last_lng` من جدول `captains`) — **مش عبر GeoCell**. هذا معناه فيه **مصدرين منفصلين لموقع الكابتن**: GeoCell presence (محدّث فورًا عند كل heartbeat) وD1 columns (محدّثة في نفس اللحظة فعليًا لأنها في نفس الـ request، لكن عبر مسار كود منفصل تمامًا). حاليًا الاتنين بيتحدثوا معًا في نفس الـ request فمفيش انحراف فوري، لكن أي تغيير مستقبلي (مثلاً تأخير تحديث GeoCell أو فشله بصمت) هيخلق تعارض بين "اللي شايفه GeoCell" و"اللي شايفه D1" من غير أي آلية تصالح (reconciliation) بينهم.

### 2.6 نقاط بث الأحداث بعد تعديل الرحلة — `apps/api/src/routes/trips.ts`

الدالة `broadcastTrip(env, trip)`:

```ts
async function broadcastTrip(env: Env, trip: DbTrip) {
  const payload = await withCaptain(env, trip);
  const room = env.TRIP_ROOM.get(env.TRIP_ROOM.idFromName(trip.id));
  await room.fetch("https://room/broadcast", {
    method: "POST",
    body: JSON.stringify({ type: "trip.updated", trip: payload }),
  });
  await room.fetch("https://room/state", {
    method: "PUT",
    body: JSON.stringify(payload),
  });
}
```

بتتنادى بعد كل تعديل جوهري: cancel، accept، بداية الرحلة (arrived→in_progress)، complete، تقديم عرض سعر (bid submit — تعليق الكود هنا بيوضح إن نسيان النداء ده قبل كده "broke the rider's bid-polling sheet entirely")، وقبول العرض. كل نداء = **2 round-trip منفصلين لنفس الـ DO** (broadcast + state PUT)، من غير batching.

على الإلغاء، فيه fan-out إضافي لـ `trip.cancelled` push عبر `CAPTAIN_INBOX` لكل كابتن قريب (عبر `findNearbyCaptains`، نفس الجيران التسعة اللي كانوا استلموا العرض الأصلي).

على قبول عرض سعر (accept-bid)، السيرفر بيوقظ الكابتن الفايز مباشرة عبر `CAPTAIN_INBOX` بـ `type: "trip.assigned", reason: "bid.accepted"` — تعليق الكود بيوضح إن ده تجاوز متعمد لأن الكابتن لسه معندوش TripRoom socket مفتوح في اللحظة دي.

`GET /trips/:id/path` بيرجع:

```sql
SELECT lat, lng, heading, speed, recorded_at
FROM trip_path_points
WHERE trip_id = ?
ORDER BY recorded_at ASC
LIMIT 2000
```

حد أعلى صريح 2000 نقطة من غير أي pagination — رحلة طويلة جدًا (نادرة لكن ممكنة، خصوصًا في intercity) هتتقطع بصمت.

### 2.7 fan-out الـ 9 خلايا للمطابقة — `apps/api/src/lib/nearby.ts`

`neighbourhoodCellKeys()` بتحسب 9 نقاط (شبكة 3×3 حوالين موقع الراكب، مع `EDGE_EPS = 1e-7` nudge لتفادي miscounting عند حدود الخلية) وتعمل dedupe عبر `Set`. `findNearbyCaptains()` بتطلق `Promise.all` عبر التسعة `GEO_CELL` DO instances، بتدمج النتائج بمفتاح `userId` (تحتفظ بأقرب مسافة لو كابتن ظهر في أكتر من خلية أثناء عبوره الحدود)، ترتيب، وقص للـ limit. هذا معناه **9 استدعاءات DO لكل عملية بحث عن كباتن قريبين** — التكلفة والقياس هنا خارج نطاقي (track 18) لكن النمط نفسه (fan-out بلا cache) هو جزء من تصميم الـ realtime layer وأنا بس بلاحظه هنا كسياق مهم لقسم 4.

### 2.8 مخطط الـ D1 المرتبط بالبث الحي

من `migrations/0001_init.sql`:

```sql
CREATE TABLE IF NOT EXISTS trip_events (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  actor_id TEXT,
  type TEXT NOT NULL,
  payload TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_trip_events_trip ON trip_events(trip_id);
```

ومن `migrations/0002_enhancements.sql`:

```sql
CREATE TABLE IF NOT EXISTS trip_path_points (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  heading REAL,
  speed REAL,
  recorded_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_path_trip ON trip_path_points(trip_id);
CREATE INDEX IF NOT EXISTS idx_path_trip_time ON trip_path_points(trip_id, recorded_at);
```

كلا الجدولين **مفيهمش عمود ترتيب صريح (`seq`) ولا `UNIQUE` constraint يمنع تكرار الإدخال** عند إعادة محاولة فاشلة من العميل. `trip_events` موجود لكن ملحوظ إنه مش بيتقرأ في أي مسار WS حاليًا (البث بيحصل مباشرة من `broadcastTrip`، مش من قراءة `trip_events`) — يعني الجدول ده حاليًا **audit log فقط، مش مصدر حقيقة للـ replay**. هذا بالظبط الفجوة البنيوية اللي بتمنع تنفيذ "missed-message recovery" بسهولة: الجدول اللي ممكن يكون مصدر الـ replay موجود من أصلًا، بس مش متصل بمنطق البث.

## 3. الثغرات والمشاكل المكتشفة

| الخطورة | المشكلة | الدليل (file:symbol) | الأثر |
|---|---|---|---|
| P0 | مفيش sequence number ولا معرّف حدث فريد على أي بث WS | `TripRoom.ts: broadcast()`, `CaptainInbox.ts`, كل الـ Dart clients | العميل مقدرش يكتشف حدث فايت بعد انقطاع؛ مفيش طريقة لبناء replay صحيح |
| P0 | `trip_events` موجود كـ schema لكن غير متصل بمنطق البث أو الـ reconnect | `migrations/0001_init.sql: trip_events`, `trips.ts: broadcastTrip()` | فرصة ضايعة لبناء replay buffer رخيص؛ الجدول بيتاكل storage كـ audit فاضي من القيمة الوظيفية |
| P0 | إعادة الاتصال بترجع تفتح سوكيت جديد من غير أي "آخر حالة معروفة" أو catch-up fetch | `trip_ws.dart (rider)`, `trip_ws.dart (captain)`, `offers_ws.dart` | راكب/كابتن يفوّت أحداث حرجة زي `trip.cancelled` أو `trip.assigned` لو حصلت أثناء انقطاع قصير (شائع على شبكات موبايل مصرية) |
| P0 | `pushLocationCoordinates()` بتبلع كل استثناء بصمت، مفيش retry أو offline queue | `captain_state.dart: pushLocationCoordinates()` | فقدان صامت لتحديثات الموقع تحت شبكة ضعيفة؛ الراكب يشوف الكابتن "واقف" رغم إنه ماشي |
| P0 | `CaptainInbox` proxy pattern بيكلف 2 DO instance + hop مزدوج لكل اتصال بدون token مباشر | `CaptainInbox.ts: completeAuth()` (`this.env.CAPTAIN_INBOX.get(idFromName(user.id))` جوّه instance تانية) | تضاعف تكلفة الـ DO وزمن الاستجابة لكل كابتن بيفتح التطبيق من جديد ومعندوش توكن كاش وقت فتح السوكيت |
| P0 | `GeoCell.nearby()` full unbounded `storage.list()` scan من غير حد أعلى | `GeoCell.ts: /nearby handler` | مع نمو عدد الكباتن في خلية واحدة (مناطق مزدحمة زي وسط البلد)، كل استعلام مطابقة يقرأ كل الـ entries حتى لو النتيجة النهائية 10 بس |
| P0 | تعارض نافذة الـ staleness بين `/nearby` (دقيقتين) و`alarm()` cleanup (3 دقايق) | `GeoCell.ts: maxAgeMs default 120000` مقابل `alarm(): now - lastSeen > 180_000` | نافذة دقيقة كاملة كابتن أوفلاين فعليًا يفضل مؤهل يظهر في نتائج قريب |
| P0 | فقدان الـ id الحقيقي في حالات معينة من `resolveTripId()` fallback الأخير (hex id) | `TripRoom.ts: resolveTripId()` تعليق الكود نفسه | أي مسار مستقبلي يعتمد على `ctx.id.name` بدون توفره (compat date أقدم أو DO اتنقل) يرجع hex id غلط يفشل أي D1 lookup — نفس فئة الـ bug التاريخية موثقة في التعليق |
| P1 | مفيش idempotency key على `trip_path_points` INSERT | `captain.ts: POST /captain/location` (البند 3.b) | retry من العميل بعد timeout (رغم نجاح الكتابة فعليًا) يقدر يعمل duplicate إدخال يشوّه رسم مسار الرحلة |
| P1 | مفيش دليل على backstop polling موثّق لـ TripRoom WS بنفس وضوح offers WS | `captain_state.dart` (`_offersPollInterval` موجود، مفيش مكافئ trip room) | لو `CaptainTripWebSocketService` مات صامت خارج نافذة الـ `refreshOffers()` check، مفيش شبكة أمان مستقلة |
| P1 | مصدرين منفصلين لموقع الكابتن (GeoCell presence وD1 `captains.last_lat/lng`) من غير آلية تصالح | `captain.ts: POST /captain/location` (بند 1 و2)، `captain.ts: GET /captain/nearby-requests` | أي فشل جزئي مستقبلي (مثلاً GeoCell heartbeat يفشل والـ D1 UPDATE ينجح) يخلق انحراف بين "خريطة GeoCell" و"خريطة D1" بدون تنبيه |
| P1 | `GET /trips/:id/path` بحد أعلى صريح 2000 نقطة بلا pagination | `trips.ts: GET /trips/:id/path` | رحلة طويلة (intercity، تأخير كبير) ترجع مسار مقطوع بصمت من غير أي إشارة "فيه نقاط أكتر" |
| P1 | كل تعديل رحلة يعمل 2 round-trip منفصل لنفس TripRoom (`/broadcast` ثم `/state`) | `trips.ts: broadcastTrip()` | مضاعفة عدد نداءات DO لكل حدث رحلة؛ فرصة دمج ضايعة |
| P1 | التحقق من العضوية (auth) مكرر في مكانين منفصلين (Worker route وDO) لازم يفضلوا متزامنين | `index.ts: /ws/trips/:id`, `/ws/captain/offers` مقابل `TripRoom.ts: completeAuth()`, `CaptainInbox.ts: completeAuth()` | أي تغيير مستقبلي في قواعد العضوية (دور جديد، حالة رحلة جديدة) لازم يتعمل مرتين، وأي نسيان يخلق ثغرة أو false rejection |
| P2 | مفيش dead-reckoning/interpolation على جانب العميل بين تحديثات الموقع | غياب كامل — لا في `trip_ws.dart` ولا `captain_state.dart` | حركة الكابتن على خريطة الراكب "تقفز" بدل حركة سلسة، خصوصًا مع `distanceFilter: 10م` وقت انقطاع GPS مؤقت |
| P2 | معدل إرسال الموقع من العميل مربوط بـ `distanceFilter` فقط، مفيش حد زمني أقصى (throttle) على مستوى العميل نفسه | `captain_state.dart: _startLocationStream()` | كابتن بيتحرك بسرعة عالية (طريق سريع) ممكن يطلق POST متكرر جدًا خلال ثواني، معتمد كليًا على الـ rate limit في السيرفر كخط دفاع وحيد |
| P2 | فان-آوت خريطة الأدمن الحي غير موثّق بوضوح كمسار مستقل عبر أي DO — الافتراض إنه بيعتمد على polling عبر مسارات admin REST | لم يُعثر على استخدام مباشر لـ `TRIP_ROOM`/`GEO_CELL` من أي مسار `apps/admin` أثناء التدقيق | خريطة الأدمن (لو REST-polling فعلًا) هتكون دايمًا متأخرة عن الواقع الحي بمقدار فترة الـ polling، ومفيش fan-out موحّد لكل الأطراف الثلاثة (راكب/كابتن/أدمن) من نفس مصدر الحدث |
| P2 | لا يوجد unique constraint على `trip_path_points` يمنع duplicate بنفس `trip_id + recorded_at` | `migrations/0002_enhancements.sql: trip_path_points` | يسمح بإدخالات مكررة فنيًا حتى لو نادرة الحدوث حاليًا بسبب الـ 30-ثانية check |

## 4. خطة التحسين

### 4.1 P0 — التسليم الموثوق والاستقرار الأساسي

#### 4.1.1 إضافة sequence number لكل بث WS + ربط `trip_events` كمصدر حقيقة للـ replay

**التغيير:** كل حدث يتبعت عبر `TripRoom.broadcast()` يتخزن أولًا كصف في `trip_events` (بعمود `seq` جديد auto-increment لكل `trip_id`)، وبعدين يتبث بنفس الـ payload زائد `seq`. عند فتح سوكيت جديد (سواء أول اتصال أو reconnect)، العميل يبعت `{"type":"auth","token":..., "lastSeq": <n>}` (اختياري، `0` أو غايب = من الأول). السيرفر (في `completeAuth()`) يقرأ `trip_events WHERE trip_id = ? AND seq > ? ORDER BY seq ASC LIMIT 200` ويبعتها كـ batch `{"type":"replay","events":[...]}` قبل ما يبدأ البث الحي العادي.

**الملفات المتأثرة:**
- `migrations/00XX_realtime_sequencing.sql` (جديد): `ALTER TABLE trip_events ADD COLUMN seq INTEGER`; `CREATE UNIQUE INDEX idx_trip_events_trip_seq ON trip_events(trip_id, seq)`؛ جدول عداد بسيط أو استخدام `MAX(seq)+1` محسوب داخل نفس الـ DO transaction (الأفضل: تخزين العداد في `ctx.storage` الخاص بـ TripRoom نفسه بما إن كل DO instance = رحلة واحدة، فمفيش تنافس على العداد).
- `apps/api/src/durable-objects/TripRoom.ts`: `broadcast()` يتقسم لـ `recordEvent()` (يكتب لـ D1 + يزود العداد المحلي في `ctx.storage`) و`broadcast()` (يبث للسوكيتات الحالية فقط، زي دلوقتي).
- `apps/api/src/durable-objects/TripRoom.ts`: `completeAuth()` يقرأ `lastSeq` من رسالة الـ auth ويبعت الـ replay batch قبل تفعيل البث العادي.
- `apps/rider/lib/services/trip_ws.dart`, `apps/captain/lib/services/trip_ws.dart`: تخزين آخر `seq` مستلم محليًا (بس في الذاكرة كافي لعمر السيشن، مش محتاج persistence لأن أول اتصال أصلًا `lastSeq=0`)، إرساله في رسالة الـ auth، ومعالجة رسالة `"type":"replay"` بتطبيق كل event بالترتيب قبل استئناف المعالجة العادية.

**تغييرات الـ schema أو API:**
- `trip_events.seq INTEGER` (nullable مبدئيًا للتوافق الخلفي مع الصفوف القديمة، ثم `NOT NULL` بعد backfill).
- رسالة WS جديدة من العميل: `{"type":"auth","token":"...","lastSeq":<int>}`.
- رسالة WS جديدة من السيرفر: `{"type":"replay","events":[{seq,type,payload,createdAt}, ...]}`.

**معايير القبول:**
- فصل الشبكة لمدة 5-15 ثانية أثناء رحلة نشطة، مع حصول `trip.updated` واحد على الأقل أثناء الانقطاع → عند إعادة الاتصال، العميل يستلم الحدث الفايت عبر `replay` قبل أي بث حي جديد.
- `trip_events.seq` فريد لكل `(trip_id, seq)` بدون فجوات غير متوقعة تحت حمل تزامني (اختبار: 50 حدث متتالي على نفس الرحلة من مصادر مختلفة، التأكد من الترتيب الصحيح).
- لا يوجد ازدواج في تطبيق نفس الـ event على العميل (اختبار: قطع الاتصال يدويًا وإعادته 3 مرات متتالية، التأكد من عدم تكرار أي بطاقة في UI الرحلة).

**التقدير:** 5-7 أيام مهندس واحد (migration + DO logic + 2 عملاء Dart + اختبارات تكامل).

#### 4.1.2 تفعيل نفس نمط الـ sequencing على `CaptainInbox`

**التغيير:** نفس منطق 4.1.1 لكن لصندوق عروض الكابتن. بما إنه مفيش جدول مكافئ لـ `trip_events` لعروض الكباتن، نضيف جدول جديد `captain_inbox_events` (بديل أرخص: تخزين آخر N أحداث في `ctx.storage` الخاص بالـ DO نفسه بدل D1 — العدد المتوقع صغير لكل كابتن فرديًا، فالـ storage المحلي للـ DO كافي وأرخص من D1 write إضافي).

**الملفات المتأثرة:**
- `apps/api/src/durable-objects/CaptainInbox.ts`: إضافة `seq` counter في `ctx.storage`، تخزين آخر 50 حدث (ring buffer بسيط في `ctx.storage.put`) بدل D1 جديد.
- `apps/captain/lib/services/offers_ws.dart`: نفس منطق `lastSeq` وrisplay.

**تغييرات الـ schema أو API:** لا تغيير D1 (يُحل بالكامل عبر `ctx.storage` الداخلي لـ DO). رسالة WS جديدة مطابقة لـ 4.1.1.

**معايير القبول:** كابتن يفصل نت لمدة قصيرة أثناء انتظار عروض، عرض جديد يوصله كامل بعد إعادة الاتصال حتى لو فاته وقت الانقطاع.

**التقدير:** 3-4 أيام (أبسط من 4.1.1 لعدم الحاجة لـ D1 migration).

#### 4.1.3 إصلاح `pushLocationCoordinates()`: retry + offline queue محدود

**التغيير:** استبدال `catch (_) {}` بمنطق retry محدود (3 محاولات بـ backoff قصير) ثم، لو فشل نهائيًا، تخزين آخر موقع فاشل في queue محلي في الذاكرة (حد أقصى 5 عناصر، الأقدم يتشال لو امتلأ) يتحاول إرساله مع أول POST ناجح بعد كده (كـ batch صغير `locations: [...]`)، مع تسجيل حدث محلي (state flag `lastLocationPushFailed: bool`) يقدر UI مستقبلًا يستخدمه لعرض تحذير للكابتن ("الموقع مش بيتحدث، افحص الاتصال").

**الملفات المتأثرة:**
- `apps/captain/lib/services/captain_state.dart`: `pushLocationCoordinates()` (إعادة كتابة كاملة للمنطق الداخلي)، إضافة `_pendingLocationQueue` وحقل حالة جديد.
- `apps/api/src/routes/captain.ts`: `POST /captain/location` يحتاج يدعم استقبال batch اختياري `{locations: [{lat,lng,recordedAtClient}, ...]}` بدل نقطة واحدة بس (توافق خلفي: لو الجسم القديم `{lat,lng,...}` يتعامل زي ما هو، لو فيه `locations[]` يعالج كل عنصر بالترتيب).

**تغييرات الـ schema أو API:** `POST /captain/location` body schema (في `apps/api/src/lib/schemas.ts`) يتوسع لدعم `locations?: Array<{lat, lng, recordedAtClient}>` اختياري بجانب الحقول الحالية.

**معايير القبول:**
- قطع الشبكة يدويًا لمدة 20 ثانية أثناء تحرك الكابتن → عند عودة الشبكة، آخر حتى 5 مواقع محفوظة تتبعت كـ batch واحد، الترتيب الزمني محفوظ في `trip_path_points` (تستخدم `recordedAtClient` بدل `datetime('now')` السيرفر لو موجودة).
- لا exception غير معالج يوصل لأي مكان في الـ call stack (كل مسار retry معالج بوضوح).

**التقدير:** 4-5 أيام (منطق العميل + توسيع الـ API + اختبار على شبكة متذبذبة فعليًا).

#### 4.1.4 إلغاء عبء الـ proxy المزدوج في `CaptainInbox` بتوحيد نقطة الدخول للتوكن

**التغيير:** بدل الاعتماد على "pending-auth well-known instance + relay"، الحل الأنظف هو خلي `apps/captain` **يخزن التوكن دايمًا محليًا قبل فتح أي WebSocket** (باستخدام نفس آلية الـ refresh الموجودة أصلًا في auth flow) بحيث يبقى نادرًا جدًا إن السوكيت يتفتح من غير `Authorization` header. الـ proxy pattern يفضل موجود كـ fallback نادر (fail-safe) لكن مش المسار الافتراضي. بالتوازي، تحسين `CaptainInbox.completeAuth()` بحيث الـ pending-auth instance بعد نجاح الـ handshake **تسكّر نفسها فورًا** (`ws.close()` على السوكيت الوسيط الداخلي القديم واستبداله بتحويل مباشر) بدل ما تفضل شغالة كـ relay طول عمر الاتصال بالكامل — لو ده مش ممكن فنيًا بسهولة (الـ WebSocketPair بمجرد إنشائه مربوط)، على الأقل توثيق وقياس نسبة الاتصالات اللي بتعدي على المسار ده (metric جديد) عشان نعرف حجم المشكلة الفعلي قبل استثمار أكبر.

**الملفات المتأثرة:**
- `apps/captain/lib/services/offers_ws.dart` و `captain_state.dart`: التأكد من استدعاء `_connectOffersWs()` بعد ضمان توفر توكن صالح (مش قبل)، وربط أي محاولة اتصال بمنطق الـ refresh الموجود في auth service.
- `apps/api/src/durable-objects/CaptainInbox.ts`: إضافة عداد بسيط (`ctx.storage` أو حتى `console.log` منظم لقراءته من Cloudflare logs مبدئيًا) لعدد الاتصالات اللي عدت على مسار `pendingAuth=1` مقابل التوكن المباشر — هذا القياس أساسي قبل قرار استثمار أكبر في إعادة هيكلة الـ proxy.

**تغييرات الـ schema أو API:** لا تغيير خارجي. إضافة داخلية فقط (logging/metric).

**معايير القبول:**
- بعد التعديل، نسبة الاتصالات على مسار `pendingAuth=1` لكابتن عنده توكن صالح ومخزّن تنخفض إلى ما يقارب الصفر (تُقاس عبر الـ metric الجديد على مدار أسبوع في staging).
- لا انحدار في زمن أول اتصال ناجح للعروض (يُقاس بمتوسط زمن ما بين فتح التطبيق واستلام أول رسالة `offers.ready` أو مكافئها).

**التقدير:** 3 أيام (تعديل ترتيب الاستدعاء في العميل بسيط، إضافة القياس بسيطة؛ إعادة الهيكلة الكاملة للـ proxy نفسه مؤجلة لحد ما نشوف نتيجة القياس — ممكن تتضح إنها مش لازمة أصلًا لو نسبة المسار القديم صارت صفر تقريبًا).

#### 4.1.5 وضع حد أعلى (`limit`) صريح على `GeoCell.nearby()` scan + pagination داخلي

**التغيير:** استبدال `storage.list<CaptainPresence>({prefix:"captain:"})` غير المحدود بـ `storage.list({prefix:"captain:", limit: MAX_SCAN=200})`. لو الخلية فيها أكتر من 200 كابتن مسجل presence (حالة مزدحمة جدًا)، نضيف تحذير/metric بدل ما نعتمد على قراءة غير محدودة. بالتوازي، بما إن معظم الخلايا الفعلية هتكون بعيدة جدًا عن الحد ده، هذا تغيير أمان بحت (defensive cap) مش تحسين أداء فوري محسوس في الحالة العادية — لكنه يمنع سيناريو "خلية وسط البلد وقت الذروة" من عمل scan بطيء يبطئ كل استعلامات المطابقة اللي بتلمس نفس الخلية.

**الملفات المتأثرة:**
- `apps/api/src/durable-objects/GeoCell.ts`: تعديل `/nearby` handler لإضافة الـ `limit` على `storage.list()` نفسه (مش بس على النتيجة النهائية بعد الفرز)، وتسجيل metric لو الـ scan رجع بالظبط `MAX_SCAN` (إشارة إن فيه احتمال قطع بيانات).

**تغييرات الـ schema أو API:** لا تغيير خارجي — تعديل داخلي في `GeoCell.ts` فقط.

**معايير القبول:**
- اختبار وحدة: خلية بها 500 presence entry، استدعاء `/nearby` يرجع في زمن مقبول (< 50ms p99 محليًا) بدل قراءة كل الـ 500.
- metric تحذيري يظهر في اللوج لو أي خلية فعلية توصل لحد الـ `MAX_SCAN` (إشارة لضرورة إعادة نظر في دقة الـ geohash لتلك المنطقة تحديدًا — قرار مستقبلي، مش جزء من هذا التغيير).

**التقدير:** 1-2 يوم.

#### 4.1.6 توحيد نافذة الـ staleness بين `/nearby` والـ `alarm()` cleanup

**التغيير:** تعريف ثابت واحد `PRESENCE_MAX_AGE_MS = 90_000` (90 ثانية، قيمة وسطية معقولة بين الرقمين الحاليين) يُستخدم في كل من `maxAgeMs` الافتراضي في `/nearby` **و** حد التنظيف في `alarm()`، بدل رقمين منفصلين (120000 و180000). القيمة النهائية (90 ثانية مقابل غيرها) تحتاج تنسيق بسيط مع فريق المطابقة (track 02) بما إنها بتأثر على "إيه هو الكابتن المؤهل يُعتبر قريب" — لكن المبدأ الأساسي (رقم واحد مصدر حقيقة بدل رقمين متباعدين) هو التغيير الجوهري هنا وواضح إنه تحسين بغض النظر عن القيمة المضبوطة بالظبط.

**الملفات المتأثرة:**
- `apps/api/src/durable-objects/GeoCell.ts`: تعريف الثابت `PRESENCE_MAX_AGE_MS` أعلى الملف، استخدامه في كل من `/nearby` (بدل `maxAgeMs = 120000` hardcoded) وفي `alarm()` (بدل `180_000` hardcoded).

**تغييرات الـ schema أو API:** لا تغيير خارجي.

**معايير القبول:** استعلام `/nearby` بعد 91 ثانية بالضبط من آخر heartbeat لكابتن لا يرجعه ضمن النتائج، وفي نفس الوقت `alarm()` اللاحق (خلال دقيقة) يمسح presence entry بتاعته من الـ storage. مفيش نافذة تعارض بين الاستعلام والتنظيف.

**التقدير:** نصف يوم (تغيير ثابت + اختبار).

#### 4.1.7 تعزيز `resolveTripId()`: تسجيل تحذير صريح عند الوصول لآخر fallback

**التغيير:** إضافة `console.error`/metric صريح (وليس صمت) في `resolveTripId()` في اللحظة اللي بيوصل فيها لآخر fallback (hex id، المسار اللي غالبًا يفشل D1 lookup). هذا لا يحل المشكلة الجذرية بالكامل (لسه معتمدين على `?tripId=` أو `ctx.storage` كخط دفاع أول)، لكنه يحول أي تكرار مستقبلي لنفس فئة الـ bug التاريخية (موصوفة في تعليق الكود نفسه) من "فشل صامت لكل الجلسة" إلى "تنبيه فوري قابل للرصد في اللوج/dashboard".

**الملفات المتأثرة:**
- `apps/api/src/durable-objects/TripRoom.ts`: `resolveTripId()` — إضافة تسجيل واضح عند الوصول للفرع الأخير.

**تغييرات الـ schema أو API:** لا شيء.

**معايير القبول:** اختبار وحدة يفرض سيناريو "لا `?tripId=` ولا `ctx.storage` قيمة محفوظة ولا `ctx.id.name` متاح" ويتأكد من ظهور رسالة تحذير واضحة في اللوج تحتوي على الـ hex id المستخدم كـ fallback.

**التقدير:** نصف يوم.

#### 4.1.8 توثيق ونشر backstop polling مستقل لـ TripRoom WS (مطابق لـ offers)

**التغيير:** إضافة نفس نمط `_offersPollInterval` الموجود لعروض الكابتن (8 ثانية WS-down / 60 ثانية WS-up) لغرفة الرحلة أيضًا — سواء لجانب الراكب (`apps/rider`) أو جانب الكابتن. هذا يضمن إن حتى لو `CaptainTripWebSocketService`/`TripWebSocketService` ماتت بصمت خارج أي فحص يدوي زي `refreshOffers()`، يفضل فيه شبكة أمان مستقلة بتستعلم `GET /trips/:id` بمعدل معقول.

**الملفات المتأثرة:**
- `apps/rider/lib/services/trip_ws.dart` أو الشاشة المستهلكة له (يُحدد بعد فحص من يستدعي الخدمة دي — خارج نطاق التدقيق التفصيلي لهذه الوثيقة لأنه واجهة راكب، لكن مبدأ الإضافة هندسيًا هو مسؤولية طبقة النقل الحي).
- `apps/captain/lib/services/captain_state.dart`: إضافة `_tripPollInterval`/`_tripPollIntervalWsUp` بنفس نمط الـ offers الموجود بالفعل، مربوطة بحالة `_tripWs`.

**تغييرات الـ schema أو API:** لا تغيير — يستخدم `GET /trips/:id` الموجود أصلًا.

**معايير القبول:** قتل اتصال WS الرحلة يدويًا (محاكاة عبر قطع الشبكة أو force-close) → خلال 8-10 ثواني، حالة الرحلة تتحدث عبر REST fallback حتى لو الـ WebSocket لسه مايرجعش يتصل.

**التقدير:** 2-3 أيام.

### 4.2 P1 — تحسين الاتساق وكفاءة الكتابة

#### 4.2.1 إضافة idempotency key لكتابة `trip_path_points`

**التغيير:** توليد `clientEventId` (UUID) على جانب الكابتن لكل fix محاول إرساله، تمريره في body الطلب، وإضافة `UNIQUE INDEX` على `trip_path_points(trip_id, client_event_id)` في D1 بحيث أي retry بنفس الـ id يُرفض بصمت (INSERT OR IGNORE) بدل ما يخلق صف مكرر.

**الملفات المتأثرة:**
- `migrations/00XX_path_points_idempotency.sql`: `ALTER TABLE trip_path_points ADD COLUMN client_event_id TEXT`; `CREATE UNIQUE INDEX idx_path_client_event ON trip_path_points(trip_id, client_event_id) WHERE client_event_id IS NOT NULL`.
- `apps/api/src/routes/captain.ts`: `POST /captain/location` يستخدم `INSERT OR IGNORE INTO trip_path_points (..., client_event_id) VALUES (...)`.
- `apps/captain/lib/services/captain_state.dart`: توليد `clientEventId` (`Uuid().v4()` أو مكافئ) مع كل محاولة POST.

**تغييرات الـ schema أو API:** `trip_path_points.client_event_id TEXT` (nullable)، `POST /captain/location` body يقبل `clientEventId?: string` اختياري.

**معايير القبول:** إرسال نفس الطلب مرتين بنفس `clientEventId` (محاكاة retry) → صف واحد بس في `trip_path_points`.

**التقدير:** 2 أيام.

#### 4.2.2 توحيد `broadcastTrip()` لنداء DO واحد بدل اتنين

**التغيير:** دمج `/broadcast` و`/state` في endpoint واحد جديد `POST /sync` على `TripRoom` يستقبل الـ payload الكامل، يحدّث `ctx.storage` (بديل الـ `PUT /state` الحالي) **و** يبث `trip.updated` (بديل الـ `POST /broadcast` الحالي) في نفس استدعاء الـ `fetch()` من الـ DO، فيبقى فيه round-trip واحد فقط من `trips.ts` لكل تعديل رحلة بدل اتنين.

**الملفات المتأثرة:**
- `apps/api/src/durable-objects/TripRoom.ts`: إضافة handler جديد `POST /sync` يجمع منطق `/broadcast` و`PUT /state` الحاليين (الاتنين يُبقى عليهم مؤقتًا كـ endpoints قديمة للتوافق الخلفي أثناء الانتقال، ثم يُشالوا بعد التأكد إن كل الاستدعاءات انتقلت).
- `apps/api/src/routes/trips.ts`: `broadcastTrip()` تستبدل نداءين بنداء واحد لـ `/sync`.

**تغييرات الـ schema أو API:** endpoint داخلي جديد على TripRoom (`POST /sync`)، لا تغيير على أي API عام يواجه العميل.

**معايير القبول:** كل مسارات تعديل الرحلة (cancel, accept, arrived, complete, bid submit, accept-bid) تستمر تبث نفس الأحداث بنفس المحتوى، لكن بعدد نداءات DO أقل (يُقاس بعدد الطلبات في لوج Cloudflare قبل وبعد لكل نوع تعديل).

**التقدير:** 3 أيام (تعديل + اختبار رجعي شامل على كل مسارات trips.ts اللي بتنادي broadcastTrip).

#### 4.2.3 آلية تصالح دورية بين GeoCell presence وD1 `captains` columns

**التغيير:** إضافة cron خفيف (منفصل تمامًا عن أي منطق مطابقة — هذا فحص اتساق فقط) يقارن عينة عشوائية من الكباتن الأونلاين في D1 (`captains WHERE is_online=1`) مقابل وجودهم الفعلي في الـ GeoCell المتوقعة لموقعهم، ويسجل metric لعدد التعارضات المكتشفة. هذا للرصد فقط في المرحلة الأولى (مش تصحيح تلقائي) لبناء فهم حقيقي لحجم الانحراف قبل اتخاذ قرار هندسي أكبر.

**الملفات المتأثرة:**
- `apps/api/src/index.ts`: `scheduled()` handler — إضافة مهمة جديدة (منفصلة عن مهام التنظيف الموجودة) بمعدل منخفض (كل ساعة مثلًا).
- ملف جديد صغير `apps/api/src/lib/presenceReconciliation.ts`.

**تغييرات الـ schema أو API:** لا تغيير خارجي — قياس داخلي فقط.

**معايير القبول:** بعد أسبوع تشغيل في staging، توفر رقم واضح ("X% من الكباتن الأونلاين لهم انحراف presence") يُستخدم كمدخل لقرار لاحق (خارج هذه الوثيقة) عن ضرورة استثمار أكبر في التصالح التلقائي.

**التقدير:** 2-3 أيام.

#### 4.2.4 إضافة pagination حقيقي لـ `GET /trips/:id/path`

**التغيير:** استبدال `LIMIT 2000` الصلب بـ `?after=<recorded_at>&limit=<n>` cursor-based pagination، مع الحفاظ على السلوك الافتراضي الحالي (أول صفحة، حد 2000) كـ default للتوافق الخلفي، لكن مع إضافة `hasMore: boolean` في الـ response عشان العميل (شاشة "مسار الرحلة" في أي من التطبيقات) يعرف لو فيه نقاط إضافية.

**الملفات المتأثرة:**
- `apps/api/src/routes/trips.ts`: `GET /trips/:id/path` handler.

**تغييرات الـ schema أو API:** query params جديدة اختيارية `after`, `limit`؛ response body يضيف `hasMore: boolean`.

**معايير القبول:** رحلة تجريبية بأكتر من 2000 نقطة (يمكن محاكاتها بإدخال يدوي في بيئة اختبار) → أول استدعاء يرجع `hasMore: true`، استدعاء تاني بـ `after` الصحيح يرجع باقي النقاط.

**التقدير:** يوم ونصف.

#### 4.2.5 توحيد منطق التحقق من العضوية بين `index.ts` والـ DOs في دالة مشتركة

**التغيير:** استخراج منطق "هل هذا المستخدم عضو في هذه الرحلة/له صلاحية الوصول لهذا العرض" في دالة واحدة مشتركة (`apps/api/src/lib/tripAccess.ts` جديد، أو توسيع `lib/` موجود) تُستخدم من كل من `index.ts` (المسار المباشر بتوكن) و`TripRoom.ts`/`CaptainInbox.ts` (`completeAuth()`). هذا يقلل خطر انحراف قواعد التحقق بين المسارين مستقبلًا.

**الملفات المتأثرة:**
- ملف جديد `apps/api/src/lib/tripAccess.ts` (أو مكافئ): دالة `canAccessTripRoom(env, userId, role, tripId): Promise<boolean>` ومكافئها لـ captain inbox.
- `apps/api/src/index.ts`: استخدام الدالة الجديدة بدل المنطق المضمّن.
- `apps/api/src/durable-objects/TripRoom.ts`, `CaptainInbox.ts`: `completeAuth()` تستخدم نفس الدالة (ملاحظة: الـ DO بيحتاج يستدعي D1 مباشرة برضه من جوّاه، فالدالة المشتركة لازم تتصمم عشان تشتغل من الاتنين — الـ Worker route عنده الـ `env` كامل والـ DO عنده `this.env` مطابق).

**تغييرات الـ schema أو API:** لا تغيير خارجي — إعادة هيكلة داخلية فقط.

**معايير القبول:** اختبار تكامل: تعديل قاعدة عضوية واحدة (مثلًا إضافة حالة رحلة جديدة تسمح بالوصول) في مكان واحد فقط يكفي لتفعيلها في كل من المسار المباشر (`index.ts`) ومسار الـ pending-auth (الـ DO).

**التقدير:** 3-4 أيام.

### 4.3 P2 — ميزات نضج إضافية

#### 4.3.1 Dead-reckoning بسيط على جانب العميل بين تحديثات الموقع

**التغيير:** في شاشة تتبع الراكب (المستهلكة لـ `location.captain` من `trip_ws.dart`)، إضافة interpolation خطي بسيط بين آخر نقطتين معروفتين (باستخدام `heading` و`speed` المتوفرين فعلًا من payload الموقع) عبر `AnimationController` قصير (2-4 ثواني، بمعدل التحديث المتوقع من السيرفر)، بدل "قفزة" الماركر المباشرة من نقطة لنقطة.

**الملفات المتأثرة:**
- شاشة تتبع الرحلة في `apps/rider` (تستهلك `TripWebSocketService.onMessage`) — الملف المحدد يحتاج تحديد بعد فحص الشاشة الفعلية، لكن المكان المنطقي هو حيث بيتحرك ماركر الخريطة.
- احتمال إضافة helper مشترك في `packages/flutter_shared` لو نفس المنطق مطلوب لأكتر من شاشة (مثلًا خريطة الأدمن الحي لو بتتبنى نفس مصدر البيانات لاحقًا).

**تغييرات الـ schema أو API:** لا تغيير — استخدام حقول موجودة بالفعل (`heading`, وربما إضافة `speed` لو مش موجود في payload الـ `location.captain` الحالي — يحتاج فحص، وإضافته لو غايب).

**معايير القبول:** حركة الماركر على الخريطة تظهر سلسة بصريًا بين تحديثين متتاليين بدل قفزة مفاجئة (تقييم بصري + قياس عدد الـ frames في الانتقال).

**التقدير:** 4-5 أيام (منطق interpolation + اختبار بصري عبر أجهزة مختلفة).

#### 4.3.2 Presence دقيق: تمييز "أونلاين لكن مش بيتحرك" عن "أونلاين وماشي"

**التغيير:** إضافة حقل `movementState` (`stationary` | `moving`) محسوب على جانب العميل (بناءً على `speed` من GPS) يترسل مع الموقع، يُستخدم في `GeoCell.CaptainPresence` وفي عرض خريطة الأدمن (وربما رمز مختلف على خريطة الراكب) للتمييز البصري بين كابتن واقف (عند إشارة، أو مركون) وكابتن بيسوق فعليًا.

**الملفات المتأثرة:**
- `apps/captain/lib/services/captain_state.dart`: حساب `movementState` وإرساله ضمن `pushLocationCoordinates`.
- `apps/api/src/durable-objects/GeoCell.ts`: توسيع `CaptainPresence` type بحقل `movementState?`.
- عرض الخريطة في `apps/admin` (وربما `apps/rider`/`apps/captain` لعرض بعضهم البعض) — تحديد الأيقونة بناءً على الحقل الجديد.

**تغييرات الـ schema أو API:** `POST /captain/location` body يضيف `movementState?: 'stationary' | 'moving'` اختياري. `CaptainPresence` type في `GeoCell.ts` يوسّع بنفس الحقل.

**معايير القبول:** كابتن واقف لأكتر من دقيقة (سرعة GPS قريبة من صفر) يظهر بأيقونة مختلفة عن كابتن بيسوق بسرعة > 5 كم/س، على أي خريطة تستهلك presence data.

**التقدير:** 3-4 أيام.

#### 4.3.3 توحيد فان-آوت خريطة الأدمن الحي عبر قناة WS مخصصة (بدل افتراض الـ polling)

**التغيير:** بناءً على الملاحظة في القسم 2 (مفيش دليل واضح على استخدام `TRIP_ROOM`/`GEO_CELL` مباشرة من `apps/admin`)، إضافة WebSocket مخصص لخريطة الأدمن الحي (`GET /ws/admin/live-map` مثلًا) يتصل بمصدر حدث مجمّع (يمكن أن يكون DO جديد خفيف `AdminLiveFeed` يستهلك نفس نوع الأحداث اللي بتتبث من `TripRoom` و`GeoCell` عبر آلية نشر داخلية، أو ببساطة أول تكرار عملي: اشتراك في نفس أحداث `trip.updated`/`location.captain` عبر broadcast موازٍ من `broadcastTrip()` لقناة أدمن عامة). هذا يحول خريطة الأدمن من "متأخرة بمقدار فترة polling" إلى حية فعليًا، بما يطابق تجربة لوحات القيادة في Uber/inDrive الداخلية.

**الملفات المتأثرة:**
- ملف جديد محتمل `apps/api/src/durable-objects/AdminLiveFeed.ts` (أو تمديد بسيط لمسار موجود لو الحجم المتوقع من الأدمن المتصلين صغير جدًا — عادة عدد قليل من موظفي العمليات متصلين في نفس اللحظة، فمفيش حاجة لتعقيد كبير).
- `apps/api/src/routes/trips.ts`: `broadcastTrip()` يضيف نشر اختياري لقناة الأدمن.
- `apps/admin/src/pages/*` (الصفحة المسؤولة عن الخريطة الحية — تحديد دقيق يحتاج فحص لاحق خارج نطاق التدقيق الحالي).
- `apps/api/wrangler.toml`: binding جديد + migration لو تم اختيار DO منفصل.

**تغييرات الـ schema أو API:** endpoint جديد `GET /ws/admin/live-map` (auth: admin role فقط، عبر نفس نمط JWT الموجود).

**معايير القبول:** فتح لوحة خريطة الأدمن الحية وعمل تغيير حالة رحلة (مثلًا accept) من جهاز اختبار آخر → التحديث يظهر على خريطة الأدمن خلال أقل من ثانيتين بدون أي refresh يدوي.

**التقدير:** 6-8 أيام (يشمل بناء DO/قناة جديدة + تعديل واجهة React + اختبار end-to-end عبر الثلاث تطبيقات).

## 5. ميزات جديدة مقترحة (Uber / inDrive parity وما بعدها)

1. **Exactly-once semantics حقيقي لأحداث الرحلة الحرجة** (مبني فوق 4.1.1): إضافة طبقة idempotency على جانب العميل أيضًا — لما العميل يستلم event بـ `seq` أقل من أو يساوي آخر `seq` طبّقه بالفعل، يتجاهله تلقائيًا. هذا يحول الضمان الحالي (at-least-once على مستوى الشبكة، exactly-once فقط لو محظوظ) لضمان exactly-once فعلي على مستوى تطبيق الحدث، وهو المعيار اللي Uber بيلتزم بيه في نظام الرحلات الحية بتاعه.

2. **Presence heartbeat مرئي للراكب ("الكابتن متصل مباشرة الآن")**: مؤشر صغير في شاشة تتبع الرحلة يوضح "آخر تحديث موقع من X ثانية" (مبني على `lastSeq`/timestamp آخر `location.captain` مستلم)، بحيث الراكب يعرف بصريًا لو فيه تأخير في التحديث بدل ما يفترض إن الخريطة "حية 100%" دايمًا — شفافية زي اللي إن Drive بتقدمها في بعض الأسواق.

3. **Trip path replay/animation بعد اكتمال الرحلة**: استخدام `trip_path_points` (بعد إضافة `client_event_id` وربما `seq`) لعمل "إعادة تشغيل" بصري لمسار الرحلة بعد انتهائها — ميزة موجودة في Uber كجزء من شاشة "تفاصيل الرحلة"، وتفيد أيضًا فرق السلامة (track 12) في التحقيق بأي بلاغ.

4. **Graceful degradation متدرج (WS → polling → SMS/push كخط أخير)**: حاليًا الـ degradation بتوقف عند REST polling. إضافة مستوى ثالث: لو كابتن أو راكب فقد الاتصال بالكامل (مش WS ولا REST) لأكتر من فترة معينة أثناء رحلة نشطة، إرسال push notification حرج (بالتنسيق مع track 15) يحتوي على آخر حالة معروفة للرحلة، بحيث المستخدم يقدر يفتح التطبيق ويلاقي معلومة حديثة حتى لو مقدرش يستقبل بث حي في اللحظة دي.

5. **Server-side speed/heading sanity check لمنع GPS spoofing بسيط**: فحص بسيط في `POST /captain/location` (وربما في `GeoCell` نفسه) يرفض أو يعلّم بـ flag أي قفزة موقع تتجاوز سرعة فيزيائية معقولة (مثلًا > 200 كم/س بين تحديثين متتاليين) — دفاع أولي ضد تلاعب بسيط بالموقع، بالتنسيق مع track 13 (fraud/abuse) لتحديد العتبات والاستجابة الكاملة.

6. **Batch location upload endpoint مخصص** (مبني فوق 4.1.3): بدل ما الـ batching يكون آلية تعافي بس (queue بعد فشل)، يُفتح كـ ميزة عامة — العميل ممكن يجمّع 2-3 نقاط GPS في ثانية واحدة (لو بيتحرك بسرعة عالية في سياق معين) ويبعتهم دفعة واحدة، يقلل عدد الـ HTTP round-trips بدون التضحية بدقة العينة.

7. **آلية "catch-up snapshot" سريعة عند فتح شاشة تتبع الرحلة لأول مرة**: حاليًا `TripRoom` بيخزن `lastLocation` في `ctx.storage` ويرجعه لعميل جديد — ده أساس جيد. الإضافة المقترحة: توسيع الـ snapshot ده ليشمل آخر 10-20 نقطة من `trip_path_points` (مش بس آخر نقطة) عشان أي شاشة تتبع تفتح لأول مرة (بعد إعادة تشغيل التطبيق مثلًا) تقدر ترسم "ذيل" قصير لمسار الكابتن فورًا بدل نقطة واحدة معزولة.

8. **Adaptive server-side broadcast throttling بناءً على عدد المستمعين**: لو رحلة معينة (نادر، لكن ممكن في سياق مشاركة الرحلة العامة عبر `trip_share_tokens`) عندها عدد كبير غير معتاد من المستمعين على نفس `TripRoom`، إضافة throttling تكيفي (تقليل معدل بث `location.captain` تلقائيًا) لمنع تضخم غير متوقع في تكلفة الـ broadcast — ميزة استباقية وليست إصلاح مشكلة حالية مرصودة.

## 6. مخطط التنفيذ المرحلي

**المرحلة 1 (أسبوعان، لا تعتمد على أي تراك تاني):**
- 4.1.5 (حد الـ scan في GeoCell)
- 4.1.6 (توحيد نافذة الـ staleness)
- 4.1.7 (تحذير resolveTripId fallback)
- 4.1.3 (retry + offline queue للموقع) — يبدأ بالتوازي، مش معتمد على غيره

**المرحلة 2 (3-4 أسابيع، تعتمد على المرحلة 1 من ناحية الاستقرار الأساسي لكن مش تقنيًا):**
- 4.1.1 (sequence numbers + replay لـ TripRoom) — العمود الفقري لباقي خطة الموثوقية
- 4.1.2 (sequence numbers لـ CaptainInbox) — يبدأ فور استقرار نمط 4.1.1 (نفس الفريق يقدر يعيد استخدام نفس القرارات التصميمية)
- 4.1.8 (backstop polling لـ TripRoom WS)

**المرحلة 3 (2-3 أسابيع، تعتمد على المرحلة 2 لاستقرار مصدر الـ seq):**
- 4.2.1 (idempotency لـ trip_path_points)
- 4.2.2 (توحيد broadcastTrip لنداء واحد)
- 4.2.4 (pagination لـ GET /trips/:id/path)
- 4.1.4 (تقليل الاعتماد على proxy المزدوج في CaptainInbox + القياس)

**المرحلة 4 (مستمرة، رصد وقياس أولًا قبل قرار استثمار):**
- 4.2.3 (تصالح presence — رصد فقط في البداية)
- 4.2.5 (توحيد منطق التحقق من العضوية)

**المرحلة 5 (ميزات نضج، بعد استقرار الأساس بالكامل):**
- 4.3.1 (dead-reckoning)
- 4.3.2 (presence دقيق moving/stationary)
- 4.3.3 (admin live map WS) — يحتاج تنسيق مع track 16 (admin console) على مستوى واجهة React
- بنود القسم 5 (ميزات جديدة) — تُجدول لاحقًا حسب أولوية المنتج، خارج هذه الخطة التقنية البحتة

**اعتماديات على تراكات أخرى:**
- 4.1.5/4.1.6 (GeoCell) قد يحتاج تنسيق مع track 02 (matching) على القيمة النهائية لـ `PRESENCE_MAX_AGE_MS` بما إنها تؤثر مباشرة على "من المؤهل للعرض".
- 4.1.4 (تقليل الحاجة لـ pending-auth) يتقاطع مع أي عمل على تخزين التوكن في track 01 (security) — يُنسق قبل التنفيذ.
- 4.3.3 (admin live map) يحتاج عمل واجهة فعلي من track 16.
- 5.4 (graceful degradation عبر push) يعتمد كليًا على جاهزية track 15 لقناة push الحرجة.
- 5.5 (GPS sanity check) يحتاج تنسيق مع track 13 على العتبات والاستجابة.

## 7. القياس والتحقق

**اختبارات آلية جديدة مطلوبة:**
- اختبار تكامل: فتح WS، بث 3 أحداث، قطع الاتصال، إعادة الاتصال بـ `lastSeq` صحيح، التأكد من استلام الأحداث الفايتة بالترتيب الصحيح ومن غير تكرار (يغطي 4.1.1 و4.1.2).
- اختبار وحدة على `resolveTripId()`: كل مسار fallback (query param، storage، ctx.id.name، hex fallback) يُختبر منفردًا (يغطي 4.1.7).
- اختبار حمل بسيط على `GeoCell./nearby` بعدد entries متزايد (100، 500، 1000) للتأكد من استقرار زمن الاستجابة بعد وضع الحد الأعلى (يغطي 4.1.5).
- اختبار شبكة متذبذبة (network throttling/chaos) على `captain_state.dart` للتأكد من عمل الـ retry queue بدون فقدان بيانات (يغطي 4.1.3).
- اختبار رجعي شامل لكل مسارات `trips.ts` اللي بتنادي `broadcastTrip()` بعد التوحيد لنداء واحد (يغطي 4.2.2) — التأكد من عدم تغيير المحتوى المُبث رغم تغيير آلية النداء الداخلية.

**مقاييس (metrics) جديدة للوحة مراقبة (تنسيق مع track 17):**
- عدد الأحداث المستردة عبر `replay` لكل ساعة (مؤشر مباشر على حجم مشكلة الانقطاعات القصيرة قبل الإصلاح، ومؤشر نجاح الإصلاح بعده).
- نسبة الاتصالات على مسار `pendingAuth=1` في `CaptainInbox` (من 4.1.4).
- عدد المرات اللي `GeoCell./nearby` بتوصل لحد الـ `MAX_SCAN` الجديد (من 4.1.5).
- نسبة انحراف presence بين GeoCell وD1 (من 4.2.3).
- عدد فشل `pushLocationCoordinates` (قبل وبعد retry) — لقياس مدى تحسن معدل النجاح الفعلي (من 4.1.3).
- توزيع زمن استجابة `POST /sync` الجديد على TripRoom مقابل النداءين القديمين (من 4.2.2) — للتأكد من تحسن فعلي وليس مجرد نقل تكلفة.

**استراتيجية rollout/rollback:**
- كل تغيير في 4.1.1/4.1.2 (sequence numbers) يُنشر خلف feature flag على مستوى الـ Worker (متغير بيئة `ENABLE_WS_SEQUENCING`)، بحيث لو ظهرت مشكلة إنتاجية غير متوقعة (زي تضخم غير متوقع في حجم `trip_events` أو تعارض على العداد)، يمكن التراجع فورًا بإيقاف الـ flag من غير deployment جديد. العملاء (Dart) يُصمموا بحيث يتعاملوا مع غياب حقل `seq` في الرسائل بلطف (treat as "no replay support from server yet") — توافق خلفي كامل في الاتجاهين أثناء فترة الانتقال.
- التغييرات على `trip_path_points` (4.2.1، إضافة `client_event_id`) تُنفذ كـ additive migration فقط (عمود جديد nullable) — لا حاجة لأي rollback خاص، العمود القديم يستمر يعمل حتى لو الفرونت إند لسه مابعتش `clientEventId`.
- 4.2.2 (توحيد broadcastTrip) يُنشر مع إبقاء الـ endpoints القديمة (`/broadcast`, `/state`) فعّالة بالتوازي لمدة انتقالية (أسبوعين على الأقل في staging ثم production) قبل إزالتها نهائيًا، لضمان عدم كسر أي مسار لم يُكتشف أثناء التدقيق.

## 8. المخاطر والاعتماديات

- **خطر التزامن على عداد الـ `seq` (4.1.1):** لو تم اختيار تخزين العداد في D1 بدل `ctx.storage` الخاص بالـ DO، فيه احتمال race condition تحت حمل عالي (تعديلات متزامنة على نفس الرحلة). التخفيف: الاعتماد على `ctx.storage` الداخلي لكل DO instance (كل رحلة = instance واحدة = لا تزامن فعلي على نفس العداد، بما إن DOs بطبيعتها single-threaded لكل instance)، وهذا بالضبط سبب اختيار هذا التصميم في 4.1.1.
- **حجم `trip_events` سينمو بشكل ملحوظ** بعد تفعيل 4.1.1 (كل حدث بث يتخزن الآن، مش بس يتبث). التخفيف: سياسة احتفاظ (retention) — حذف صفوف `trip_events` للرحلات المكتملة بعد فترة معينة (30-60 يوم، بالتنسيق مع track 07 على سياسة الأرشفة العامة وtrack 22 على متطلبات الاحتفاظ بالبيانات في مصر).
- **اعتماد على قرار track 02 بخصوص `PRESENCE_MAX_AGE_MS`:** تغيير هذه القيمة (4.1.6) يؤثر مباشرة على معايير الأهلية في خوارزمية المطابقة. لازم تنسيق صريح قبل التنفيذ، وإلا احتمال تغيير سلوك المطابقة بشكل غير مقصود كأثر جانبي لتغيير هندسي كان الهدف منه إصلاح تعارض توقيت بسيط.
- **مخاطرة عدم اكتمال فحص خريطة الأدمن (4.3.3):** التدقيق الحالي لم يُثبت بشكل قاطع غياب أي وصلة DO مباشرة من `apps/admin` (الاستنتاج مبني على عدم العثور على دليل خلال التدقيق، وليس فحص شامل لكل ملف في `apps/admin`). قبل البدء في 4.3.3، يجب تأكيد الوضع الفعلي (قد يتقاطع مع عمل موجود بالفعل ضمن track 16) لتفادي ازدواجية الجهد.
- **اعتماد على جاهزية FCM الحقيقية (خارج نطاقي، track 15) لميزة "graceful degradation عبر push" (القسم 5، بند 4):** حسب `docs/ROADMAP.md`، مفاتيح FCM production لسه غير متوفرة وكل تكامل push حاليًا بيرجع لمسار stub/dev. هذه الميزة تبقى معلقة عمليًا لحد ما track 15 يُنجز جاهزية الإنتاج، رغم إن التصميم الهندسي (استدعاء نقطة تكامل push من طبقة الـ realtime عند اكتشاف انقطاع طويل) يمكن بناؤه وربطه بمسار الـ stub الحالي كخطوة تحضيرية.
- **مخاطرة الـ regression أثناء توحيد `broadcastTrip()` (4.2.2):** بما إن `broadcastTrip()` مستخدمة في عدد كبير من نقاط `trips.ts` (cancel, accept, arrived-start, complete, bid submit — مع تعليق كود صريح يحذر من نسيان استدعائها بعد bid submit تحديدًا لأنه كسر شاشة كاملة قبل كده)، أي خطأ في التوحيد يمكن أن يكرر نفس فئة الحادثة التاريخية. التخفيف: الإبقاء على المسارين القديمين فعّالين بالتوازي مؤقتًا (موضح في القسم 7) وتغطية اختبارية شاملة لكل نقطة استدعاء قبل إزالة المسار القديم نهائيًا.
