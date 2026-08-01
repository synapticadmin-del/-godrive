import { DurableObject } from "cloudflare:workers";

/**
 * Per-connection state, stored on the socket via `ws.serializeAttachment()`
 * rather than in an instance field (F-07-02).
 *
 * `ctx.acceptWebSocket()` enables hibernation: an idle inbox is evicted and
 * rebuilt on the next event with every instance field reset, while the sockets
 * stay open. The old `Map<WebSocket, Session>` therefore emptied itself
 * silently, and `broadcast()`'s fallback loop over `ctx.getWebSockets()` had
 * no way to tell an authenticated captain from a socket still waiting to prove
 * itself — so offers were pushed to unauthenticated sockets.
 *
 * Must stay JSON-serialisable. The relay socket used in proxy mode cannot be,
 * so it is kept in memory and re-established on demand — see `relays`.
 */
type Attachment = {
  userId: string;
  /** True until the first-message {"type":"auth"} handshake completes. */
  pendingAuth?: boolean;
  /** Epoch ms after which a still-pending socket is refused. */
  authDeadline?: number;
  /** True when this socket is proxied through to the captain's own inbox. */
  proxied?: boolean;
};

/** Max time a pending-auth socket may stay open before we close it (4401). */
const AUTH_TIMEOUT_MS = 10_000;

/**
 * One DO per online captain for push offers.
 * API pushes trip.offer events here by userId.
 *
 * Auth: the /ws/captain/offers route normally verifies the JWT (Authorization
 * header or the deprecated ?token= query param) and connects the captain to
 * their own inbox with ?userId=. When no token is supplied the route instead
 * forwards to a well-known "pending-auth" inbox instance with ?pendingAuth=1;
 * the client must then send {"type":"auth","token":"<jwt>"} as its first
 * message within AUTH_TIMEOUT_MS. On success this instance proxies the socket
 * pair through to the captain's real inbox; failure or timeout closes with
 * code 4401.
 */
export class CaptainInbox extends DurableObject<Env> {
  /**
   * Best-effort timers for the awake case. Cannot survive hibernation, which
   * is why the deadline is mirrored into the attachment.
   */
  authTimers: Map<WebSocket, number> = new Map();

  /**
   * Live relay sockets for proxy mode, keyed by the client socket.
   *
   * A `WebSocket` is not serialisable, so unlike the rest of the session state
   * this genuinely cannot survive hibernation. The attachment records that the
   * socket *is* proxied and for whom, and the relay is rebuilt on the next
   * frame after a wake rather than the connection silently going deaf.
   */
  private relays: Map<WebSocket, WebSocket> = new Map();

  private attachmentOf(ws: WebSocket): Attachment {
    try {
      return (ws.deserializeAttachment() as Attachment | null) ?? { userId: "unknown" };
    } catch {
      return { userId: "unknown" };
    }
  }

  private setAttachment(ws: WebSocket, attachment: Attachment) {
    ws.serializeAttachment(attachment);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/push" && request.method === "POST") {
      const body = await request.json<Record<string, unknown>>();
      const delivered = this.broadcast(body);
      return Response.json({ ok: true, clients: delivered });
    }

    if (request.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      this.ctx.acceptWebSocket(server);

      if (url.searchParams.get("pendingAuth") === "1") {
        this.setAttachment(server, {
          userId: "pending",
          pendingAuth: true,
          authDeadline: Date.now() + AUTH_TIMEOUT_MS,
        });
        this.armAuthTimeout(server);
        server.send(
          JSON.stringify({
            type: "auth.required",
            channel: "captain.inbox",
            timeoutMs: AUTH_TIMEOUT_MS,
          }),
        );
      } else {
        const userId = url.searchParams.get("userId") || "unknown";
        this.setAttachment(server, { userId });

        server.send(
          JSON.stringify({
            type: "connected",
            channel: "captain.inbox",
            userId,
          }),
        );
      }

      return new Response(null, { status: 101, webSocket: client });
    }

    return new Response("CaptainInbox: WebSocket or POST /push", { status: 400 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    if (typeof message !== "string") return;

    const session = this.attachmentOf(ws);

    if (session.pendingAuth) {
      if (session.authDeadline !== undefined && Date.now() > session.authDeadline) {
        this.closeUnauthorised(ws);
        return;
      }
      // Until authenticated the only acceptable message is the auth
      // handshake; everything else is dropped silently.
      try {
        const data = JSON.parse(message) as { type?: string; token?: string };
        if (data.type === "auth") {
          await this.completeAuth(ws, data.token);
        }
      } catch {
        ws.send(JSON.stringify({ type: "error", message: "invalid message" }));
      }
      return;
    }

    // Proxy mode (well-known pending-auth inbox): forward client frames to the
    // captain's real inbox. The target inbox itself only handles ping, which
    // we answer locally so the round trip works in both modes.
    if (session.proxied) {
      const relay = this.relays.get(ws) ?? (await this.openRelay(ws, session.userId));
      if (!relay) {
        this.closeUnauthorised(ws);
        return;
      }
      try {
        relay.send(message);
      } catch {
        this.detachRelay(ws);
      }
      return;
    }

    try {
      const data = JSON.parse(message) as { type?: string };
      if (data.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", t: Date.now() }));
      }
    } catch {
      ws.send(JSON.stringify({ type: "error", message: "invalid message" }));
    }
  }

  async webSocketClose(ws: WebSocket) {
    this.clearAuthTimeout(ws);
    this.detachRelay(ws);
  }

  async webSocketError(ws: WebSocket) {
    this.clearAuthTimeout(ws);
    this.detachRelay(ws);
  }

  private closeUnauthorised(ws: WebSocket) {
    try {
      ws.send(JSON.stringify({ type: "auth.failed" }));
    } catch {
      /* ignore */
    }
    this.clearAuthTimeout(ws);
    this.detachRelay(ws);
    try {
      ws.close(4401, "Unauthorized");
    } catch {
      /* already closed */
    }
  }

  /**
   * Open (or re-open) the server-side socket to the captain's own inbox and
   * wire the return path back to the client.
   */
  private async openRelay(ws: WebSocket, userId: string): Promise<WebSocket | null> {
    try {
      const id = this.env.CAPTAIN_INBOX.idFromName(userId);
      const stub = this.env.CAPTAIN_INBOX.get(id);
      const resp = await stub.fetch("https://inbox/ws?pendingTarget=1", {
        headers: { Upgrade: "websocket" },
      });
      const upstream = resp.webSocket;
      if (!upstream) return null;
      upstream.accept();
      this.relays.set(ws, upstream);

      upstream.addEventListener("message", (event) => {
        try {
          ws.send(event.data as string | ArrayBuffer);
        } catch {
          this.detachRelay(ws);
        }
      });
      upstream.addEventListener("close", () => {
        this.relays.delete(ws);
        try {
          ws.close();
        } catch {
          /* already closed */
        }
      });

      return upstream;
    } catch {
      return null;
    }
  }

  /**
   * Verify the first-message JWT, then connect the client to the captain's
   * own inbox via a server-side WebSocket pair and proxy frames both ways.
   * The target inbox accepts ?pendingTarget=1 to skip its own auth timeout.
   */
  private async completeAuth(ws: WebSocket, token?: string) {
    if (!token) {
      this.closeUnauthorised(ws);
      return;
    }

    try {
      const { verifyToken } = await import("../lib/jwt");
      const user = await verifyToken(token, this.env.JWT_SECRET, this.env.JWT_ISSUER);
      if (user.typ === "refresh" || (user.role !== "captain" && user.role !== "admin")) {
        this.closeUnauthorised(ws);
        return;
      }

      this.clearAuthTimeout(ws);
      this.setAttachment(ws, { userId: user.id, pendingAuth: false, proxied: true });

      const relay = await this.openRelay(ws, user.id);
      if (!relay) {
        this.closeUnauthorised(ws);
        return;
      }

      ws.send(
        JSON.stringify({ type: "connected", channel: "captain.inbox", userId: user.id }),
      );
    } catch {
      this.closeUnauthorised(ws);
    }
  }

  private detachRelay(ws: WebSocket) {
    const relay = this.relays.get(ws);
    if (relay) {
      try {
        relay.close();
      } catch {
        /* already closed */
      }
      this.relays.delete(ws);
    }
  }

  private armAuthTimeout(ws: WebSocket) {
    const timer = setTimeout(() => {
      if (this.attachmentOf(ws).pendingAuth) {
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
   * Push to every authenticated socket on this inbox. Returns how many got it.
   *
   * As in TripRoom, one loop over `ctx.getWebSockets()` replaces the old
   * map-then-fallback pair: the fallback was the half with no auth filter, and
   * after a hibernation wake it was the only half that ran.
   */
  private broadcast(payload: unknown): number {
    const raw = JSON.stringify(payload);
    let delivered = 0;
    for (const ws of this.ctx.getWebSockets()) {
      if (this.attachmentOf(ws).pendingAuth) continue;
      try {
        ws.send(raw);
        delivered += 1;
      } catch {
        /* the socket is gone; close events do the cleanup */
      }
    }
    return delivered;
  }
}
