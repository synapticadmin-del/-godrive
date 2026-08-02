/**
 * A `D1Database` surface over `node:sqlite`, plus a real-migration loader.
 *
 * This is **not** a behavioural mock. Every statement the source issues is
 * executed verbatim by real SQLite and `meta.changes` is real, which is what
 * makes the compare-and-swap and `UNIQUE`-index assertions meaningful. What it
 * does not model is `workerd`, the network, or D1's own consistency semantics —
 * which is precisely why the shipped suite is `@cloudflare/vitest-pool-workers`
 * and this file is only local evidence.
 */
import { DatabaseSync } from "node:sqlite";
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
/** apps/api/test/tools → repository root → migrations/ */
export const MIGRATIONS_DIR = join(HERE, "..", "..", "..", "..", "migrations");

/** Split a .sql file into statements, honouring BEGIN…END trigger bodies. */
function splitStatements(sql) {
  const out = [];
  let buf = "";
  let depth = 0;
  for (const rawLine of sql.split("\n")) {
    const line = rawLine.replace(/--.*$/, "");
    if (!line.trim()) {
      buf += "\n";
      continue;
    }
    buf += rawLine + "\n";
    if (/\bBEGIN\b/i.test(line) && !/\bEND\s*;/i.test(line)) depth++;
    if (/\bEND\s*;/i.test(line)) depth = Math.max(0, depth - 1);
    if (depth === 0 && /;\s*$/.test(line.trim())) {
      out.push(buf);
      buf = "";
    }
  }
  if (buf.trim()) out.push(buf);
  return out.filter((s) => s.replace(/--.*$/gm, "").trim().length);
}

/** A fresh in-memory database with every migration applied, in order. */
export function freshDb() {
  const db = new DatabaseSync(":memory:");
  db.exec("PRAGMA foreign_keys = ON;");
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith(".sql")).sort();
  for (const f of files) {
    const sql = readFileSync(join(MIGRATIONS_DIR, f), "utf8").replace(/^﻿/, "");
    for (const stmt of splitStatements(sql)) {
      try {
        db.exec(stmt);
      } catch (e) {
        throw new Error(`migration ${f} failed: ${e.message}\n${stmt.slice(0, 300)}`);
      }
    }
  }
  const tables = db.prepare("SELECT count(*) c FROM sqlite_master WHERE type='table'").get().c;
  return { db, applied: files.length, total: files.length, tables };
}

function norm(v) {
  if (v === undefined || v === null) return null;
  if (typeof v === "boolean") return v ? 1 : 0;
  return v;
}

class Stmt {
  constructor(db, sql, values = []) {
    this.db = db;
    this.sql = sql;
    this.values = values;
  }
  bind(...values) {
    return new Stmt(this.db, this.sql, values.map(norm));
  }
  async run() {
    const r = this.db.prepare(this.sql).run(...this.values);
    return {
      success: true,
      meta: { changes: Number(r.changes ?? 0), last_row_id: Number(r.lastInsertRowid ?? 0) },
    };
  }
  async first(col) {
    const row = this.db.prepare(this.sql).get(...this.values);
    if (row === undefined) return null;
    return col ? row[col] : row;
  }
  async all() {
    return { success: true, results: this.db.prepare(this.sql).all(...this.values), meta: {} };
  }
}

export function makeD1(sqlite) {
  return {
    prepare: (sql) => new Stmt(sqlite, sql),
    async batch(stmts) {
      sqlite.exec("BEGIN");
      try {
        const out = [];
        for (const s of stmts) out.push(await s.run());
        sqlite.exec("COMMIT");
        return out;
      } catch (e) {
        sqlite.exec("ROLLBACK");
        throw e;
      }
    },
    async exec(sql) {
      sqlite.exec(sql);
      return { count: 0, duration: 0 };
    },
  };
}
