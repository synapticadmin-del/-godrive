import { id, nowIso } from "./utils";

export async function logAudit(
  db: D1Database,
  opts: {
    actorId?: string | null;
    action: string;
    entityType?: string;
    entityId?: string;
    payload?: unknown;
    ip?: string | null;
    userAgent?: string | null;
  },
): Promise<void> {
  try {
    await db
      .prepare(
        `INSERT INTO audit_log (id, actor_id, action, entity_type, entity_id, payload, ip, user_agent, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        id("aud"),
        opts.actorId ?? null,
        opts.action,
        opts.entityType ?? null,
        opts.entityId ?? null,
        opts.payload ? JSON.stringify(opts.payload) : null,
        opts.ip ?? null,
        opts.userAgent ?? null,
        nowIso(),
      )
      .run();
  } catch (e) {
    // Never break the main request because of audit failures.
    console.error("audit log failed", e);
  }
}
