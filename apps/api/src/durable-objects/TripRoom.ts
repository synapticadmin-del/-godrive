import { DurableObject } from "cloudflare:workers";

type ClientRole = "rider" | "captain" | "admin" | "unknown";

/**
 * Per-connection state.
 *
 * This is stored on the socket itself via `ws.serializeAttachment()`, **not**
 * in an instance field (F-07-02). `ctx.acceptWebSocket()` opts this object
 * into hibernation: when the room goes idle Cloudflare evicts the instance and
 * reconstructs it on the next event, at which point every instance field is
 * back to its initial value while the sockets are still open and still
 * connected to real people.
 *
 * With the state in a `Map<WebSocket, Session>` that produced two bugs, and
 * the more serious one was not the obvious one:
 *
 *  * `webSocketMessage` looked the socket up, got `undefined`, and therefore
 *    read `session?.pendingAuth` as falsy — so a socket that had **never
 *    completed the auth handshake** was promoted to a trusted client by the
 *    act of the room going quiet for a minute. It could then publish
 *    `location.captain` frames into the room.
 *  * `broadcast` fell through to `ctx.getWebSockets()` for "hibernation API
 *    sockets", and that loop had no way to tell a pending-auth socket from an
 *    authenticated one — so it sent the trip's live location to sockets that
 *    had never proved who they were.
 *
 * An attachment survives hibernation, so both checks now work on a woken
 * instance. It must stay JSON-serialisable: no `WebSocket`, no timers.
 */
type Attachment = {
  role: ClientRole;
  userId?: string;
  /** True until the first-message {"type":"auth"} handshake completes. */
  pendingAuth?: boolean;
  /** Epoch ms after which a still-pending socket is refused. */
  authDeadline?: number;
  /** The real `trips.id` for this room — see resolveTripId(). */
  tripId?: string;
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
  /**
   * Best-effort timers for the awake case only. A `setTimeout` cannot survive
   * hibernation, which is why the deadline is also written into the
   * attachment and re-checked on every message.
   */
  authTimers: Map<WebSocket, number> = new Map();
  /** In-memory cache of this room's trips.id — see resolveTripId(). */
  private tripIdCache?: string;

  private attachmentOf(ws: WebSocket): Attachment {
    try {
      return (ws.deserializeAttachment() as Attachment | null) ?? { role: "unknown" };
    } catch {
      return { role: "unknown" };
    }
  }

  private setAttachment(ws: WebSocket, attachment: Attachment) {
    ws.serializeAttachment(attachment);
  }

  /**
   * The real `trips.id` this room belongs to.
   *
   * Deliberately NOT `ctx.id.toString()`: that returns the 64-hex
   * DurableObjectId, never the name passed to `idFromName(tripId)`, because
   * `idFromName` is one-way. Trip ids look like `trip_<32 hex>` (lib/utils.ts
   * `id()`), so a D1 lookup keyed on the hex id matches no row — which is what
   * made every first-message auth handshake fail closed with 4401 and left
   * riders with no live socket for the whole trip.
   *
   * Resolution order: the `?tripId=` the Worker route forwards (authoritative)
   * → storage (survives hibernation) → `ctx.id.name` (only populated on newer
   * compatibility dates) → the hex id as a last resort.
   */
  private async resolveTripId(fromQuery?: string | null): Promise<string> {
    if (fromQuery) {
      if (this.tripIdCache !== fromQuery) {
        this.tripIdCache = fromQuery;
        await this.ctx.storage.put("tripId", fromQuery);
      }
      return fromQuery;
    }

    if (this.tripIdCache) return this.tripIdCache;

    const stored = await this.ctx.storage.get<string>("tripId");
    if (stored) {
      this.tripIdCache = stored;
      return stored;
    }

    const name = (this.ctx.id as DurableObjectId & { name?: string }).name;
    if (name) {
      this.tripIdCache = name;
      await this.ctx.storage.put("tripId", name);
      return name;
    }

    return this.ctx.id.toString();
  }

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
      const body = await request.json<Record<string, unknown>>();
      // The trip row carries its own id, so this is the cheapest reliable
      // place to learn this room's real trips.id even when a socket connects
      // before any route has forwarded ?tripId=.
      if (typeof body?.id === "string") await this.resolveTripId(body.id);
      await this.ctx.storage.put("trip", body);
      this.broadcast({ type: "trip.updated", trip: body });
      return Response.json({ ok: true });
    }

    if (request.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      this.ctx.acceptWebSocket(server);

      const tripId = await this.resolveTripId(url.searchParams.get("tripId"));

      if (url.searchParams.get("pendingAuth") === "1") {
        this.setAttachment(server, {
          role: "unknown",
          pendingAuth: true,
          authDeadline: Date.now() + AUTH_TIMEOUT_MS,
          tripId,
        });
        this.armAuthTimeout(server);
        server.send(
          JSON.stringify({ type: "auth.required", tripId, timeoutMs: AUTH_TIMEOUT_MS }),
        );
      } else {
        const role = (url.searchParams.get("role") as ClientRole) || "unknown";
        const userId = url.searchParams.get("userId") || undefined;
        this.setAttachment(server, { role, userId, tripId });

        server.send(
          JSON.stringify({
            type: "connected",
            tripId,
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

      const session = this.attachmentOf(ws);

      if (session.pendingAuth) {
        // The timer that would normally have closed this socket does not
        // survive hibernation, so the deadline is enforced here too. Without
        // this a woken pending socket could sit open indefinitely.
        if (session.authDeadline !== undefined && Date.now() > session.authDeadline) {
          this.closeUnauthorised(ws);
          return;
        }
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
          userId: session.userId ?? null,
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
  }

  async webSocketError(ws: WebSocket) {
    this.clearAuthTimeout(ws);
  }

  private closeUnauthorised(ws: WebSocket) {
    try {
      ws.send(JSON.stringify({ type: "auth.failed" }));
    } catch {
      /* ignore */
    }
    this.clearAuthTimeout(ws);
    try {
      ws.close(4401, "Unauthorized");
    } catch {
      /* already closed */
    }
  }

  /**
   * Verify the first-message JWT and complete the join flow. Mirrors the
   * checks the /ws/trips/:id route performs for header/query auth: token
   * validity, access-token type, then trip membership (rider/captain/admin).
   */
  private async completeAuth(ws: WebSocket, session: Attachment, token?: string) {
    if (!token) {
      this.closeUnauthorised(ws);
      return;
    }

    try {
      const { verifyToken } = await import("../lib/jwt");
      const user = await verifyToken(token, this.env.JWT_SECRET, this.env.JWT_ISSUER);
      if (user.typ === "refresh") {
        this.closeUnauthorised(ws);
        return;
      }

      const tripId = session.tripId ?? (await this.resolveTripId());
      const trip = await this.env.DB.prepare(`SELECT rider_id, captain_id FROM trips WHERE id = ?`)
        .bind(tripId)
        .first<{ rider_id: string; captain_id: string }>();

      if (!trip || (user.role !== "admin" && trip.rider_id !== user.id && trip.captain_id !== user.id)) {
        this.closeUnauthorised(ws);
        return;
      }

      this.clearAuthTimeout(ws);
      // Promotion is a write to the attachment, so it survives hibernation the
      // same way the pending state does.
      this.setAttachment(ws, {
        role: user.role as ClientRole,
        userId: user.id,
        pendingAuth: false,
        tripId,
      });
      ws.send(JSON.stringify({ type: "connected", tripId, role: user.role }));
    } catch {
      this.closeUnauthorised(ws);
    }
  }

  private armAuthTimeout(ws: WebSocket) {
    const timer = setTimeout(() => {
      const session = this.attachmentOf(ws);
      if (session.pendingAuth) {
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

  /**
   * Fan out to every authenticated socket in the room.
   *
   * One loop, not two. The previous version walked an in-memory map and then
   * walked `ctx.getWebSockets()` for "hibernation API sockets" it had missed —
   * but every socket here is a hibernation socket, and the second loop applied
   * no auth filter at all. `ctx.getWebSockets()` is the complete and correct
   * list on both a warm and a freshly woken instance; the attachment says
   * whether each one is allowed to hear this.
   */
  private broadcast(payload: unknown, except?: WebSocket) {
    const raw = JSON.stringify(payload);
    for (const ws of this.ctx.getWebSockets()) {
      if (except && ws === except) continue;
      if (this.attachmentOf(ws).pendingAuth) continue;
      try {
        ws.send(raw);
      } catch {
        /* the socket is gone; close events do the cleanup */
      }
    }
  }
}
