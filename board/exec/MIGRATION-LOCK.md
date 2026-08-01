# MIGRATION-LOCK

D1 migrations serialise globally. Two chats picking `0020` from a directory listing is a guaranteed
collision, so the number comes from this file instead.

**Next free number: 0021**

To take one: `github__create_or_update_file` on this file **with** its `sha`, appending your row and
bumping the "next free number" line above. On `409`, re-read, take the next number, rename your file.

Migrations are forward-only. State the rollback in your PR (a forward repair migration, or a restore
rehearsed under E18). Migrations `0005`, `0009`, `0017` and `0018` contain irreversible backfills —
do not add a fifth without saying so explicitly.

| Number | Task | Chat | File | Merged |
|---|---|---|---|---|
| 0001–0019 | (pre-existing) | — | — | yes |
| 0020 | E06 | chat-20260801-1840-091b | `migrations/0020_payout_requests.sql` | no |
