import { DurableObject } from "cloudflare:workers";
import { haversineKm } from "@synaptic-go/shared";

type CaptainPresence = {
  userId: string;
  lat: number;
  lng: number;
  lastSeen: number;
  name?: string | null;
};

/**
 * One Durable Object per geohash cell in a city.
 * Tracks online captains for matching.
 */
export class GeoCell extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/heartbeat" && request.method === "POST") {
      const body = await request.json<CaptainPresence>();
      const key = `captain:${body.userId}`;
      const record: CaptainPresence = {
        userId: body.userId,
        lat: body.lat,
        lng: body.lng,
        lastSeen: Date.now(),
        name: body.name ?? null,
      };
      await this.ctx.storage.put(key, record);
      // auto-expire stale after 3 minutes via alarm
      const currentAlarm = await this.ctx.storage.getAlarm();
      if (currentAlarm == null) {
        await this.ctx.storage.setAlarm(Date.now() + 60_000);
      }
      return Response.json({ ok: true });
    }

    if (url.pathname === "/offline" && request.method === "POST") {
      const body = await request.json<{ userId: string }>();
      await this.ctx.storage.delete(`captain:${body.userId}`);
      return Response.json({ ok: true });
    }

    if (url.pathname === "/nearby" && request.method === "GET") {
      const lat = Number(url.searchParams.get("lat"));
      const lng = Number(url.searchParams.get("lng"));
      const limit = Number(url.searchParams.get("limit") || "10");
      const maxAgeMs = Number(url.searchParams.get("maxAgeMs") || "120000");

      const list = await this.ctx.storage.list<CaptainPresence>({ prefix: "captain:" });
      const now = Date.now();
      const captains: Array<CaptainPresence & { distanceKm: number }> = [];

      for (const [, c] of list) {
        if (now - c.lastSeen > maxAgeMs) continue;
        const distanceKm = haversineKm({ lat, lng }, { lat: c.lat, lng: c.lng });
        captains.push({ ...c, distanceKm });
      }

      captains.sort((a, b) => a.distanceKm - b.distanceKm);
      return Response.json({ captains: captains.slice(0, limit) });
    }

    return new Response("GeoCell: /heartbeat /offline /nearby", { status: 400 });
  }

  async alarm() {
    const list = await this.ctx.storage.list<CaptainPresence>({ prefix: "captain:" });
    const now = Date.now();
    const toDelete: string[] = [];
    for (const [key, c] of list) {
      if (now - c.lastSeen > 180_000) toDelete.push(key);
    }
    if (toDelete.length) await this.ctx.storage.delete(toDelete);

    const remaining = await this.ctx.storage.list({ prefix: "captain:" });
    if ([...remaining.keys()].length > 0) {
      await this.ctx.storage.setAlarm(Date.now() + 60_000);
    }
  }
}
