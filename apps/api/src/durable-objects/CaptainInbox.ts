import { DurableObject } from "cloudflare:workers";

type Session = {
  ws: WebSocket;
  userId: string;
  /** True until the first-message {"type":"auth"} handshake completes. */
  pendingAuth?: boolean;
  /** While proxying: the socket on the captain's own inbox we forward to. */
  relay?: WebSocket;
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
  sessions: Map<WebSocket, Session> = new Map();
  authTimers: Map<WebSocket, number> = new Map();

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/push" && request.method === "POST") {
      const body = await request.json<Record<string, unknown>>();
      this.broadcast(body);
      return Response.json({ ok: true, clients: this.sessions.size });
    }

    if (request.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      this.ctx.acceptWebSocket(server);

      if (url.searchParams.get("pendingAuth") === "1") {
        this.sessions.set(server, { ws: server, userId: "pending", pendingAuth: true });
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
        this.sessions.set(server, { ws: server, userId });

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

    const session = this.sessions.get(ws);

    if (session?.pendingAuth) {
      // Until authenticated the only acceptable message is the auth
      // handshake; everything else is dropped silently.
      try {
        const data = JSON.parse(message) as { type?: string; token?: string };
        if (data.type === "auth") {
          await this.completeAuth(ws, session, data.token);
        }
      } catch {
        ws.send(JSON.stringify({ type: "error", message: "invalid message" }));
      }
      return;
    }

    // Proxy mode (well-known pending-auth inbox): forward client frames to the
    // captain's real inbox. The target inbox itself only handles ping, which
    // we answer locally so the round trip works in both modes.
    if (session?.relay) {
      try {
        session.relay.send(message);
      } catch {
        this.detachRelay(ws, session);
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
    const session = this.sessions.get(ws);
    if (session) this.detachRelay(ws, session);
    this.sessions.delete(ws);
  }

  async webSocketError(ws: WebSocket) {
    this.clearAuthTimeout(ws);
    const session = this.sessions.get(ws);
    if (session) this.detachRelay(ws, session);
    this.sessions.delete(ws);
  }

  /**
   * Verify the first-message JWT, then connect the client to the captain's
   * own inbox via a server-side WebSocket pair and proxy frames both ways.
   * The target inbox accepts ?pendingTarget=1 to skip its own auth timeout.
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
      if (user.typ === "refresh" || (user.role !== "captain" && user.role !== "admin")) {
        fail();
        return;
      }

      this.clearAuthTimeout(ws);
      session.pendingAuth = false;
      session.userId = user.id;

      const id = this.env.CAPTAIN_INBOX.idFromName(user.id);
      const stub = this.env.CAPTAIN_INBOX.get(id);
      const resp = await stub.fetch("https://inbox/ws?pendingTarget=1", {
        headers: { Upgrade: "websocket" },
      });
      const upstream = resp.webSocket;
      if (!upstream) {
        fail();
        return;
      }
      upstream.accept();
      session.relay = upstream;

      upstream.addEventListener("message", (event) => {
        try {
          ws.send(event.data as string | ArrayBuffer);
        } catch {
          this.detachRelay(ws, session);
        }
      });
      upstream.addEventListener("close", () => {
        try {
          ws.close();
        } catch {
          /* already closed */
        }
      });

      ws.send(
        JSON.stringify({ type: "connected", channel: "captain.inbox", userId: user.id }),
      );
    } catch {
      fail();
    }
  }

  private detachRelay(ws: WebSocket, session: Session) {
    if (session.relay) {
      try {
        session.relay.close();
      } catch {
        /* already closed */
      }
      session.relay = undefined;
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

  private broadcast(payload: unknown) {
    const raw = JSON.stringify(payload);
    for (const [socket, session] of this.sessions) {
      if (session.pendingAuth) continue;
      try {
        socket.send(raw);
      } catch {
        this.sessions.delete(socket);
      }
    }
    for (const ws of this.ctx.getWebSockets()) {
      if (this.sessions.has(ws)) continue;
      try {
        ws.send(raw);
      } catch {
        /* ignore */
      }
    }
  }
}
