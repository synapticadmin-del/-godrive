-- Migration 0020: a payout request is a queue entry, not a debit
--
-- Gate item 4. Until this migration, POST /captain/wallet/payout removed money
-- from users.wallet_balance at request time and recorded it as a
-- wallet_transactions row with status='pending'
-- (apps/api/src/routes/wallet.ts:113-130 at 149271dd). No endpoint and no screen
-- could ever action that row: there is no disbursement API and no bank-account
-- storage anywhere in the product. Three tracks filed it independently -- T03
-- F-03-08, T04 F-04-06, T11 F-11-04 -- because it accrues silent, unbounded
-- liability to captains from the first day captains exist.
--
-- The request now lives in its own table and the balance is untouched until an
-- operator settles it. That restores the meaning wallet_transactions is supposed
-- to have: a row there is money that has actually moved.
--
-- NO BACKFILL. The stranded pre-existing rows are deliberately left exactly as
-- they are, to be reconciled by hand against the query in the PR description.
-- Migrations 0005, 0009, 0017 and 0018 carry irreversible backfills; this is
-- explicitly not a fifth.
--
-- Rollback: migrations are forward-only. While no request has been settled,
-- `DROP TABLE payout_requests;` is a complete reversal -- nothing else in the
-- schema references this table. Once settled rows exist, the ledger rows they
-- produced are ordinary wallet_transactions and the correct recovery is the
-- restore rehearsed under E18, not a drop.

CREATE TABLE IF NOT EXISTS payout_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Both money columns. The codebase is midway through the REAL -> integer
  -- piastres migration started in 0005, and the ledger this table feeds
  -- (wallet_transactions) still carries both, so this table does too. The CHECK
  -- below makes them incapable of drifting apart.
  amount REAL NOT NULL CHECK (amount > 0),
  amount_piastres INTEGER NOT NULL CHECK (amount_piastres > 0),
  currency TEXT NOT NULL DEFAULT 'EGP',

  method TEXT NOT NULL CHECK (method IN ('bank_transfer', 'vodafone_cash', 'instapay', 'fawry')),
  account_info TEXT NOT NULL,

  -- Three states, every one of them reachable: 'requested' on create, 'paid' or
  -- 'rejected' from the operator console (E14). No unreachable state is defined
  -- here. An unreachable state is root R3, and a row parked in one is precisely
  -- the defect this migration exists to end.
  status TEXT NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested', 'paid', 'rejected')),

  idempotency_key TEXT NOT NULL,

  -- Set when, and only when, the request is paid: the ledger row that actually
  -- moved the money. A paid request can therefore always name its own debit.
  wallet_transaction_id TEXT REFERENCES wallet_transactions(id) ON DELETE SET NULL,

  decided_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  decided_at TEXT,
  decision_reason TEXT,

  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),

  -- The two money columns describe the same amount.
  CHECK (amount_piastres = CAST(ROUND(amount * 100) AS INTEGER)),

  -- A decided request must record who decided it, when, and why. E14's console
  -- is the only caller and "neither action is possible without a recorded reason
  -- and actor" is its acceptance criterion; enforcing it here means no future
  -- caller can quietly skip it either.
  CHECK (
    status = 'requested'
    OR (decided_by IS NOT NULL
        AND decided_at IS NOT NULL
        AND TRIM(COALESCE(decision_reason, '')) <> '')
  ),

  -- Paid without a ledger row would be exactly the invisible-money-movement
  -- this table was created to prevent.
  CHECK (status <> 'paid' OR wallet_transaction_id IS NOT NULL)
);

-- Idempotency is scoped to OPEN requests. A captain must not be able to stack
-- two identical outstanding withdrawals, but may legitimately request the same
-- amount again once the first has been paid or rejected. A plain UNIQUE index
-- across the whole column would forbid that second request forever.
CREATE UNIQUE INDEX IF NOT EXISTS idx_payout_requests_open_idem
  ON payout_requests(idempotency_key) WHERE status = 'requested';

-- The captain's own history.
CREATE INDEX IF NOT EXISTS idx_payout_requests_user
  ON payout_requests(user_id, status, created_at);

-- E14's operator queue: open requests, oldest first.
CREATE INDEX IF NOT EXISTS idx_payout_requests_queue
  ON payout_requests(status, created_at);
