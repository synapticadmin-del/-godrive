# REVIEW_PLAN — Synaptic Go
## خطة المراجعة التفصيلية الموزّعة على شاتات

28 independent tasks. No task depends on another's output. Any chat may claim
any unclaimed task; the lowest-numbered one is the convention.

**Before you touch this file: it is read-only.** Your only write on this branch
is your own `board/claims/TNN.md`. See `board/PROTOCOL.md`.

| | |
|---|---|
| Repo | `synapticadmin-del/-godrive` |
| Base branch | `main` |
| Board branch | `review-board` |
| Deliverable | one document per task at `docs/plan/NN-slug.md`, one PR into `main` |
| Central record | every chat appends its summary block to `PROJECT.md` at the repo root |
| Phase | **review + plan only** — no product code changes in these PRs |

---

## Task index

> **T27 and T28 were added after the first round.** They sit at the end of the
> numbering, so the auto-claim order reaches them last. If you want them early,
> use the pinned-task prompt in `board/NEW_CHAT_PROMPT.md`.


### A — Foundation & safety-critical

| Task | Title | العنوان | Branch | Brief |
|---|---|---|---|---|
| **T01** | Auth, Identity & Sessions | المصادقة والهوية والجلسات | `plan/01-auth-identity-sessions` | [`tasks/T01.md`](tasks/T01.md) |
| **T02** | Authorization, RBAC & Object-Level Access | الصلاحيات والتحكم في الوصول | `plan/02-authorization-rbac-idor` | [`tasks/T02.md`](tasks/T02.md) |
| **T03** | Money Integrity — Wallet, Ledger & Commission | سلامة الأموال — المحفظة ودفتر الحسابات | `plan/03-money-integrity-wallet-ledger` | [`tasks/T03.md`](tasks/T03.md) |
| **T04** | Payments, PSP Integration & Captain Payouts | المدفوعات والتحصيل وصرف مستحقات الكباتن | `plan/04-payments-psp-payouts` | [`tasks/T04.md`](tasks/T04.md) |
| **T05** | Pricing, Surge & Bidding Economics | التسعير والمزايدة واقتصاديات الرحلة | `plan/05-pricing-surge-bidding-economics` | [`tasks/T05.md`](tasks/T05.md) |
| **T06** | Dispatch & Matching Engine | محرك التوزيع ومطابقة الرحلات | `plan/06-dispatch-matching-engine` | [`tasks/T06.md`](tasks/T06.md) |
| **T07** | Realtime — Durable Objects & WebSockets | الاتصال الحي — Durable Objects والويب سوكيت | `plan/07-realtime-durable-objects-ws` | [`tasks/T07.md`](tasks/T07.md) |
| **T08** | Data Model, Migrations & Integrity | نموذج البيانات والهجرات وسلامتها | `plan/08-data-model-migrations-integrity` | [`tasks/T08.md`](tasks/T08.md) |

### B — Product surface & experience

| Task | Title | العنوان | Branch | Brief |
|---|---|---|---|---|
| **T09** | Rider App — End-to-End Journey | تطبيق الراكب — الرحلة الكاملة | `plan/09-rider-app-journey` | [`tasks/T09.md`](tasks/T09.md) |
| **T10** | Captain App — End-to-End Journey | تطبيق الكابتن — الرحلة الكاملة | `plan/10-captain-app-journey` | [`tasks/T10.md`](tasks/T10.md) |
| **T11** | Admin Console & Operations Tooling | لوحة التحكم وأدوات التشغيل | `plan/11-admin-operations-console` | [`tasks/T11.md`](tasks/T11.md) |
| **T12** | Design System & Visual Language | نظام التصميم واللغة البصرية | `plan/12-design-system-visual-language` | [`tasks/T12.md`](tasks/T12.md) |
| **T13** | Motion, Micro-interactions & Perceived Performance | الحركة والتفاعلات الدقيقة والأداء المُدرَك | `plan/13-motion-micro-interactions` | [`tasks/T13.md`](tasks/T13.md) |
| **T14** | Localisation, RTL & Content Design | التعريب والاتجاه والمحتوى | `plan/14-i18n-rtl-content` | [`tasks/T14.md`](tasks/T14.md) |
| **T15** | Accessibility & Inclusive Design | إتاحة الاستخدام والتصميم الشامل | `plan/15-accessibility-inclusive-design` | [`tasks/T15.md`](tasks/T15.md) |
| **T27** | Cross-App Parity — Rider ↔ Captain ↔ Admin | مطابقة التطبيقين مع بعض والاتساق الكامل | `plan/27-cross-app-parity-consistency` | [`tasks/T27.md`](tasks/T27.md) |
| **T28** | Motion Development — Shared Animation Library & Signature Moments | تطوير الموشن — مكتبة الحركة المشتركة واللحظات المميّزة | `plan/28-motion-development-build` | [`tasks/T28.md`](tasks/T28.md) |

### C — Feature parity & new capability

| Task | Title | العنوان | Branch | Brief |
|---|---|---|---|---|
| **T16** | Trip Lifecycle — Feature Gap vs Uber & inDrive | دورة حياة الرحلة — الفجوة مقابل أوبر وإن درايف | `plan/16-trip-lifecycle-feature-gap` | [`tasks/T16.md`](tasks/T16.md) |
| **T17** | Safety, Trust & Two-Sided Accountability | الأمان والثقة والمساءلة | `plan/17-safety-trust-ratings` | [`tasks/T17.md`](tasks/T17.md) |
| **T18** | Fraud, Abuse & Risk Engine | الاحتيال وإساءة الاستخدام وإدارة المخاطر | `plan/18-fraud-abuse-risk` | [`tasks/T18.md`](tasks/T18.md) |
| **T19** | Growth, Notifications & Lifecycle Messaging | النمو والإشعارات ورسائل دورة حياة المستخدم | `plan/19-growth-notifications-lifecycle` | [`tasks/T19.md`](tasks/T19.md) |
| **T20** | Intercity, B2B & New Verticals | الرحلات بين المدن والشركات والقطاعات الجديدة | `plan/20-intercity-b2b-new-verticals` | [`tasks/T20.md`](tasks/T20.md) |

### D — Engineering excellence & production readiness

| Task | Title | العنوان | Branch | Brief |
|---|---|---|---|---|
| **T21** | Maps, Routing & Geospatial Accuracy | الخرائط والمسارات ودقة الموقع | `plan/21-maps-routing-geo-accuracy` | [`tasks/T21.md`](tasks/T21.md) |
| **T22** | Observability, Operations & Incident Response | المراقبة والتشغيل والاستجابة للحوادث | `plan/22-observability-operations` | [`tasks/T22.md`](tasks/T22.md) |
| **T23** | Testing, CI/CD & Release Safety | الاختبارات والتكامل المستمر وأمان الإصدار | `plan/23-testing-ci-cd-release-safety` | [`tasks/T23.md`](tasks/T23.md) |
| **T24** | Performance, Cost & Scale | الأداء والتكلفة وقابلية التوسّع | `plan/24-performance-cost-scale` | [`tasks/T24.md`](tasks/T24.md) |
| **T25** | Privacy, Compliance & Legal Readiness | الخصوصية والامتثال والجاهزية القانونية | `plan/25-privacy-compliance-legal` | [`tasks/T25.md`](tasks/T25.md) |
| **T26** | Mobile Release Engineering & Store Readiness | هندسة إصدار التطبيقات والجاهزية للمتاجر | `plan/26-mobile-release-store-readiness` | [`tasks/T26.md`](tasks/T26.md) |


---

## Status

There is no status column here on purpose — a shared status table is a write
conflict waiting to happen when ten chats update it at once.

**The claims folder is the status board.** List `board/claims/` to see what is
taken. Each claim file carries `status`, `claimed_by`, `claimed_at_utc` and,
once finished, the `pr` link.

---

## Sequencing advice (for the human, not a constraint on chats)

Track A is what blocks production: money, auth, dispatch, data. Run those
chats first if you are running a limited number in parallel. Track B is what
makes people come back. Track C is what makes the product competitive. Track D
is what lets a small team operate it without fear.

Nothing enforces this order. The claim protocol simply hands out the lowest
unclaimed number, so starting chats in bursts naturally drains A, then B, then
C, then D.
