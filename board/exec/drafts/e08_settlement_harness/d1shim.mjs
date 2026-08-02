// A D1Database shim over node:sqlite, good enough to run the real
// apps/api/src/lib code unmodified against a real SQLite file with the real
// migrations applied. Implements only what settlement.ts / money.ts / audit.ts
// touch: prepare/bind/run/first/all, batch (as one transaction), exec.
import { DatabaseSync } from "node:sqlite";

class Stmt {
  constructor(db, sql, values = []) {
    this.db = db;
    this.sql = sql;
    this.values = values;
  }
  bind(...values) {
    return new Stmt(this.db, this.sql, values);
  }
  _prep() {
    return this.db.prepare(this.sql);
  }
  async run() {
    const r = this._prep().run(...this.values);
    return {
      success: true,
      results: [],
      meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) },
    };
  }
  async first(col) {
    const row = this._prep().get(...this.values);
    if (row === undefined) return null;
    return col === undefined ? row : row[col];
  }
  async all() {
    const rows = this._prep().all(...this.values);
    return { success: true, results: rows, meta: { changes: 0 } };
  }
}

export class D1 {
  constructor(path = ":memory:") {
    this.db = new DatabaseSync(path);
    this.db.exec("PRAGMA foreign_keys = ON");
  }
  prepare(sql) {
    return new Stmt(this.db, sql);
  }
  exec(sql) {
    this.db.exec(sql);
    return { count: 0, duration: 0 };
  }
  // D1 runs a batch as a single transaction.
  async batch(stmts) {
    this.db.exec("BEGIN");
    try {
      const out = [];
      for (const s of stmts) out.push(await s.run());
      this.db.exec("COMMIT");
      return out;
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
  }
}
