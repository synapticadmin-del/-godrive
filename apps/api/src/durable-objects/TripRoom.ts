import { DurableObject } from "cloudflare:workers";

type ClientRole = "rider" | "captain" | "admin" | "unknown";

type Session = {
  ws: WebSocket;
  role: ClientRole;
  userId?: string;
};

/**
 * One Durable Object per active trip.
 * Handles WebSocket fanout for live tracking + status events.
 */
export class TripRoom extends DurableObject<Env> {
  sessions: Map<WebSocket, Session> = new Map();

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/broadcast" && request.method === "POST") {
      const body = await request.json<Record<string, unknown>>();
      this.broadcast(body);
      return Response.json({ ok: true });
    }

    if (url.pathname === "/state" && request.method === "GET") {
      const state = (await this.ctx.storage.get("trip")) ?? null;
      return Response.json({ trip: state });
    }

    if (url.pathname === "/state" && request.method === "PUT") {
      const body = await request.json();
      await this.ctx.storage.put("trip", body);
      this.broadcast({ type: "trip.updated", trip: body });
      return Response.json({ ok: true });
    }

    if (request.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      this.ctx.acceptWebSocket(server);

      const role = (url.searchParams.get("role") as ClientRole) || "unknown";
      const userId = url.searchParams.get("userId") || undefined;
      this.sessions.set(server, { ws: server, role, userId });

      server.send(
        JSON.stringify({
          type: "connected",
          tripId: this.ctx.id.toString(),
          role,
        }),
      );

      return new Response(null, { status: 101, webSocket: client });
    }

    return new Response("TripRoom: use WebSocket or /broadcast|/state", { status: 400 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    if (typeof message !== "string") return;
    try {
      const data = JSON.parse(message) as {
        type?: string;
        lat?: number;
        lng?: number;
        heading?: number;
      };

      if (data.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", t: Date.now() }));
        return;
      }

      if (data.type === "location" && typeof data.lat === "number" && typeof data.lng === "number") {
        const session = this.sessions.get(ws);
        const payload = {
          type: "location.captain",
          lat: data.lat,
          lng: data.lng,
          heading: data.heading ?? null,
          userId: session?.userId ?? null,
          at: new Date().toISOString(),
        };
        await this.ctx.storage.put("lastLocation", payload);
        this.broadcast(payload, ws);
      }
    } catch {
      ws.send(JSON.stringify({ type: "error", message: "invalid message" }));
    }
  }

  async webSocketClose(ws: WebSocket) {
    this.sessions.delete(ws);
  }

  async webSocketError(ws: WebSocket) {
    this.sessions.delete(ws);
  }

  private broadcast(payload: unknown, except?: WebSocket) {
    const raw = JSON.stringify(payload);
    for (const [socket] of this.sessions) {
      if (except && socket === except) continue;
      try {
        socket.send(raw);
      } catch {
        this.sessions.delete(socket);
      }
    }
    // Also use hibernation API sockets
    for (const ws of this.ctx.getWebSockets()) {
      if (except && ws === except) continue;
      if (this.sessions.has(ws)) continue;
      try {
        ws.send(raw);
      } catch {
        /* ignore */
      }
    }
  }
}
