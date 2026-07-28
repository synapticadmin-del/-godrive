import { DurableObject } from "cloudflare:workers";

type ClientRole = "rider" | "captain" | "admin" | "unknown";

type Session = {
  ws: WebSocket;
  role: ClientRole;
  userId?: string;
  /** True until the first-message {"type":"auth"} handshake completes. */
  pendingAuth?: boolean;
};

/** Max time a pending-auth socket may stay open before we close it (4401). */
const AUTH_TIMEOUT_MS = 10_000;

/**
 * One Durable Object per active trip.
 * Handles WebSocket fanout for live tracking + status events.
 *
 * Auth: the Worker route normally verifies the JWT (Authorization header or
 * the deprecated ?token= query param) and forwards role/userId here. When the
 * route forwards with ?pendingAuth=1 instead, the socket is accepted in a
 * pending state and the client must send {"type":"auth","token":"<jwt>"}
 * as its first message within AUTH_TIMEOUT_MS. Failure or timeout closes the
 * socket with code 4401.
 */
export class TripRoom extends DurableObject<Env> {
  sessions: Map<WebSocket, Session> = new Map();
  authTimers: Map<WebSocket, number> = new Map();

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

      if (url.searchParams.get("pendingAuth") === "1") {
        const tripId = url.searchParams.get("tripId") ?? this.ctx.id.toString();
        this.sessions.set(server, { ws: server, role: "unknown", pendingAuth: true });
        this.armAuthTimeout(server);
        server.send(
          JSON.stringify({ type: "auth.required", tripId, timeoutMs: AUTH_TIMEOUT_MS }),
        );
      } else {
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
      }

      return new Response(null, { status: 101, webSocket: client });
    }

    return new Response("TripRoom: use WebSocket or /broadcast|/state", { status: 400 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    if (typeof message !== "string") return;
    try {
      const data = JSON.parse(message) as {
        type?: string;
        token?: string;
        lat?: number;
        lng?: number;
        heading?: number;
      };

      const session = this.sessions.get(ws);

      if (session?.pendingAuth) {
        // Until authenticated the only acceptable message is the auth
        // handshake; everything else is dropped silently.
        if (data.type === "auth") {
          await this.completeAuth(ws, session, data.token);
        }
        return;
      }

      if (data.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", t: Date.now() }));
        return;
      }

      if (data.type === "location" && typeof data.lat === "number" && typeof data.lng === "number") {
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
    this.clearAuthTimeout(ws);
    this.sessions.delete(ws);
  }

  async webSocketError(ws: WebSocket) {
    this.clearAuthTimeout(ws);
    this.sessions.delete(ws);
  }

  /**
   * Verify the first-message JWT and complete the join flow. Mirrors the
   * checks the /ws/trips/:id route performs for header/query auth: token
   * validity, access-token type, then trip membership (rider/captain/admin).
   */
  private async completeAuth(ws: WebSocket, session: Session, token?: string) {
    const fail = () => {
      try {
        ws.send(JSON.stringify({ type: "auth.failed" }));
      } catch {
        /* ignore */
      }
      this.clearAuthTimeout(ws);
      this.sessions.delete(ws);
      ws.close(4401, "Unauthorized");
    };

    if (!token) {
      fail();
      return;
    }

    try {
      const { verifyToken } = await import("../lib/jwt");
      const user = await verifyToken(token, this.env.JWT_SECRET, this.env.JWT_ISSUER);
      if (user.typ === "refresh") {
        fail();
        return;
      }

      const tripId = this.ctx.id.toString();
      const trip = await this.env.DB.prepare(`SELECT rider_id, captain_id FROM trips WHERE id = ?`)
        .bind(tripId)
        .first<{ rider_id: string; captain_id: string }>();

      if (!trip || (user.role !== "admin" && trip.rider_id !== user.id && trip.captain_id !== user.id)) {
        fail();
        return;
      }

      this.clearAuthTimeout(ws);
      session.pendingAuth = false;
      session.role = user.role;
      session.userId = user.id;
      ws.send(JSON.stringify({ type: "connected", tripId, role: user.role }));
    } catch {
      fail();
    }
  }

  private armAuthTimeout(ws: WebSocket) {
    const timer = setTimeout(() => {
      const session = this.sessions.get(ws);
      if (session?.pendingAuth) {
        this.sessions.delete(ws);
        try {
          ws.close(4401, "Auth timeout");
        } catch {
          /* already closed */
        }
      }
      this.authTimers.delete(ws);
    }, AUTH_TIMEOUT_MS) as unknown as number;
    this.authTimers.set(ws, timer);
  }

  private clearAuthTimeout(ws: WebSocket) {
    const timer = this.authTimers.get(ws);
    if (timer !== undefined) {
      clearTimeout(timer);
      this.authTimers.delete(ws);
    }
  }

  private broadcast(payload: unknown, except?: WebSocket) {
    const raw = JSON.stringify(payload);
    for (const [socket, session] of this.sessions) {
      if (session.pendingAuth) continue;
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
