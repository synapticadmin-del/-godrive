/**
 * Trip settlement — the balance moves that a completed trip causes.
 *
 * E03 lifted this out of the `POST /trips/:id/complete` handler unchanged, bugs
 * included, because a pure refactor that also fixes things is unreviewable.
 * This is **E08**, the task that file's header named: it fixes them.
 *
 * ## What changed, and why each one is here
 *
 * **1. Settlement resolves the price that was agreed.** `trips.offered_price`
 * (`migrations/0004:16`) is the rider's named price. It is written at
 * `routes/trips.ts:409` and — verified by grep across `apps/api/src` at base
 * `c0ce174` — **read nowhere in the codebase**. So on the direct-accept path,
 * where no bid row exists and `accepted_price` is therefore null, settlement
 * fell through to `estimated_fare` and paid a different number from the one the
 * captain accepted. That is T05 F-05-01, and its author calls it the most
 * important finding in that document because it breaks the product's
 * differentiator silently. [resolveTripSettlement] puts `offered_price` in the
 * chain.
 *
 * **This half of gate item 6 is the primitive only.** The completion handler
 * still computes its own `finalFare` at `routes/trips.ts:873` and passes it in;
 * that line, and the `/trips/:id/accept` handler at `routes/trips.ts:733`, are
 * in `routes/trips.ts`, which **E09** owns. Until E09 flips the call site the
 * corrected number is available and unused. A caller-supplied price that
 * disagrees with the resolved one is counted and logged (see
 * `settlement.price_mismatch` below) so the gap is visible on `main` rather
 * than merely documented. **Do not close gate item 6 on this PR.**
 *
 * **2. Every balance-moving statement goes through `moveMoney()`.** Root R1 —
 * see `lib/money.ts` for the idiom and for what each of the three hand-rolled
 * versions in this file got wrong. The rider debit's was the expensive one: it
 * updated the balance *before* taking the idempotency lock, so a retried
 * completion debited the rider twice.
 *
 * **3. The cash commission debit has a floor.** It was the one debit in the
 * codebase with none (F-03-11 / F-04-12, promoted to G1), and under the
 * cash-only launch shape it is the only live money path.
 *
 * **4. A completed trip writes an audit row** — `logAudit` with
 * `critical: true`, the flag E12 added for exactly this call site. `trips.ts:22`
 * imports `logAudit` and never calls it (F-22-05); deleting that dead import is
 * E09's line, not this task's.
 *
 * ## What deliberately did not change
 *
 * The wallet payment path is **G1‡ — disabled, not fixed.** E04 narrows the
 * payment-method enum in `lib/schemas.ts` so `wallet` and `card` are rejected at
 * the edge, which is what quarantines this branch; it is unreachable for new
 * trips under the launch shape. It has not been redesigned here, and it still
 * needs a real hold/capture/refund model in Wave 2. One consequence of the old
 * shape was **not** left in place: when the rider's debit failed the code
 * carried on and credited the captain anyway, so the platform minted the fare.
 * A live money-minting path cannot ship behind an enum, so the captain's credit
 * is now withheld when the rider's debit did not settle. See the PR for the
 * reasoning; this is the one place where "leave the wallet-path mint in place"
 * was read as "do not redesign the wallet path" rather than "leave the mint
 * live".
 */

import type { DbTrip } from "./types";
import { logAudit } from "./audit";
import { counter, logWarn } from "./log";
import { moveMoney, recordFailedMove, type MoveMoneyResult } from "./money";

/**
 * A trip row as settlement needs to see it.
 *
 * `DbTrip` in `lib/types.ts` has no `offered_price`, although the column has
 * existed since `migrations/0004:16` and `routes/trips.ts:409` writes it on
 * every booking. `lib/types.ts` is in **no task's `owns:`** for this wave
 * (WAVE-PLAN §8), so the field is declared here instead of being added there.
 * That is a reporting matter, not a workaround: see the PR's seam note.
 */
export type SettlementTrip = DbTrip & {
  /** The rider's named price. `trips.offered_price`, `migrations/0004:16`. */
  offered_price?: number | null;
};

/** Which column the settled price came from. Recorded on the audit row. */
export type SettlementPriceSource =
  /** A captain's counter-offer the rider accepted (`POST /trips/:id/accept-bid`). */
  | "accepted_price"
  /** The rider's named price, accepted directly by a captain. */
  | "offered_price"
  /** Already-settled trips being re-read. */
  | "final_fare"
  /** No negotiated price on the row. */
  | "estimated_fare"
  /** Nothing priced this trip at all. */
  | "none";

export type ResolvedSettlement = {
  /** The price to settle, in EGP. */
  agreedPrice: number;
  priceSource: SettlementPriceSource;
  /** Platform commission on `agreedPrice`, in EGP. */
  commission: number;
  /** `"stored"` — the row's own value. `"rescaled"` — see [resolveTripSettlement]. */
  commissionSource: "stored" | "rescaled" | "absent";
  /** What the captain is owed on a non-cash trip: `agreedPrice - commission`, never negative. */
  captainPayout: number;
};

const round2 = (n: number): number => Math.round(n * 100) / 100;

/**
 * Resolve what a completed trip is actually worth, and to whom.
 *
 * ## Price precedence
 *
 * `accepted_price` → `offered_price` → `final_fare` → `estimated_fare` → `0`.
 *
 * `accepted_price` leads because it is the only one both parties explicitly
 * agreed to — the rider picked that captain's counter-offer. `offered_price` is
 * next: the rider named it, and on the direct-accept path it is the number the
 * captain's trip row carried when they took the job (`routes/trips.ts:539`
 * serves captains `SELECT *`).
 *
 * Adding `offered_price` to the chain is **narrower than it looks.**
 * `routes/trips.ts:401` sets `offered_price = body.offeredPrice || finalEstimate`,
 * so it is populated on every booking and equals `estimated_fare` whenever the
 * rider did not name a price. The resolved number therefore only differs from
 * today's on trips where the rider actually made an offer — which is precisely
 * the case F-05-01 is about.
 *
 * ## Commission
 *
 * Settling price X while taking commission computed from Y pays the captain the
 * wrong number, so the two have to agree. The commission stored on the row was
 * computed at booking from `estimated_fare` (`routes/trips.ts:392`) and, on the
 * bid path only, recomputed from the accepted price
 * (`routes/trips.ts:1143`). So:
 *
 * - source `accepted_price` → the stored commission already matches. Keep it.
 * - source `offered_price` → the stored commission is still on the
 *   `estimated_fare` basis. Rescale it at **the same effective rate the booking
 *   used** (`commission / estimated_fare`), so the platform's percentage take is
 *   unchanged and no rate has to be read from `pricing_rules` — a table this
 *   task cannot reach.
 * - anything else → keep the stored value.
 *
 * Pure: no database, no clock. This is the function E19's test drives.
 */
export function resolveTripSettlement(trip: SettlementTrip): ResolvedSettlement {
  const candidates: Array<[SettlementPriceSource, number | null | undefined]> = [
    ["accepted_price", trip.accepted_price],
    ["offered_price", trip.offered_price],
    ["final_fare", trip.final_fare],
    ["estimated_fare", trip.estimated_fare],
  ];

  let agreedPrice = 0;
  let priceSource: SettlementPriceSource = "none";
  for (const [source, value] of candidates) {
    if (typeof value === "number" && Number.isFinite(value)) {
      agreedPrice = round2(value);
      priceSource = source;
      break;
    }
  }

  const storedCommission =
    typeof trip.commission === "number" && Number.isFinite(trip.commission)
      ? round2(trip.commission)
      : null;
  const basis =
    typeof trip.estimated_fare === "number" && Number.isFinite(trip.estimated_fare)
      ? trip.estimated_fare
      : 0;

  let commission = storedCommission ?? 0;
  let commissionSource: ResolvedSettlement["commissionSource"] =
    storedCommission === null ? "absent" : "stored";

  if (
    priceSource === "offered_price" &&
    storedCommission !== null &&
    basis > 0 &&
    round2(basis) !== agreedPrice
  ) {
    commission = round2(agreedPrice * (storedCommission / basis));
    commissionSource = "rescaled";
  }

  // A commission may not exceed the fare; the captain's share floors at zero.
  commission = Math.min(Math.max(commission, 0), agreedPrice);

  return {
    agreedPrice,
    priceSource,
    commission,
    commissionSource,
    captainPayout: Math.max(0, round2(agreedPrice - commission)),
  };
}

export type SettleTripCompletionInput = {
  db: D1Database;
  /** The trip row as read *before* the completion UPDATE. */
  trip: SettlementTrip;
  tripId: string;
  /**
   * The price to settle. **Optional.** Omit it and the primitive resolves the
   * agreed price itself, which is what E09 should do once it owns the call
   * site. Supplying it keeps today's behaviour byte-for-byte; a value that
   * disagrees with the resolved one is counted and logged, not silently used.
   */
  finalFare?: number;
  /** Optional; defaults to the resolved commission. */
  commission?: number;
  /** Optional; defaults to the resolved payout. */
  captainPayout?: number;
  /** Correlation id, when the caller has one (`getRequestId(c)`). */
  requestId?: string;
};

export type SettlementOutcome = ResolvedSettlement & {
  /** The amount actually settled — the caller's, when it supplied one. */
  settledPrice: number;
  riderDebit?: MoveMoneyResult;
  captainMove?: MoveMoneyResult;
  /**
   * True when the captain's credit was deliberately skipped because the rider's
   * debit did not settle. This is the mint, refusing to happen.
   */
  creditWithheld: boolean;
  /** True when a cash commission could not be taken without breaching the floor. */
  commissionUncollected: boolean;
};

/**
 * Apply the wallet consequences of a completed trip.
 *
 * The caller keeps the `trips` UPDATE, the `trip_events` write and the
 * completion pushes; this function is only the money — and now the audit row
 * that proves what the money did.
 */
export async function settleTripCompletion({
  db,
  trip,
  tripId,
  finalFare,
  commission: commissionArg,
  captainPayout: captainPayoutArg,
  requestId,
}: SettleTripCompletionInput): Promise<SettlementOutcome> {
  const resolved = resolveTripSettlement(trip);

  // The caller still owns the number today. Where it disagrees with the agreed
  // price, that *is* F-05-01 happening — make it countable rather than silent.
  if (finalFare !== undefined && Math.abs(finalFare - resolved.agreedPrice) >= 0.005) {
    counter("settlement_price_mismatch", 1, { source: resolved.priceSource });
    logWarn("settlement.price_mismatch", {
      tripId,
      requestId,
      callerFare: finalFare,
      agreedPrice: resolved.agreedPrice,
      priceSource: resolved.priceSource,
      reason:
        "caller settled a different number from the agreed price; E09 owns the call site at routes/trips.ts:873",
    });
  }

  const settledPrice = finalFare ?? resolved.agreedPrice;
  const commission = commissionArg ?? resolved.commission;
  const captainPayout = captainPayoutArg ?? resolved.captainPayout;

  let riderDebit: MoveMoneyResult | undefined;
  let captainMove: MoveMoneyResult | undefined;
  let creditWithheld = false;
  let commissionUncollected = false;

  // ── Rider leg ────────────────────────────────────────────────────────────
  // G1‡ — the wallet path is disabled by E04's enum narrowing, not repaired.
  // Unreachable for new trips; kept for rows booked before the launch shape.
  if (trip.payment_method === "wallet" && !trip.billed_to_company && trip.rider_id) {
    riderDebit = await moveMoney({
      db,
      userId: trip.rider_id,
      type: "trip_payment",
      direction: "debit",
      amount: settledPrice,
      idempotencyKey: `trip_debit:${tripId}`,
      tripId,
      note: "رحلة مكتملة",
      floor: 0,
    });

    if (!riderDebit.moved && riderDebit.reason === "insufficient_funds") {
      // A distinct key on purpose. The old code wrote the failure under
      // `trip_debit:<id>`, which burned the real key: a retry after the rider
      // topped up could never insert the settled row.
      await recordFailedMove({
        db,
        userId: trip.rider_id,
        type: "trip_payment",
        direction: "debit",
        amount: settledPrice,
        idempotencyKey: `trip_debit_failed:${tripId}`,
        tripId,
        note: "فشل الخصم - رصيد غير كافٍ",
      });
      creditWithheld = true;
    }
  }

  // ── Captain leg ──────────────────────────────────────────────────────────
  if (trip.captain_id) {
    if (trip.payment_method === "cash") {
      // The captain took the whole fare in hand, so the platform debits its
      // commission rather than crediting a payout. Crediting here would pay the
      // captain twice and forfeit the commission.
      if (commission > 0) {
        captainMove = await moveMoney({
          db,
          userId: trip.captain_id,
          type: "commission",
          direction: "debit",
          amount: commission,
          idempotencyKey: `trip_commission_debit:${tripId}`,
          tripId,
          note: "عمولة المنصة على رحلة نقدية",
          floor: 0,
        });

        if (!captainMove.moved && captainMove.reason === "insufficient_funds") {
          // The floor held. The debt is real, so leave a row for it rather than
          // dropping it — and make it countable, because uncollected commission
          // that nobody can see is how a balance sheet drifts.
          commissionUncollected = true;
          await recordFailedMove({
            db,
            userId: trip.captain_id,
            type: "commission",
            direction: "debit",
            amount: commission,
            idempotencyKey: `trip_commission_debit_failed:${tripId}`,
            tripId,
            note: "تعذّر خصم العمولة - رصيد غير كافٍ",
          });
          counter("commission_uncollected", 1, {});
          logWarn("settlement.commission_uncollected", {
            tripId,
            requestId,
            captainId: trip.captain_id,
            commission,
            reason: "captain balance below the floor; debit refused rather than driving it negative",
          });
        }
      }
    } else if (creditWithheld) {
      // The mint, refusing to happen. See the header.
      counter("settlement_credit_withheld", 1, {});
      logWarn("settlement.credit_withheld", {
        tripId,
        requestId,
        captainId: trip.captain_id,
        captainPayout,
        reason: "rider debit did not settle; crediting the captain here would mint the fare",
      });
    } else {
      captainMove = await moveMoney({
        db,
        userId: trip.captain_id,
        type: "commission",
        direction: "credit",
        amount: captainPayout,
        idempotencyKey: `trip_payout:${tripId}`,
        tripId,
        note: "أرباح رحلة مكتملة",
      });
    }
  }

  // ── The record ───────────────────────────────────────────────────────────
  // `critical: true` is E12's flag for a row whose loss has consequences; a
  // failure here is counted and logged at error rather than swallowed.
  await logAudit(db, {
    actorId: trip.captain_id ?? trip.rider_id ?? null,
    action: "trip.settled",
    entityType: "trip",
    entityId: tripId,
    critical: true,
    requestId,
    payload: {
      settledPrice,
      agreedPrice: resolved.agreedPrice,
      priceSource: resolved.priceSource,
      commission,
      commissionSource: resolved.commissionSource,
      captainPayout,
      paymentMethod: trip.payment_method,
      billedToCompany: trip.billed_to_company ?? 0,
      riderDebit: riderDebit
        ? { moved: riderDebit.moved, reason: riderDebit.reason, transactionId: riderDebit.transactionId }
        : null,
      captainMove: captainMove
        ? { moved: captainMove.moved, reason: captainMove.reason, transactionId: captainMove.transactionId }
        : null,
      creditWithheld,
      commissionUncollected,
    },
  });

  return {
    ...resolved,
    settledPrice,
    commission,
    captainPayout,
    riderDebit,
    captainMove,
    creditWithheld,
    commissionUncollected,
  };
}
